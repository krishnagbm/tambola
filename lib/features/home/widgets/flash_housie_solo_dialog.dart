import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/flash_housie_config.dart';
import 'level_zero_solo_view.dart';

class FlashHousieSoloDialog extends StatefulWidget {
  final VoidCallback? onLevelCompleted;
  final String initialGameId;

  const FlashHousieSoloDialog({
    super.key,
    this.onLevelCompleted,
    this.initialGameId = 'level_0a_make',
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onLevelCompleted,
    String initialGameId = 'level_0a_make',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FlashHousieSoloDialog(
        onLevelCompleted: onLevelCompleted,
        initialGameId: initialGameId,
      ),
    );
  }

  @override
  State<FlashHousieSoloDialog> createState() => _FlashHousieSoloDialogState();
}

class _FlashHousieSoloDialogState extends State<FlashHousieSoloDialog> {
  late String _activeGameId;
  final Set<String> _completedGameIds = <String>{};

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

  static const List<(String, String, String, String)> _release1Games = [
    (
      'level_0a_make',
      '🎓 0A: Make™',
      '🎓 LEVEL 0A • SOLO',
      'MakeHousie™ Solo Arena',
    ),
    (
      'level_0b_fix',
      '🔍 0B: Fix™',
      '🔍 LEVEL 0B • SOLO',
      'FixHousie™ Solo Arena',
    ),
    (
      'level_0c_math',
      '➕ 0C: Math™',
      '➕ LEVEL 0C • SOLO',
      'MathHousie™ Solo Arena',
    ),
    (
      'level_0d_sum',
      '🧮 0D: Sum™',
      '🧮 LEVEL 0D • SOLO',
      'SumHousie™ Solo Arena',
    ),
    (
      'level_1_flash',
      '⚡ Lvl 1: Flash™',
      '⚡ LEVEL 1 • SOLO',
      'FlashHousie™ Solo Arena',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _activeGameId = widget.initialGameId;
    _startNewSoloRound(_selectedMode, autoStart: false);
    _loadCompletedGames();
  }

  Future<void> _loadCompletedGames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = <String>{};
      for (final g in _release1Games) {
        final id = g.$1;
        final key = id == 'level_1_flash'
            ? 'dabhousie_skill_level_1_completed'
            : 'dabhousie_skill_${id}_completed';
        if (prefs.getBool(key) == true) {
          done.add(id);
        }
      }
      if (!mounted) return;
      setState(() {
        _completedGameIds
          ..clear()
          ..addAll(done);
      });
    } catch (_) {}
  }

  void _selectGameTab(String gameId) {
    if (_activeGameId == gameId) return;
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    _autoCallTimer?.cancel();
    _autoCallTimer = null;
    if (gameId == 'level_1_flash') {
      _startNewSoloRound(_selectedMode, autoStart: false);
    }
    setState(() {
      _activeGameId = gameId;
    });
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

  void _startNewSoloRound(String mode, {bool autoStart = false}) {
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
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
    final cycleSpec = baseConfig.activeCycleSpec.copyWith(
      startedAtMs: autoStart ? nowMs : null,
      calledNumbers: const [],
    );

    setState(() {
      _selectedMode = mode;
      _config = baseConfig.copyWith(cycles: [cycleSpec]);
      _recalledNumbers.clear();
      _wrongFlashingCells.clear();
      _wrongTapCount = 0;
      _freezeUntilMs = 0;
      _totalReactionMs = 0;
      _callingStartedAtMs = null;
      _lastBallCalledAtMs = null;
      _roundCompleted = false;
    });
    if (autoStart) {
      _startUiTicker();
    }
  }

  void _launchActiveRound() {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startedCycle = spec.copyWith(
      startedAtMs: nowMs,
      calledNumbers: const [],
    );
    setState(() {
      _config = _config.copyWith(cycles: [startedCycle]);
      _roundCompleted = false;
    });
    _startUiTicker();
  }

  String _modeShortName(String mode) {
    switch (mode) {
      case FlashHousieConfig.modeFlash10:
        return 'Flash 10';
      case FlashHousieConfig.modeFlash15:
        return 'Flash 15';
      default:
        return 'Flash 5';
    }
  }

  void _checkNeuroWaveTransition() {
    final spec = _config.activeCycleSpec;
    if (spec.startedAtMs == null) return;
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
      TambolaAudioCaller().announceNumber(nextBall, useNicknames: false);
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
      _lastBallCalledAtMs = DateTime.now().millisecondsSinceEpoch;
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
      _loadCompletedGames();
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
    if (waveState.phase == NeuroWavePhase.waitingToStart) {
      return '${_config.activeCycleSpec.trueNumbers.length} Balls';
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
    if (waveState.phase == NeuroWavePhase.waitingToStart) {
      return 'Ready Mode';
    }
    if (!waveState.isCallingReady) {
      return 'Countdown';
    }
    return 'Play Clock';
  }

  String _formatClockBottomCaption(NeuroWaveState waveState) {
    if (_roundCompleted) {
      final count = _recalledNumbers.isEmpty ? 1 : _recalledNumbers.length;
      final avgSec = (_totalReactionMs / 1000) / count;
      final roundSec =
          (_callingStartedAtMs != null && _lastBallCalledAtMs != null)
          ? ((_lastBallCalledAtMs! - _callingStartedAtMs!) / 1000).clamp(
              1.0,
              999.0,
            )
          : 0.0;
      return 'Avg ${avgSec.toStringAsFixed(1)}s • Rnd ${roundSec.toStringAsFixed(0)}s';
    }
    if (waveState.phase == NeuroWavePhase.waitingToStart) {
      return 'Pick Mode & Start';
    }
    if (waveState.isCallingReady) {
      return 'Auto-draw 3.5s';
    }
    return 'Get Ready';
  }

  (String, String) _activeBadgeAndTitle() {
    for (final g in _release1Games) {
      if (g.$1 == _activeGameId) {
        return (g.$3, g.$4);
      }
    }
    return ('⚡ LEVEL 1 • SOLO', 'FlashHousie™ Solo Arena');
  }

  @override
  Widget build(BuildContext context) {
    final spec = _config.activeCycleSpec;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final waveState = spec.computeNeuroWaveState(nowMs);
    final isWaitingToStart =
        !_roundCompleted && waveState.phase == NeuroWavePhase.waitingToStart;
    final isFrozen = !_roundCompleted && nowMs < _freezeUntilMs;
    final freezeRemSec =
        isFrozen ? ((_freezeUntilMs - nowMs) / 1000).ceil() : 0;
    final latestBall = spec.latestCalledNumber;
    final wonAll = _recalledNumbers.length >= spec.trueNumbers.length;
    final activeQuadLabel = spec.activeQuadrants.map((q) => 'Q$q').join(' + ');
    final (badgeText, titleText) = _activeBadgeAndTitle();

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
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titleText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_activeGameId == 'level_1_flash')
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
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
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

              // 1B. Release 1 Skill Game Switcher Bar (Natural Order: 0A Make -> 0B Fix -> 0C Math -> 0D Sum -> Lvl 1 Flash)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _release1Games.map((g) {
                    final id = g.$1;
                    final label = g.$2;
                    final isSelected = _activeGameId == id;
                    final isDone = _completedGameIds.contains(id);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => _selectGameTab(id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF10B981).withValues(alpha: 0.22)
                                : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF10B981)
                                  : (isDone
                                        ? const Color(0xFF10B981).withValues(
                                            alpha: 0.45,
                                          )
                                        : const Color(0xFF2E3A59)),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: isSelected
                                      ? const Color(0xFF34D399)
                                      : Colors.white70,
                                ),
                              ),
                              if (isDone) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 13,
                                  color: Color(0xFF34D399),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              if (_activeGameId != 'level_1_flash') ...[
                LevelZeroSoloView(
                  gameId: _activeGameId,
                  onLevelCompleted: () {
                    _loadCompletedGames();
                    widget.onLevelCompleted?.call();
                  },
                  onSelectGameId: _selectGameTab,
                ),
              ] else ...[
                // 2. Mode Selector & New Card / Reset Row
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
                      onPressed: () =>
                          _startNewSoloRound(_selectedMode, autoStart: false),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        isWaitingToStart ? 'Shuffle Card' : 'New Card / Reset',
                      ),
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

                // 3. Fixed-Height Status Banner
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
                                  : (isWaitingToStart
                                        ? Icons.play_circle_fill_rounded
                                        : (waveState.isCallingReady
                                              ? Icons.touch_app_rounded
                                              : Icons.visibility_rounded))),
                        color: isFrozen
                            ? const Color(0xFFF87171)
                            : (_roundCompleted
                                  ? AppTheme.secondaryColor
                                  : (isWaitingToStart || waveState.isCallingReady
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
                                        : (isWaitingToStart
                                              ? '🎯 ${_modeShortName(_selectedMode)} Ready • Active: $activeQuadLabel (${spec.trueNumbers.length} Target Numbers)'
                                              : waveState.statusLabel)),
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
                                  ? 'Great session! Tap "Play Again" below or pick Flash 10 / Flash 15.'
                                  : (isWaitingToStart
                                        ? '1️⃣ Pick Flash 5/10/15 above  •  2️⃣ See [•] slots on grid  •  3️⃣ Tap "▶ Start" when ready!'
                                        : (waveState.isCallingReady
                                              ? 'Tap called numbers using memory & column logic! Wrong guess = -3 pts & 3s freeze.'
                                              : 'Memorize active column numbers before they lock into [?] mystery cells!')),
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

                // 4. 3-Column HUD Card
                Container(
                  constraints: const BoxConstraints(minHeight: 88),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF2E334D),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 4,
                        child: isWaitingToStart
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Active: $activeQuadLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: _launchActiveRound,
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Start ${_modeShortName(_selectedMode)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              )
                            : (_roundCompleted
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          wonAll
                                              ? '🎉 Round Won!'
                                              : 'Round Ended',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF34D399),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ElevatedButton.icon(
                                          onPressed: () => _startNewSoloRound(
                                            _selectedMode,
                                            autoStart: true,
                                          ),
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
                                            backgroundColor:
                                                AppTheme.secondaryColor,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
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
                                            latestBall != null
                                                ? '$latestBall'
                                                : '—',
                                            style: TextStyle(
                                              fontSize: 20,
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
                                        const SizedBox(width: 8),
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
                                                  fontSize: 12.5,
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
                                    )),
                      ),

                      Container(
                        width: 1,
                        height: 54,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: const Color(0xFF2E334D),
                      ),

                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'SCORE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$_netScore pts',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.secondaryColor,
                                  height: 1.1,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
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
                        height: 54,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: const Color(0xFF2E334D),
                      ),

                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 12,
                                  color: Color(0xFFFFD54F),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    _formatClockSubtitle(
                                      waveState,
                                    ).toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF94A3B8),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatClockDisplay(waveState, nowMs),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFFF59D),
                                  height: 1.1,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                _formatClockBottomCaption(waveState),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 5. 3x9 Interactive Matrix
                _buildSoloTicketMatrix(spec, waveState, isFrozen),
              ],
              const SizedBox(height: 10),
              const Text(
                '© 2026 DabHousie™ • MakeHousie™, FixHousie™, MathHousie™, SumHousie™, FlashHousie™, RowHousie™, FastTap™, SwapHousie™, BlastHousie™, StickHousie™ & NeuroWave™ are proprietary game formats & copyrighted visual expressions of Digital App Studio.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  height: 1.3,
                ),
              ),
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
      onSelected: (_) => _startNewSoloRound(mode, autoStart: false),
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
