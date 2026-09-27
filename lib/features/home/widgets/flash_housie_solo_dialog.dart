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
  int? _callingStartedAtMs;
  int? _lastBallCalledAtMs;
  bool _roundCompleted = false;
  bool _voiceEnabled = true;

  @override
  void initState() {
    super.initState();
    _startNewSoloRound(_selectedMode);
  }

  @override
  void dispose() {
    _uiTickTimer?.cancel();
    _autoCallTimer?.cancel();
    super.dispose();
  }

  void _startUiTicker() {
    _uiTickTimer?.cancel();
    _uiTickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _roundCompleted) return;
      _checkNeuroWaveTransition();
      setState(() {});
    });
  }

  void _startNewSoloRound(String mode) {
    _autoCallTimer?.cancel();
    _autoCallTimer = null;
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
      _callingStartedAtMs = null;
      _lastBallCalledAtMs = null;
      _roundCompleted = false;
    });
    _startUiTicker();
  }

  void _checkNeuroWaveTransition() {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waveState = spec.computeNeuroWaveState(nowMs);
    if (waveState.isCallingReady &&
        spec.calledNumbers.isEmpty &&
        _autoCallTimer == null &&
        !_roundCompleted) {
      _callingStartedAtMs = nowMs;
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
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    if (!mounted) return;
    final spec = _config.activeCycleSpec;
    final wonAll = _recalledNumbers.length >= spec.trueNumbers.length;
    setState(() {
      _roundCompleted = true;
      _freezeUntilMs = 0;
    });
    if (wonAll) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('dabhousie_skill_level_1_completed', true);
        final prevBest =
            prefs.getInt('dabhousie_skill_level_1_best_score') ?? 0;
        if (_netScore > prevBest) {
          await prefs.setInt('dabhousie_skill_level_1_best_score', _netScore);
        }
      } catch (_) {}
      widget.onLevelCompleted?.call();
    }
  }

  int get _netScore => (_recalledNumbers.length * 10) - (_wrongTapCount * 3);

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
        if (mounted && !_roundCompleted) {
          setState(() => _wrongFlashingCells.remove(cellKey));
        }
      });
    }
  }

  String _formatClockDisplay(NeuroWaveState waveState, int nowMs) {
    if (_roundCompleted) {
      return '${(_totalReactionMs / 1000).toStringAsFixed(1)}s';
    }
    if (!waveState.isCallingReady) {
      return '00:${waveState.remainingSeconds.toString().padLeft(2, '0')}s';
    }
    final elapsedSec = _callingStartedAtMs != null
        ? ((nowMs - _callingStartedAtMs!) / 1000).clamp(0.0, 999.0)
        : 0.0;
    return '${elapsedSec.toStringAsFixed(1)}s';
  }

  String _formatClockSubtitle(NeuroWaveState waveState) {
    if (_roundCompleted) {
      return 'Reaction Time';
    }
    if (!waveState.isCallingReady) {
      return 'Wave Countdown';
    }
    return 'Play Clock';
  }

  @override
  Widget build(BuildContext context) {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waveState = spec.computeNeuroWaveState(nowMs);
    final isFrozen = !_roundCompleted && nowMs < _freezeUntilMs;
    final freezeRemSec =
        isFrozen ? ((_freezeUntilMs - nowMs) / 1000).ceil() : 0;
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
        constraints: const BoxConstraints(maxWidth: 740),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar
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
                      '⚡ LEVEL 1 • SOLO',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'FlashHousie™ Solo Arena',
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
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () =>
                        setState(() => _voiceEnabled = !_voiceEnabled),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: 'Close Solo Arena',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 2. Mode Selector & Restart Row
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

              // 3. Fixed-Height Status Banner (handles Wave, Calling, Freeze & Completion without vertical layout shift)
              Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isFrozen
                        ? const [Color(0xFF450A0A), Color(0xFF0F172A)]
                        : (waveState.isCallingReady || _roundCompleted
                              ? const [Color(0xFF064E3B), Color(0xFF0F172A)]
                              : const [Color(0xFF311042), Color(0xFF0F172A)]),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isFrozen
                        ? AppTheme.accentDanger
                        : (waveState.isCallingReady || _roundCompleted
                              ? const Color(0xFF10B981)
                              : AppTheme.secondaryColor),
                    width: 1.4,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isFrozen
                          ? Icons.ac_unit_rounded
                          : (_roundCompleted
                                ? Icons.emoji_events_rounded
                                : (waveState.isCallingReady
                                      ? Icons.touch_app_rounded
                                      : Icons.visibility_rounded)),
                      color: isFrozen
                          ? const Color(0xFFF87171)
                          : (_roundCompleted
                                ? AppTheme.secondaryColor
                                : (waveState.isCallingReady
                                      ? const Color(0xFF34D399)
                                      : AppTheme.secondaryColor)),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isFrozen
                                ? '❄️ WRONG GUESS PENALTY (-3 PTS) — FROZEN FOR ${freezeRemSec}s'
                                : (_roundCompleted
                                      ? (wonAll
                                            ? '🏆 LEVEL 1 CLEARED! ALL ${spec.trueNumbers.length} NUMBERS RECALLED!'
                                            : '⏱️ ROUND OVER — ${_recalledNumbers.length}/${spec.trueNumbers.length} NUMBERS RECALLED')
                                      : waveState.statusLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _roundCompleted
                                ? 'Great session! Tap "Play Again" below or try Flash 10 / Flash 15.'
                                : (waveState.isCallingReady
                                      ? 'Tap called numbers using memory & column logic! Wrong guess = -3 pts & 3s freeze.'
                                      : 'Memorize active column numbers before they lock into [?] mystery cells!'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4. 3-Column HUD Card:
              //    - Col 1 (Left): Current Ball (hidden when round is over; replaced by Play Again)
              //    - Col 2 (Middle): Prominent Large SCORE
              //    - Col 3 (Right Edge): Prominent Large CLOCK / TIME
              Container(
                constraints: const BoxConstraints(minHeight: 88),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E334D), width: 1.5),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // LEFT COLUMN: Drawn Ball (active) OR Round Complete / Play Again (when over)
                      Expanded(
                        flex: 4,
                        child: _roundCompleted
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    wonAll ? '🎉 Round Won!' : 'Round Ended',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _startNewSoloRound(_selectedMode),
                                    icon: const Icon(
                                      Icons.replay_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Play Again',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: latestBall != null
                                          ? AppTheme.secondaryColor
                                          : const Color(0xFF1E293B),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: latestBall != null
                                            ? Colors.white
                                            : const Color(0xFF334155),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      latestBall != null ? '$latestBall' : '—',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: latestBall != null
                                            ? Colors.black
                                            : Colors.white54,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          latestBall != null
                                              ? 'Ball #$latestBall (${spec.calledNumbers.length}/${spec.drawPool.length})'
                                              : 'Spot Numbers',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          spec.calledNumbers.isNotEmpty
                                              ? 'Recent: ${spec.calledNumbers.reversed.take(5).join(', ')}'
                                              : 'NeuroWave™ active',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: const Color(0xFF2E334D),
                      ),

                      // MIDDLE COLUMN: Prominent Large SCORE
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'SCORE',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$_netScore pts',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.secondaryColor,
                                height: 1.1,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '✓ ${_recalledNumbers.length}/${spec.trueNumbers.length}  •  ✖ $_wrongTapCount',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        color: const Color(0xFF2E334D),
                      ),

                      // RIGHT COLUMN (Right Edge): Prominent Large CLOCK / TIME
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 13,
                                  color: Color(0xFFFFD54F),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatClockSubtitle(waveState).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF94A3B8),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatClockDisplay(waveState, nowMs),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFFFF59D),
                                height: 1.1,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              waveState.isCallingReady && !_roundCompleted
                                  ? 'Auto-draw 3.5s'
                                  : (_roundCompleted
                                        ? 'Final Time'
                                        : 'Get Ready'),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 5. 3x9 Interactive Matrix (Rock-solid fixed height)
              _buildSoloTicketMatrix(spec, waveState, isFrozen),
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
          // Single-line Quadrant header bar (never wraps unevenly)
          Row(
            children: List.generate(3, (qIdx) {
              final qNum = qIdx + 1;
              final isActive = spec.activeQuadrants.contains(qNum);
              final ranges = ['Cols 1–3 (1–29)', 'Cols 4–6 (30–59)', 'Cols 7–9 (60–90)'];
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
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
                        ? '⚡ Q$qNum • ${ranges[qIdx]}'
                        : '🔒 Q$qNum • ${ranges[qIdx]}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
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
      bg = isSpotlightCol ? AppTheme.secondaryColor : const Color(0xFF334155);
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
        onTap: (!isEmpty &&
                inActiveQuad &&
                waveState.isCallingReady &&
                !isFrozen &&
                !_roundCompleted)
            ? () => _handleCellTap(row, col, trueVal)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
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
