import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/flash_housie_config.dart';

class FlashHousieSoloDialog extends StatefulWidget {
  final VoidCallback? onLevelCompleted;

  const FlashHousieSoloDialog({super.key, this.onLevelCompleted});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onLevelCompleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FlashHousieSoloDialog(
        onLevelCompleted: onLevelCompleted,
      ),
    );
  }

  @override
  State<FlashHousieSoloDialog> createState() => _FlashHousieSoloDialogState();
}

class _FlashHousieSoloDialogState extends State<FlashHousieSoloDialog> {
  String _selectedMode = FlashHousieConfig.modeFlash5;
  late FlashHousieConfig _config;
  Timer? _uiTickTimer;
  Timer? _autoCallTimer;

  final Set<int> _recalledNumbers = <int>{};
  final Set<String> _wrongFlashingCells = <String>{};
  int _wrongTapCount = 0;
  int _freezeUntilMs = 0;
  int _totalReactionMs = 0;
  int? _lastBallCalledAtMs;
  bool _roundCompleted = false;
  bool _voiceEnabled = true;

  @override
  void initState() {
    super.initState();
    _startNewSoloRound(_selectedMode);
    _uiTickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      _checkNeuroWaveTransition();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTickTimer?.cancel();
    _autoCallTimer?.cancel();
    super.dispose();
  }

  void _startNewSoloRound(String mode) {
    _autoCallTimer?.cancel();
    final baseConfig = FlashHousieConfig.generate(
      mode: mode,
      totalCycles: 1,
      cellsPerQuadrant: 5,
      decoysPerColumn: 2,
      random: Random(),
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startedCycle = baseConfig.activeCycleSpec.copyWith(
      startedAtMs: nowMs,
      calledNumbers: const [],
    );

    setState(() {
      _selectedMode = mode;
      _config = baseConfig.copyWith(cycles: [startedCycle]);
      _recalledNumbers.clear();
      _wrongFlashingCells.clear();
      _wrongTapCount = 0;
      _freezeUntilMs = 0;
      _totalReactionMs = 0;
      _lastBallCalledAtMs = null;
      _roundCompleted = false;
    });
  }

  void _checkNeuroWaveTransition() {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waveState = spec.computeNeuroWaveState(nowMs);
    if (waveState.isCallingReady &&
        spec.calledNumbers.isEmpty &&
        _autoCallTimer == null &&
        !_roundCompleted) {
      // Immediately draw first ball as soon as NeuroWave locks into [?]
      _drawNextBall();
      _autoCallTimer = Timer.periodic(const Duration(milliseconds: 3600), (_) {
        if (!mounted || _roundCompleted) return;
        _drawNextBall();
      });
    }
  }

  void _drawNextBall() {
    final spec = _config.activeCycleSpec;
    if (_roundCompleted) return;
    if (spec.calledNumbers.length >= spec.drawPool.length) {
      _finishRound();
      return;
    }
    final nextBall = spec.drawPool[spec.calledNumbers.length];
    final updatedCalled = <int>[...spec.calledNumbers, nextBall];
    final updatedSpec = spec.copyWith(calledNumbers: updatedCalled);

    setState(() {
      _config = _config.copyWith(cycles: [updatedSpec]);
      _lastBallCalledAtMs = DateTime.now().millisecondsSinceEpoch;
    });

    if (_voiceEnabled) {
      TambolaAudioCaller().announceNumber(nextBall);
    }

    // If all pool numbers drawn and player hasn't finished all true numbers, conclude after a brief window
    if (updatedCalled.length >= spec.drawPool.length) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_roundCompleted) {
          _finishRound();
        }
      });
    }
  }

  Future<void> _finishRound() async {
    _autoCallTimer?.cancel();
    _autoCallTimer = null;
    if (!mounted) return;
    final spec = _config.activeCycleSpec;
    final wonAll = _recalledNumbers.length >= spec.trueNumbers.length;
    setState(() {
      _roundCompleted = true;
    });
    if (wonAll) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('dabhousie_skill_level_1_completed', true);
        final prevBest = prefs.getInt('dabhousie_skill_level_1_best_score') ?? 0;
        if (_netScore > prevBest) {
          await prefs.setInt('dabhousie_skill_level_1_best_score', _netScore);
        }
      } catch (_) {}
      widget.onLevelCompleted?.call();
    }
  }

  int get _netScore =>
      (_recalledNumbers.length * 10) - (_wrongTapCount * 3);

  void _handleCellTap(int row, int col, int trueVal) {
    if (trueVal == 0 || _roundCompleted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _freezeUntilMs) return;

    final spec = _config.activeCycleSpec;
    final waveState = spec.computeNeuroWaveState(nowMs);
    if (!waveState.isCallingReady) return;
    if (!spec.isColumnInActiveQuadrant(col)) return;
    if (_recalledNumbers.contains(trueVal)) return;

    final calledSet = spec.calledNumbers.toSet();
    if (calledSet.contains(trueVal)) {
      final reaction = _lastBallCalledAtMs != null
          ? (nowMs - _lastBallCalledAtMs!).clamp(150, 15000)
          : 1200;
      setState(() {
        _recalledNumbers.add(trueVal);
        _totalReactionMs += reaction;
      });
      if (_recalledNumbers.length >= spec.trueNumbers.length) {
        _finishRound();
      }
    } else {
      final cellKey = '${row}_$col';
      setState(() {
        _wrongTapCount++;
        _totalReactionMs += 3000;
        _freezeUntilMs = nowMs + 3000;
        _wrongFlashingCells.add(cellKey);
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _wrongFlashingCells.remove(cellKey));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waveState = spec.computeNeuroWaveState(nowMs);
    final isFrozen = nowMs < _freezeUntilMs;
    final freezeRemSec = isFrozen ? ((_freezeUntilMs - nowMs) / 1000).ceil() : 0;
    final latestBall = spec.latestCalledNumber;
    final wonAll = _recalledNumbers.length >= spec.trueNumbers.length;

    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '⚡ LEVEL 1 • SOLO PRACTICE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'FlashHousie™ Instant Solo Arena',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _voiceEnabled ? Icons.volume_up : Icons.volume_off,
                      color: _voiceEnabled
                          ? AppTheme.secondaryColor
                          : Colors.white54,
                      size: 20,
                    ),
                    tooltip: 'Toggle Voice Caller',
                    onPressed: () =>
                        setState(() => _voiceEnabled = !_voiceEnabled),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: 'Close Solo Practice',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Mode Selector & Restart Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildModeChip(
                        FlashHousieConfig.modeFlash5,
                        'Flash 5 (1 Quad)',
                      ),
                      _buildModeChip(
                        FlashHousieConfig.modeFlash10,
                        'Flash 10 (2 Quads)',
                      ),
                      _buildModeChip(
                        FlashHousieConfig.modeFlash15,
                        'Flash 15 (3 Quads)',
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _startNewSoloRound(_selectedMode),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('New Card / Restart'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.secondaryColor,
                      side: BorderSide(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.6),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // NeuroWave / Calling Status Banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: waveState.isCallingReady
                        ? const [Color(0xFF064E3B), Color(0xFF0F172A)]
                        : const [Color(0xFF311042), Color(0xFF0F172A)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: waveState.isCallingReady
                        ? const Color(0xFF10B981)
                        : AppTheme.secondaryColor,
                    width: 1.4,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      waveState.isCallingReady
                          ? Icons.touch_app_rounded
                          : Icons.visibility_rounded,
                      color: waveState.isCallingReady
                          ? const Color(0xFF34D399)
                          : AppTheme.secondaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _roundCompleted
                                ? (wonAll
                                      ? '🏆 LEVEL 1 CLEARED! ALL ${spec.trueNumbers.length} NUMBERS RECALLED!'
                                      : '⏱️ ROUND FINISHED — ${_recalledNumbers.length}/${spec.trueNumbers.length} RECALLED')
                                : waveState.statusLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            waveState.isCallingReady
                                ? 'Combine spatial memory & column decade logic (Col 1: 1–9, Col 2: 10–19...) to tap called numbers! Wrong guess = -3 pts & 3s freeze.'
                                : 'Watch the active column numbers carefully before they lock into [?] mystery cells!',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!waveState.isCallingReady) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090D16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFD54F),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '⏱ 00:${waveState.remainingSeconds.toString().padLeft(2, '0')}s',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFF59D),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Live Ball Call + Scoreboard Strip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: latestBall != null
                                ? AppTheme.secondaryColor
                                : const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            latestBall != null ? '$latestBall' : '—',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: latestBall != null
                                  ? Colors.black
                                  : Colors.white54,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              latestBall != null
                                  ? 'Ball #$latestBall Drawn (${spec.calledNumbers.length}/${spec.drawPool.length})'
                                  : 'Waiting for NeuroWave™ Sweep...',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (spec.calledNumbers.isNotEmpty)
                              Text(
                                'Recent: ${spec.calledNumbers.reversed.take(6).join(', ')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildStatPill(
                          'Recalled',
                          '${_recalledNumbers.length}/${spec.trueNumbers.length}',
                          const Color(0xFF10B981),
                        ),
                        _buildStatPill(
                          'Wrong',
                          '$_wrongTapCount (-${_wrongTapCount * 3})',
                          const Color(0xFFF87171),
                        ),
                        _buildStatPill(
                          'Net Score',
                          '$_netScore pts',
                          AppTheme.secondaryColor,
                        ),
                        if (waveState.isCallingReady && !_roundCompleted)
                          ElevatedButton.icon(
                            onPressed: _drawNextBall,
                            icon: const Icon(Icons.skip_next_rounded, size: 16),
                            label: const Text('Next Ball'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryLight,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isFrozen) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentDanger.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accentDanger),
                  ),
                  child: Text(
                    '❄️ Wrong guess penalty! Ticket frozen for ${freezeRemSec}s (-3 pts)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 3x9 Interactive Matrix
              _buildSoloTicketMatrix(spec, waveState, isFrozen),

              if (_roundCompleted) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: wonAll
                        ? const Color(0xFF064E3B).withValues(alpha: 0.6)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: wonAll
                          ? const Color(0xFF10B981)
                          : AppTheme.secondaryColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        wonAll
                            ? Icons.emoji_events_rounded
                            : Icons.replay_circle_filled_rounded,
                        color: wonAll
                            ? AppTheme.secondaryColor
                            : Colors.white70,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          wonAll
                              ? 'Awesome job! You scored $_netScore pts (${(_totalReactionMs / 1000).toStringAsFixed(1)}s total reaction) and completed Level 1 Solo! Next levels open sequentially as they launch.'
                              : 'Round complete! You recalled ${_recalledNumbers.length}/${spec.trueNumbers.length} numbers ($_netScore pts). Try again to recall all ${spec.trueNumbers.length}!',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _startNewSoloRound(_selectedMode),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text(
                          'Play Again',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String mode, String label) {
    final isSelected = _selectedMode == mode;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.black : Colors.white,
        ),
      ),
      selected: isSelected,
      selectedColor: AppTheme.secondaryColor,
      backgroundColor: AppTheme.darkCard,
      onSelected: (_) => _startNewSoloRound(mode),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoloTicketMatrix(
    FlashHousieCycleSpec spec,
    NeuroWaveState waveState,
    bool isFrozen,
  ) {
    final matrix = spec.ticketMatrix;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Quadrant header bar
          Row(
            children: List.generate(3, (qIdx) {
              final qNum = qIdx + 1;
              final isActive = spec.activeQuadrants.contains(qNum);
              final ranges = ['Cols 1–3 (1–29)', 'Cols 4–6 (30–59)', 'Cols 7–9 (60–90)'];
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.secondaryColor.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? AppTheme.secondaryColor.withValues(alpha: 0.65)
                          : Colors.white12,
                    ),
                  ),
                  child: Text(
                    isActive
                        ? '⚡ Q$qNum ACTIVE • ${ranges[qIdx]}'
                        : '🔒 Q$qNum • ${ranges[qIdx]}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? AppTheme.secondaryColor
                          : Colors.white38,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          for (int r = 0; r < 3; r++)
            Padding(
              padding: EdgeInsets.only(bottom: r < 2 ? 6 : 0),
              child: Row(
                children: [
                  for (int c = 0; c < 9; c++) ...[
                    if (c == 3 || c == 6) const SizedBox(width: 6),
                    Expanded(
                      child: _buildSoloCell(
                        row: r,
                        col: c,
                        trueVal: matrix[r][c],
                        spec: spec,
                        waveState: waveState,
                        isFrozen: isFrozen,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSoloCell({
    required int row,
    required int col,
    required int trueVal,
    required FlashHousieCycleSpec spec,
    required NeuroWaveState waveState,
    required bool isFrozen,
  }) {
    final isEmpty = trueVal == 0;
    final inActiveQuad = spec.isColumnInActiveQuadrant(col);
    final isRecalled = !isEmpty && _recalledNumbers.contains(trueVal);
    final isWrongFlash = _wrongFlashingCells.contains('${row}_$col');
    final isSpotlightCol =
        waveState.phase == NeuroWavePhase.columnWave &&
        waveState.visibleColumn == col;

    String label = '';
    Color bg = const Color(0xFF1E293B);
    Color border = const Color(0xFF334155);
    Color textColor = Colors.white;

    if (isEmpty) {
      bg = const Color(0xFF0B1120);
      border = const Color(0xFF1E293B);
    } else if (!inActiveQuad) {
      label = '·';
      bg = const Color(0xFF111827);
      border = const Color(0xFF1F2937);
      textColor = Colors.white24;
    } else if (isRecalled) {
      label = '$trueVal';
      bg = const Color(0xFF059669);
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else if (isWrongFlash) {
      label = '✖';
      bg = const Color(0xFFDC2626);
      border = const Color(0xFFF87171);
      textColor = Colors.white;
    } else if (isSpotlightCol || _roundCompleted) {
      label = '$trueVal';
      bg = isSpotlightCol
          ? AppTheme.secondaryColor
          : const Color(0xFF334155);
      border = isSpotlightCol
          ? Colors.white
          : AppTheme.secondaryColor.withValues(alpha: 0.6);
      textColor = isSpotlightCol ? Colors.black : AppTheme.secondaryColor;
    } else if (waveState.isCallingReady) {
      label = '?';
      bg = const Color(0xFF312E81);
      border = AppTheme.secondaryColor.withValues(alpha: 0.75);
      textColor = AppTheme.secondaryColor;
    } else {
      label = '•';
      bg = const Color(0xFF1E1B4B);
      border = const Color(0xFF3730A3);
      textColor = Colors.white38;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: (!isEmpty && inActiveQuad && waveState.isCallingReady && !isFrozen)
            ? () => _handleCellTap(row, col, trueVal)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border,
              width: isSpotlightCol || isRecalled ? 2 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
