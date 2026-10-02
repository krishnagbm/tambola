import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/flash_housie_config.dart';
import '../../../models/level_zero_skill_engine.dart';
import 'level_zero_solo_view.dart';
import 'skill_friend_squad_controller.dart';

class FlashHousieSoloDialog extends StatefulWidget {
  final VoidCallback? onLevelCompleted;
  final String initialGameId;
  final bool initialFriendMode;

  const FlashHousieSoloDialog({
    super.key,
    this.onLevelCompleted,
    this.initialGameId = 'level_0a_make',
    this.initialFriendMode = false,
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onLevelCompleted,
    String initialGameId = 'level_0a_make',
    bool initialFriendMode = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FlashHousieSoloDialog(
        onLevelCompleted: onLevelCompleted,
        initialGameId: initialGameId,
        initialFriendMode: initialFriendMode,
      ),
    );
  }

  @override
  State<FlashHousieSoloDialog> createState() => _FlashHousieSoloDialogState();
}

class _FlashHousieSoloDialogState extends State<FlashHousieSoloDialog> {
  late String _activeGameId;
  final Set<String> _completedGameIds = <String>{};

  late final SkillFriendSquadController _squadController;
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  bool _showJoinCodeInput = false;
  int _sharedSeed = 1001;
  String _sharedSubMode = 'make_5_quad';
  bool _sharedAutoStart = false;

  String _selectedMode = FlashHousieConfig.modeFlash5;
  late FlashHousieConfig _config;
  Timer? _uiTickTimer;
  Timer? _autoCallTimer;
  String? _squadCopiedNotice;
  Timer? _squadNoticeTimer;

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
    _showJoinCodeInput = widget.initialFriendMode;
    _sharedSeed = 1000 + Random().nextInt(899999);
    _squadController = SkillFriendSquadController();
    _squadController.addListener(_onSquadChanged);
    _squadController.onRemoteRoundSync = (gameId, subMode, seed, autoStart) {
      if (!mounted) return;
      setState(() {
        _activeGameId = gameId;
        _sharedSubMode = subMode;
        _sharedSeed = seed;
        _sharedAutoStart = autoStart;
      });
      if (gameId == 'level_1_flash') {
        _startNewSoloRound(
          subMode,
          autoStart: autoStart,
          explicitSeed: seed,
          broadcastToSquad: false,
        );
      }
    };
    _squadController.onRemoteCancelGame = (playerName) {
      if (!mounted) return;
      _showInDialogNotice('🛑 $playerName cancelled the active game round.');
      if (_activeGameId == 'level_1_flash') {
        _startNewSoloRound(
          _selectedMode,
          autoStart: false,
          explicitSeed: _sharedSeed,
          broadcastToSquad: false,
        );
      }
    };
    _squadController.initIdentity().then((_) {
      if (mounted) {
        _nicknameController.text = _squadController.localName;
      }
    });
    _startNewSoloRound(
      _selectedMode,
      autoStart: false,
      explicitSeed: _sharedSeed,
      broadcastToSquad: false,
    );
    _loadCompletedGames();
  }

  void _onSquadChanged() {
    if (mounted) {
      setState(() {});
    }
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

  List<(String, String)> _getCurrentGameSubModes() {
    switch (_activeGameId) {
      case 'level_0a_make':
        return const [
          (MakeHousieRoundSpec.modeMake5Quad, 'Make 5 (1 Quad)'),
          (MakeHousieRoundSpec.modeMake15Guided, 'Make 10 (2 Quads)'),
          (MakeHousieRoundSpec.modeMake15Master, 'Make 15 (Full Grid)'),
        ];
      case 'level_0b_fix':
        return const [
          (FixHousieRoundSpec.modeFix1, 'Fix 1 Bug (Easy)'),
          (FixHousieRoundSpec.modeFix3, 'Fix 3 Bugs (Med)'),
          (FixHousieRoundSpec.modeFix5, 'Fix 5 Bugs (Hard)'),
        ];
      case 'level_0c_math':
        return const [
          (MathHousieRoundSpec.modeAddSub5, 'Math 5 (+ / −)'),
          (MathHousieRoundSpec.modeMulDiv5, 'Math 5 (× / ÷)'),
          (MathHousieRoundSpec.modeMixed10, 'Math 10 (Mixed)'),
        ];
      case 'level_0d_sum':
        return const [
          (SumHousieRoundSpec.modeSumQ1, 'Sum Q1 (Easy 1–29)'),
          (SumHousieRoundSpec.modeSumQ2, 'Sum Q2 (Med 30–59)'),
          (SumHousieRoundSpec.modeSumQ3, 'Sum Q3 (Hard 60–90)'),
          (SumHousieRoundSpec.modeSumAll3, 'Sum All 3 (Hardest Q1→Q3)'),
        ];
      case 'level_1_flash':
      default:
        return const [
          (FlashHousieConfig.modeFlash5, 'Flash 5 (1 Quad)'),
          (FlashHousieConfig.modeFlash10, 'Flash 10 (2 Quads)'),
          (FlashHousieConfig.modeFlash15, 'Flash 15 (3 Quads)'),
        ];
    }
  }

  String _getDefaultSubModeForGame(String gameId) {
    switch (gameId) {
      case 'level_0a_make':
        return MakeHousieRoundSpec.modeMake5Quad;
      case 'level_0b_fix':
        return FixHousieRoundSpec.modeFix3;
      case 'level_0c_math':
        return MathHousieRoundSpec.modeAddSub5;
      case 'level_0d_sum':
        return SumHousieRoundSpec.modeSumQ1;
      case 'level_1_flash':
      default:
        return FlashHousieConfig.modeFlash5;
    }
  }

  String _getCurrentActiveSubMode() {
    final validModes = _getCurrentGameSubModes().map((m) => m.$1).toList();
    if (_activeGameId == 'level_1_flash') {
      return validModes.contains(_selectedMode)
          ? _selectedMode
          : FlashHousieConfig.modeFlash5;
    }
    return validModes.contains(_sharedSubMode)
        ? _sharedSubMode
        : _getDefaultSubModeForGame(_activeGameId);
  }

  void _onSelectSubMode(String newSubMode) {
    final nextSeed = 1000 + Random().nextInt(899999);
    if (_activeGameId == 'level_1_flash') {
      _selectedMode = newSubMode;
      _sharedSubMode = newSubMode;
      _sharedSeed = nextSeed;
      _startNewSoloRound(
        newSubMode,
        autoStart: false,
        explicitSeed: nextSeed,
        broadcastToSquad: true,
      );
    } else {
      _sharedSubMode = newSubMode;
      _sharedSeed = nextSeed;
      if (_squadController.isInSquad) {
        _squadController.broadcastRoundSync(
          gameId: _activeGameId,
          subMode: newSubMode,
          roundSeed: nextSeed,
          autoStart: false,
        );
      }
      setState(() {});
    }
  }

  void _selectGameTab(String gameId) {
    if (_activeGameId == gameId) return;
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    _autoCallTimer?.cancel();
    _autoCallTimer = null;
    final nextSeed = 1000 + Random().nextInt(899999);
    final nextSubMode = _getDefaultSubModeForGame(gameId);
    if (gameId == 'level_1_flash') {
      _selectedMode = nextSubMode;
      _sharedSubMode = nextSubMode;
      _sharedSeed = nextSeed;
      _startNewSoloRound(
        nextSubMode,
        autoStart: false,
        explicitSeed: nextSeed,
        broadcastToSquad: true,
      );
    } else {
      _sharedSubMode = nextSubMode;
      _sharedSeed = nextSeed;
      if (_squadController.isInSquad) {
        _squadController.broadcastRoundSync(
          gameId: gameId,
          subMode: nextSubMode,
          roundSeed: nextSeed,
          autoStart: false,
        );
      }
    }
    setState(() {
      _activeGameId = gameId;
    });
  }

  void _showInDialogNotice(String msg) {
    if (!mounted) return;
    _squadNoticeTimer?.cancel();
    setState(() {
      _squadCopiedNotice = msg;
    });
    _squadNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _squadCopiedNotice = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _squadNoticeTimer?.cancel();
    _uiTickTimer?.cancel();
    _autoCallTimer?.cancel();
    _squadController.removeListener(_onSquadChanged);
    _squadController.dispose();
    _joinCodeController.dispose();
    _nicknameController.dispose();
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

  void _startNewSoloRound(
    String mode, {
    bool autoStart = false,
    int? explicitSeed,
    bool broadcastToSquad = true,
  }) {
    _uiTickTimer?.cancel();
    _uiTickTimer = null;
    _autoCallTimer?.cancel();
    _autoCallTimer = null;
    final seed = explicitSeed ?? (1000 + Random().nextInt(899999));
    _sharedSeed = seed;
    _sharedSubMode = mode;
    final baseConfig = FlashHousieConfig.generate(
      mode: mode,
      totalCycles: 1,
      cellsPerQuadrant: 5,
      decoysPerColumn: 2,
      random: Random(seed),
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
    if (broadcastToSquad &&
        _activeGameId == 'level_1_flash' &&
        _squadController.isInSquad) {
      _squadController.broadcastRoundSync(
        gameId: 'level_1_flash',
        subMode: mode,
        roundSeed: seed,
        autoStart: autoStart,
      );
    }
    if (_activeGameId == 'level_1_flash') {
      _squadController.reportLocalProgress(
        score: 0,
        progress: 0,
        target: cycleSpec.trueNumbers.length,
        wrongCount: 0,
        reactionMs: 0,
        completed: false,
      );
    }
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
    _squadController.reportLocalProgress(
      score: _netScore,
      progress: _recalledNumbers.length,
      target: spec.trueNumbers.length,
      wrongCount: _wrongTapCount,
      reactionMs: _totalReactionMs,
      completed: true,
      eventText: wonAll
          ? '🏆 Cleared ${_modeShortName(_selectedMode)} ($_netScore pts)!'
          : 'Round ended ($_netScore pts)',
    );
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
      } else {
        _squadController.reportLocalProgress(
          score: _netScore,
          progress: _recalledNumbers.length,
          target: spec.trueNumbers.length,
          wrongCount: _wrongTapCount,
          reactionMs: _totalReactionMs,
          completed: false,
        );
      }
    } else {
      final cellKey = '${row}_$col';
      setState(() {
        _wrongTapCount++;
        _totalReactionMs += 3000;
        _freezeUntilMs = nowMs + 3000;
        _wrongFlashingCells.add(cellKey);
      });
      _squadController.reportLocalProgress(
        score: _netScore,
        progress: _recalledNumbers.length,
        target: spec.trueNumbers.length,
        wrongCount: _wrongTapCount,
        reactionMs: _totalReactionMs,
        completed: false,
        eventText: '❄️ Bogey tap (-3 pts, 3s freeze)!',
      );
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

  Widget _buildFriendSquadBar() {
    final inSquad = _squadController.isInSquad;
    final members = _squadController.sortedMembers;
    final code = _squadController.squadCode ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: inSquad ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inSquad
              ? const Color(0xFF10B981)
              : AppTheme.secondaryColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_squadCopiedNotice != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF047857),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF34D399), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _squadCopiedNotice!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!inSquad) ...[
            Row(
              children: [
                const Icon(
                  Icons.group_add_rounded,
                  size: 16,
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Play with Friends (Free up to 5 Players)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final newCode = await _squadController.createSquad(
                      gameId: _activeGameId,
                      subMode: _sharedSubMode,
                      roundSeed: _sharedSeed,
                      customNickname: _nicknameController.text.trim(),
                    );
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            'Join my DabHousie Skill Game! Open the Skill Arena and enter Friend Code: $newCode (Max 5 players free)',
                      ),
                    );
                    _showInDialogNotice(
                      '🎉 Friend Code #$newCode copied! Share with up to 4 friends to play together.',
                    );
                  },
                  icon: const Icon(Icons.share_rounded, size: 13),
                  label: const Text(
                    'Share Code',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showJoinCodeInput = !_showJoinCodeInput;
                    });
                  },
                  icon: const Icon(Icons.vpn_key_rounded, size: 13),
                  label: Text(
                    _showJoinCodeInput ? 'Cancel' : 'Enter Code',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 28),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
            if (_showJoinCodeInput) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 34,
                    child: TextField(
                      controller: _nicknameController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Your Name',
                        hintStyle: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    height: 34,
                    child: TextField(
                      controller: _joinCodeController,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.secondaryColor,
                        letterSpacing: 1.2,
                      ),
                      decoration: InputDecoration(
                        hintText: '4-Digit Code',
                        hintStyle: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final entered = _joinCodeController.text.trim();
                      final ok = await _squadController.joinSquad(
                        code: entered,
                        customNickname: _nicknameController.text.trim(),
                        currentGameId: _activeGameId,
                        currentSubMode: _sharedSubMode,
                        currentSeed: _sharedSeed,
                      );
                      if (ok && mounted) {
                        setState(() {
                          _showJoinCodeInput = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.login_rounded, size: 14),
                    label: const Text(
                      'Join Squad',
                      style: TextStyle(
                        fontSize: 11.5,
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
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
            if (_squadController.errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _squadController.errorMessage!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF87171),
                ),
              ),
            ],
          ] else ...[
            // Active 5-Player Friend Squad View
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '🔑 CODE: $code',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '👥 ${members.length}/${SkillFriendSquadController.maxPlayers} Players (You + Max 4 Friends Free)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                'Join my DabHousie Skill Game! Open Skill Arena & enter Friend Code: $code',
                          ),
                        );
                        _showInDialogNotice('📋 Copied Friend Code #$code to clipboard!');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 13),
                      label: const Text(
                        'Copy Code',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.secondaryColor,
                        side: const BorderSide(color: AppTheme.secondaryColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _squadController.broadcastCancelGame();
                        if (_activeGameId == 'level_1_flash') {
                          _startNewSoloRound(
                            _selectedMode,
                            autoStart: false,
                            explicitSeed: _sharedSeed,
                            broadcastToSquad: true,
                          );
                        } else {
                          // Signal LevelZeroSoloView by updating seed
                          setState(() {
                            _sharedSeed = 1000 + Random().nextInt(899999);
                          });
                        }
                        _showInDialogNotice('🛑 Cancelled the active squad round.');
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 13),
                      label: const Text(
                        'Cancel Game',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFBBF24),
                        side: const BorderSide(color: Color(0xFFFBBF24)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _squadController.leaveSquad(),
                      icon: const Icon(Icons.logout_rounded, size: 13),
                      label: const Text(
                        'Leave Squad',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFF87171),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Up to 5 Player Live Standings Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(members.length, (idx) {
                final m = members[idx];
                final isMe = m.playerId == _squadController.localPlayerId;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: m.completed
                        ? const Color(0xFF064E3B)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: m.completed
                          ? const Color(0xFF34D399)
                          : (isMe
                                ? AppTheme.secondaryColor
                                : const Color(0xFF334155)),
                      width: isMe || m.completed ? 1.4 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${idx + 1} ${m.avatar} ${isMe ? "${m.name} (You)" : m.name}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${m.score} pts • ${m.progress}/${m.target}${m.wrongCount > 0 ? " • ✖${m.wrongCount}" : ""}${m.completed ? " 🏆" : ""}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: m.completed
                              ? const Color(0xFF34D399)
                              : AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            if (_squadController.liveFeedMessage != null) ...[
              const SizedBox(height: 5),
              Text(
                _squadController.liveFeedMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA7F3D0),
                ),
              ),
            ],
          ],
        ],
      ),
    );
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
              // 1. Header Bar with Level Dropdown & Action Controls
              Row(
                children: [
                  // Compact Level Dropdown Selector
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.65),
                        width: 1.2,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _activeGameId,
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.secondaryColor),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        items: _release1Games.map((g) {
                          final isDone = _completedGameIds.contains(g.$1);
                          return DropdownMenuItem<String>(
                            value: g.$1,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(g.$2),
                                if (isDone) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF34D399)),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _selectGameTab(val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Inline Quad / Sub-Mode Dropdown Selector (Level-0A, Quad-1 in one line)
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.65),
                        width: 1.2,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _getCurrentActiveSubMode(),
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.secondaryColor),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        items: _getCurrentGameSubModes().map((m) {
                          return DropdownMenuItem<String>(
                            value: m.$1,
                            child: Text(m.$2),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _onSelectSubMode(val);
                        },
                      ),
                    ),
                  ),
                  const Spacer(),
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
                    tooltip: 'Close Arena',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 1B. Hostless 5-Player Friend Squad Bar (Share Code with up to 4 friends without hosting!)
              _buildFriendSquadBar(),
              const SizedBox(height: 10),

              if (_activeGameId != 'level_1_flash') ...[
                LevelZeroSoloView(
                  gameId: _activeGameId,
                  squadController: _squadController,
                  sharedSeed: _sharedSeed,
                  sharedSubMode: _sharedSubMode,
                  autoStart: _sharedAutoStart,
                  onLocalStateChanged: (subMode, seed) {
                    _sharedSubMode = subMode;
                    _sharedSeed = seed;
                  },
                  onLevelCompleted: () {
                    _loadCompletedGames();
                    widget.onLevelCompleted?.call();
                  },
                  onSelectGameId: _selectGameTab,
                ),
              ] else ...[
                // 2. Level 1 Action Row (New Card / Cancel during active play only)
                if (!isWaitingToStart && !_roundCompleted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            _startNewSoloRound(_selectedMode, autoStart: false),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'New Card',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: AppTheme.secondaryColor,
                          side: BorderSide(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.6),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_squadController.isInSquad) {
                            _squadController.broadcastCancelGame();
                          }
                          _startNewSoloRound(
                            _selectedMode,
                            autoStart: false,
                            explicitSeed: _sharedSeed,
                            broadcastToSquad: true,
                          );
                          _showInDialogNotice('🛑 Round cancelled.');
                        },
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                        label: const Text('Cancel', style: TextStyle(fontSize: 11.5)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF87171),
                          side: const BorderSide(color: Color(0xFFF87171)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

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
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
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
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () => _startNewSoloRound(
                                          _selectedMode,
                                          autoStart: false,
                                        ),
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Shuffle',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF1E293B),
                                          foregroundColor:
                                              AppTheme.secondaryColor,
                                          side: BorderSide(
                                            color: AppTheme.secondaryColor
                                                .withValues(alpha: 0.6),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ],
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
