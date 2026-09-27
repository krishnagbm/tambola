import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/level_zero_skill_engine.dart';

class LevelZeroSoloView extends StatefulWidget {
  final String gameId; // 'level_0a_make', 'level_0b_fix', 'level_0c_math', 'level_0d_sum'
  final VoidCallback? onLevelCompleted;
  final ValueChanged<String>? onSelectGameId;

  const LevelZeroSoloView({
    super.key,
    required this.gameId,
    this.onLevelCompleted,
    this.onSelectGameId,
  });

  @override
  State<LevelZeroSoloView> createState() => _LevelZeroSoloViewState();
}

class _LevelZeroSoloViewState extends State<LevelZeroSoloView> {
  Timer? _uiTimer;
  int? _startedAtMs;
  int? _stepStartedAtMs;
  int? _finishedAtMs;
  int _totalReactionMs = 0;
  bool _roundCompleted = false;

  int _correctCount = 0;
  int _wrongCount = 0;
  String? _feedbackBannerText;
  bool _feedbackIsError = false;
  final Set<String> _wrongFlashingCells = <String>{};

  // Level 0A: MakeHousie state
  String _makeMode = MakeHousieRoundSpec.modeMake5Quad;
  late MakeHousieRoundSpec _makeSpec;
  final Set<int> _placedBalls = <int>{};
  int? _selectedDealBall;

  // Level 0B: FixHousie state
  String _fixMode = FixHousieRoundSpec.modeFix3;
  late FixHousieRoundSpec _fixSpec;
  final Set<String> _repairedCellKeys = <String>{};

  // Level 0C: MathHousie state
  String _mathMode = MathHousieRoundSpec.modeAddSub5;
  late MathHousieRoundSpec _mathSpec;
  int _mathPromptIndex = 0;
  final Set<int> _solvedMathTargets = <int>{};

  // Level 0D: SumHousie state
  String _sumMode = SumHousieRoundSpec.modeSumQ1;
  late SumHousieRoundSpec _sumSpec;
  int _sumWaveIndex = 0;
  final Set<int> _solvedSumQuadrants = <int>{};
  final Set<int> _wrongSumOptions = <int>{};

  @override
  void initState() {
    super.initState();
    _initCurrentGame(autoStart: false);
  }

  @override
  void didUpdateWidget(covariant LevelZeroSoloView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId) {
      _initCurrentGame(autoStart: false);
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  void _startClockTicker() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _roundCompleted) return;
      setState(() {});
    });
  }

  void _initCurrentGame({required bool autoStart}) {
    _uiTimer?.cancel();
    _uiTimer = null;
    final rng = Random();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    _makeSpec = MakeHousieRoundSpec.generate(mode: _makeMode, random: rng);
    _fixSpec = FixHousieRoundSpec.generate(mode: _fixMode, random: rng);
    _mathSpec = MathHousieRoundSpec.generate(mode: _mathMode, random: rng);
    _sumSpec = SumHousieRoundSpec.generate(mode: _sumMode, random: rng);

    setState(() {
      _startedAtMs = autoStart ? nowMs : null;
      _stepStartedAtMs = autoStart ? nowMs : null;
      _finishedAtMs = null;
      _totalReactionMs = 0;
      _roundCompleted = false;
      _correctCount = 0;
      _wrongCount = 0;
      _feedbackBannerText = null;
      _feedbackIsError = false;
      _wrongFlashingCells.clear();

      _placedBalls.clear();
      _selectedDealBall =
          _makeSpec.dealPool.isNotEmpty ? _makeSpec.dealPool.first : null;

      _repairedCellKeys.clear();

      _mathPromptIndex = 0;
      _solvedMathTargets.clear();

      _sumWaveIndex = 0;
      _solvedSumQuadrants.clear();
      _wrongSumOptions.clear();
    });

    if (autoStart) {
      _startClockTicker();
    }
  }

  void _launchRound() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _startedAtMs = nowMs;
      _stepStartedAtMs = nowMs;
      _roundCompleted = false;
      _feedbackBannerText = null;
      _feedbackIsError = false;
    });
    _startClockTicker();
  }

  int get _targetStepCount {
    switch (widget.gameId) {
      case 'level_0a_make':
        return _makeSpec.dealPool.length;
      case 'level_0b_fix':
        return _fixSpec.totalBugs;
      case 'level_0c_math':
        return _mathSpec.prompts.length;
      case 'level_0d_sum':
        return _sumSpec.waves.length;
      default:
        return 5;
    }
  }

  int get _pointsPerHit {
    switch (widget.gameId) {
      case 'level_0b_fix':
      case 'level_0d_sum':
        return 15;
      default:
        return 10;
    }
  }

  int get _penaltyPerMiss {
    switch (widget.gameId) {
      case 'level_0b_fix':
      case 'level_0d_sum':
        return 5;
      default:
        return 3;
    }
  }

  int get _netScore =>
      (_correctCount * _pointsPerHit) - (_wrongCount * _penaltyPerMiss);

  Future<void> _completeRound() async {
    _uiTimer?.cancel();
    _uiTimer = null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _roundCompleted = true;
      _finishedAtMs = nowMs;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final doneKey = 'dabhousie_skill_${widget.gameId}_completed';
      final bestKey = 'dabhousie_skill_${widget.gameId}_best_score';
      await prefs.setBool(doneKey, true);
      final prevBest = prefs.getInt(bestKey) ?? 0;
      if (_netScore > prevBest) {
        await prefs.setInt(bestKey, _netScore);
      }
      // Also mark overall level_0 completed if any Level 0 game is completed
      await prefs.setBool('dabhousie_skill_level_0_completed', true);
    } catch (_) {}
    widget.onLevelCompleted?.call();
  }

  void _flashWrongCell(int row, int col) {
    final key = '${row}_$col';
    setState(() => _wrongFlashingCells.add(key));
    Future.delayed(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() => _wrongFlashingCells.remove(key));
      }
    });
  }

  // --------------------------------------------------------------------------
  // Interaction Handlers per Level 0 Game
  // --------------------------------------------------------------------------

  void _handleMakeCellTap(int row, int col) {
    if (_startedAtMs == null || _roundCompleted) return;
    final ball = _selectedDealBall;
    if (ball == null || _placedBalls.contains(ball)) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final res = _makeSpec.validatePlacement(
      selectedBall: ball,
      row: row,
      col: col,
      alreadyPlacedBalls: _placedBalls,
    );

    if (res.isSuccess) {
      final stepMs = _stepStartedAtMs != null
          ? (nowMs - _stepStartedAtMs!).clamp(150, 30000)
          : 1000;
      setState(() {
        _placedBalls.add(ball);
        _correctCount = _placedBalls.length;
        _totalReactionMs += stepMs;
        _stepStartedAtMs = nowMs;
        _feedbackBannerText = res.message;
        _feedbackIsError = false;
        // Auto-select next unplaced ball in dealPool
        _selectedDealBall = _makeSpec.dealPool
            .where((b) => !_placedBalls.contains(b))
            .cast<int?>()
            .firstWhere((b) => b != null, orElse: () => null);
      });
      if (_placedBalls.length >= _makeSpec.dealPool.length) {
        _completeRound();
      }
    } else {
      _flashWrongCell(row, col);
      setState(() {
        if (res.isRulePenalty) {
          _wrongCount++;
          _totalReactionMs += 1500;
        }
        _feedbackBannerText = res.message;
        _feedbackIsError = true;
      });
    }
  }

  void _handleFixCellTap(int row, int col) {
    if (_startedAtMs == null || _roundCompleted) return;
    final cellKey = '${row}_$col';
    if (_repairedCellKeys.contains(cellKey)) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final bug = _fixSpec.bugsByCellKey[cellKey];
    if (bug != null) {
      final stepMs = _stepStartedAtMs != null
          ? (nowMs - _stepStartedAtMs!).clamp(150, 30000)
          : 1000;
      setState(() {
        _repairedCellKeys.add(cellKey);
        _correctCount = _repairedCellKeys.length;
        _totalReactionMs += stepMs;
        _stepStartedAtMs = nowMs;
        _feedbackBannerText = bug.explanation;
        _feedbackIsError = false;
      });
      if (_repairedCellKeys.length >= _fixSpec.totalBugs) {
        _completeRound();
      }
    } else {
      final val = _fixSpec.bugMatrix[row][col];
      if (val == 0) return;
      _flashWrongCell(row, col);
      setState(() {
        _wrongCount++;
        _totalReactionMs += 2000;
        _feedbackBannerText =
            '✖ Valid Cell (-5 pts): Ball $val is already valid in Col ${col + 1} (${columnDecadeLabel(col)})!';
        _feedbackIsError = true;
      });
    }
  }

  void _handleMathCellTap(int row, int col, int cellVal) {
    if (_startedAtMs == null || _roundCompleted || cellVal == 0) return;
    if (_mathPromptIndex >= _mathSpec.prompts.length) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final prompt = _mathSpec.prompts[_mathPromptIndex];

    if (cellVal == prompt.targetValue) {
      final stepMs = _stepStartedAtMs != null
          ? (nowMs - _stepStartedAtMs!).clamp(150, 30000)
          : 1000;
      setState(() {
        _solvedMathTargets.add(cellVal);
        _correctCount = _solvedMathTargets.length;
        _totalReactionMs += stepMs;
        _stepStartedAtMs = nowMs;
        _feedbackBannerText =
            '✓ Correct! ${prompt.expression.replaceAll('?', '$cellVal')} in Col ${col + 1} (${columnDecadeLabel(col)})!';
        _feedbackIsError = false;
        if (_mathPromptIndex + 1 < _mathSpec.prompts.length) {
          _mathPromptIndex++;
        }
      });
      if (_solvedMathTargets.length >= _mathSpec.prompts.length) {
        _completeRound();
      }
    } else {
      _flashWrongCell(row, col);
      final expectedCol = expectedColumnForBall(prompt.targetValue);
      setState(() {
        _wrongCount++;
        _totalReactionMs += 1500;
        _feedbackBannerText =
            '✖ Not $cellVal (-3 pts)! Hint: "${prompt.expression}" is in Col ${expectedCol + 1} (${columnDecadeLabel(expectedCol)}).';
        _feedbackIsError = true;
      });
    }
  }

  void _handleSumOptionTap(int chosenSum) {
    if (_startedAtMs == null || _roundCompleted) return;
    if (_sumWaveIndex >= _sumSpec.waves.length) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final wave = _sumSpec.waves[_sumWaveIndex];

    if (chosenSum == wave.correctSum) {
      final stepMs = _stepStartedAtMs != null
          ? (nowMs - _stepStartedAtMs!).clamp(150, 30000)
          : 1200;
      setState(() {
        _solvedSumQuadrants.add(wave.quadrant);
        _correctCount = _solvedSumQuadrants.length;
        _wrongSumOptions.clear();
        _totalReactionMs += stepMs;
        _stepStartedAtMs = nowMs;
        _feedbackBannerText =
            '✓ Exact Sum! Q${wave.quadrant} (${wave.quadrantNumbers.join(' + ')}) = ${wave.correctSum}!';
        _feedbackIsError = false;
        if (_sumWaveIndex + 1 < _sumSpec.waves.length) {
          _sumWaveIndex++;
        }
      });
      if (_solvedSumQuadrants.length >= _sumSpec.waves.length) {
        _completeRound();
      }
    } else {
      setState(() {
        _wrongCount++;
        _wrongSumOptions.add(chosenSum);
        _totalReactionMs += 2000;
        _feedbackBannerText =
            '✖ $chosenSum is a decoy (-5 pts)! Add all 5 numbers in Q${wave.quadrant} carefully.';
        _feedbackIsError = true;
      });
    }
  }

  // --------------------------------------------------------------------------
  // UI Helpers
  // --------------------------------------------------------------------------

  String _formatClockMain() {
    if (_startedAtMs == null) {
      return '$_targetStepCount Steps';
    }
    final nowMs = _finishedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final sec = ((nowMs - _startedAtMs!) / 1000).clamp(0.0, 999.0);
    return '${sec.toStringAsFixed(1)}s';
  }

  String _formatClockSubCaption() {
    if (_startedAtMs == null) {
      return 'Pick Mode & Start';
    }
    if (_roundCompleted) {
      final count = _correctCount <= 0 ? 1 : _correctCount;
      final avgSec = (_totalReactionMs / 1000) / count;
      final roundSec = ((_finishedAtMs! - _startedAtMs!) / 1000).clamp(1.0, 999.0);
      return 'Avg ${avgSec.toStringAsFixed(1)}s • Rnd ${roundSec.toStringAsFixed(0)}s';
    }
    return 'Step $_correctCount/$_targetStepCount';
  }

  String _nextGameId() {
    switch (widget.gameId) {
      case 'level_0a_make':
        return 'level_0b_fix';
      case 'level_0b_fix':
        return 'level_0c_math';
      case 'level_0c_math':
        return 'level_0d_sum';
      default:
        return 'level_1_flash';
    }
  }

  String _nextGameLabel() {
    switch (widget.gameId) {
      case 'level_0a_make':
        return 'Next: 0B Fix™ →';
      case 'level_0b_fix':
        return 'Next: 0C Math™ →';
      case 'level_0c_math':
        return 'Next: 0D Sum™ →';
      default:
        return 'Next: Lvl 1 Flash™ →';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWaiting = _startedAtMs == null && !_roundCompleted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Sub-Mode Selector Row + Shuffle Card
        _buildSubModeRow(isWaiting),
        const SizedBox(height: 10),

        // 2. Status & Rule Feedback Banner
        _buildStatusBanner(isWaiting),
        const SizedBox(height: 10),

        // 3. 3-Column HUD (Left: Start / Prompt / Play Again | Middle: SCORE | Right: CLOCK)
        _buildThreeColumnHud(isWaiting),
        const SizedBox(height: 10),

        // 4. Game-Specific Interactive Strip (Deal Pool for MakeHousie, MCQ Bar for SumHousie)
        if (widget.gameId == 'level_0a_make') ...[
          _buildMakeDealPoolStrip(isWaiting),
          const SizedBox(height: 10),
        ] else if (widget.gameId == 'level_0d_sum') ...[
          _buildSumMcqStrip(isWaiting),
          const SizedBox(height: 10),
        ],

        // 5. 3x9 Grid Matrix
        _buildGridContainer(isWaiting),
      ],
    );
  }

  Widget _buildSubModeRow(bool isWaiting) {
    List<(String, String)> chips;
    String activeMode;
    void Function(String) onSelect;

    switch (widget.gameId) {
      case 'level_0a_make':
        activeMode = _makeMode;
        chips = const [
          (MakeHousieRoundSpec.modeMake5Quad, 'Make 5 (1 Quad)'),
          (MakeHousieRoundSpec.modeMake15Guided, 'Make 15 (Guided)'),
          (MakeHousieRoundSpec.modeMake15Master, 'Make 15 (Master)'),
        ];
        onSelect = (m) {
          _makeMode = m;
          _initCurrentGame(autoStart: false);
        };
        break;
      case 'level_0b_fix':
        activeMode = _fixMode;
        chips = const [
          (FixHousieRoundSpec.modeFix1, 'Fix 1 Bug (Easy)'),
          (FixHousieRoundSpec.modeFix3, 'Fix 3 Bugs (Med)'),
          (FixHousieRoundSpec.modeFix5, 'Fix 5 Bugs (Hard)'),
        ];
        onSelect = (m) {
          _fixMode = m;
          _initCurrentGame(autoStart: false);
        };
        break;
      case 'level_0c_math':
        activeMode = _mathMode;
        chips = const [
          (MathHousieRoundSpec.modeAddSub5, 'Math 5 (+ / −)'),
          (MathHousieRoundSpec.modeMulDiv5, 'Math 5 (× / ÷)'),
          (MathHousieRoundSpec.modeMixed10, 'Math 10 (Mixed)'),
        ];
        onSelect = (m) {
          _mathMode = m;
          _initCurrentGame(autoStart: false);
        };
        break;
      default:
        activeMode = _sumMode;
        chips = const [
          (SumHousieRoundSpec.modeSumQ1, 'Sum Q1 (Easy 1–29)'),
          (SumHousieRoundSpec.modeSumQ2, 'Sum Q2 (Med 30–59)'),
          (SumHousieRoundSpec.modeSumAll3, 'Sum All 3 (Q1→Q3)'),
        ];
        onSelect = (m) {
          _sumMode = m;
          _initCurrentGame(autoStart: false);
        };
        break;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (modeVal, label) in chips)
              ChoiceChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: activeMode == modeVal ? Colors.black : Colors.white,
                  ),
                ),
                selected: activeMode == modeVal,
                selectedColor: AppTheme.secondaryColor,
                backgroundColor: AppTheme.darkCard,
                onSelected: (_) => onSelect(modeVal),
              ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => _initCurrentGame(autoStart: false),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(isWaiting ? 'Shuffle Card' : 'New Card / Reset'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.secondaryColor,
            side: BorderSide(
              color: AppTheme.secondaryColor.withValues(alpha: 0.6),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(bool isWaiting) {
    String headline;
    String subline;

    if (_roundCompleted) {
      switch (widget.gameId) {
        case 'level_0a_make':
          headline =
              '🏆 LEVEL 0A CLEARED! ALL ${_makeSpec.dealPool.length} NUMBERS PLACED VALIDLY!';
          subline =
              'You mastered 3×9 column decades & ascending order! Try Make 15 Master or advance to 0B FixHousie™.';
          break;
        case 'level_0b_fix':
          headline =
              '🏆 LEVEL 0B CLEARED! ALL ${_fixSpec.totalBugs} TICKET BUGS REPAIRED!';
          subline =
              'Sharp eye! You audited the 3×9 grid and fixed every rule violation.';
          break;
        case 'level_0c_math':
          headline =
              '🏆 LEVEL 0C CLEARED! ALL ${_mathSpec.prompts.length} FORMULAS SOLVED!';
          subline =
              'Fast mental math + column decade hunting! Ready for 0D SumHousie™?';
          break;
        default:
          headline =
              '🏆 LEVEL 0D CLEARED! QUADRANT RAPID ADDITION MASTERED!';
          subline =
              'Awesome mental addition! You are ready for Level 1 FlashHousie™ NeuroWave™ memory rounds.';
          break;
      }
    } else if (isWaiting) {
      switch (widget.gameId) {
        case 'level_0a_make':
          headline =
              '🎓 MakeHousie™ Ready • Place ${_makeSpec.dealPool.length} Numbers onto the 3×9 Ticket';
          subline =
              'Rules: 1️⃣ Column Decades (1–9 .. 80–90) • 2️⃣ Top-to-Bottom Ascending Order • 3️⃣ 5 Numbers per Row!';
          break;
        case 'level_0b_fix':
          headline =
              '🔍 FixHousie™ Ready • Spot & Repair ${_fixSpec.totalBugs} Rule Mistake(s)';
          subline =
              'Tap "▶ Start" to reveal the ticket, then tap any cell with a wrong decade, flipped order, duplicate, or >90 ball!';
          break;
        case 'level_0c_math':
          headline =
              '➕ MathHousie™ Ready • Solve ${_mathSpec.prompts.length} Live Formulas on the 3×9 Grid';
          subline =
              'Tap "▶ Start" to see each formula, jump to its decade column (1–9 .. 80–90), and tap the answer!';
          break;
        default:
          headline =
              '🧮 SumHousie™ Ready • Add the 5 Numbers Inside Active 3×3 Quadrants';
          subline =
              'Tap "▶ Start" to reveal the active quadrant numbers and pick the exact sum (watch out for same-last-digit decoys)!';
          break;
      }
    } else {
      // Active play
      if (_feedbackBannerText != null) {
        headline = _feedbackBannerText!;
      } else {
        switch (widget.gameId) {
          case 'level_0a_make':
            headline =
                '🎯 Tap the valid [•] cell for Ball #${_selectedDealBall ?? '—'} (${_placedBalls.length}/${_makeSpec.dealPool.length} placed)';
            break;
          case 'level_0b_fix':
            headline =
                '🔍 Inspect the 3×9 ticket and tap the ${_fixSpec.totalBugs - _repairedCellKeys.length} remaining buggy cell(s)!';
            break;
          case 'level_0c_math':
            final p = _mathSpec.prompts[_mathPromptIndex];
            headline =
                '➕ Solve "${p.expression}" and tap the matching number in its decade column!';
            break;
          default:
            final w = _sumSpec.waves[_sumWaveIndex];
            headline =
                '🧮 Add all 5 highlighted numbers in Q${w.quadrant} and select the exact sum below!';
            break;
        }
      }
      subline =
          'Rule 1: Col Decades (1–9, 10–19 … 80–90) • Rule 2: Ascending Vertical Order • Rule 3: 5 Per Row';
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _feedbackIsError
              ? const [Color(0xFF450A0A), Color(0xFF0F172A)]
              : (_roundCompleted || !isWaiting
                    ? const [Color(0xFF064E3B), Color(0xFF0F172A)]
                    : const [Color(0xFF1E1B4B), Color(0xFF0F172A)]),
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _feedbackIsError
              ? AppTheme.accentDanger
              : (_roundCompleted || !isWaiting
                    ? const Color(0xFF10B981)
                    : AppTheme.secondaryColor),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _feedbackIsError
                ? Icons.warning_amber_rounded
                : (_roundCompleted
                      ? Icons.emoji_events_rounded
                      : (isWaiting
                            ? Icons.play_circle_fill_rounded
                            : Icons.psychology_rounded)),
            color: _feedbackIsError
                ? const Color(0xFFF87171)
                : (_roundCompleted
                      ? AppTheme.secondaryColor
                      : const Color(0xFF34D399)),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subline,
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
    );
  }

  Widget _buildThreeColumnHud(bool isWaiting) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // LEFT COLUMN: Start / Active Prompt / Completed Actions
          Expanded(
            flex: 4,
            child: isWaiting
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _waitingLeftSubtitle(),
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
                        onPressed: _launchRound,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          _startButtonLabel(),
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _initCurrentGame(autoStart: true),
                                  icon: const Icon(
                                    Icons.replay_rounded,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Play Again',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondaryColor,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                if (widget.onSelectGameId != null)
                                  OutlinedButton(
                                    onPressed: () => widget.onSelectGameId!(
                                      _nextGameId(),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF34D399),
                                      side: const BorderSide(
                                        color: Color(0xFF10B981),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: Text(
                                      _nextGameLabel(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        )
                      : _buildActiveLeftHudContent()),
          ),

          Container(
            width: 1,
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 6),
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
                  '✓ $_correctCount/$_targetStepCount  •  ✖ $_wrongCount',
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

          // RIGHT COLUMN: Prominent Large CLOCK / TIME
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
                        _roundCompleted
                            ? 'REACTION TIME'
                            : (isWaiting ? 'READY MODE' : 'PLAY CLOCK'),
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
                    _formatClockMain(),
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
                    _formatClockSubCaption(),
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
    );
  }

  String _waitingLeftSubtitle() {
    switch (widget.gameId) {
      case 'level_0a_make':
        return 'Target: ${_makeSpec.dealPool.length} Balls';
      case 'level_0b_fix':
        return 'Target: ${_fixSpec.totalBugs} Bug(s)';
      case 'level_0c_math':
        return 'Target: ${_mathSpec.prompts.length} Formulas';
      default:
        return 'Target: ${_sumSpec.waves.length} Quadrant(s)';
    }
  }

  String _startButtonLabel() {
    switch (widget.gameId) {
      case 'level_0a_make':
        return 'Start MakeHousie';
      case 'level_0b_fix':
        return 'Start FixHousie';
      case 'level_0c_math':
        return 'Start MathHousie';
      default:
        return 'Start SumHousie';
    }
  }

  Widget _buildActiveLeftHudContent() {
    switch (widget.gameId) {
      case 'level_0a_make':
        final ball = _selectedDealBall;
        final col = ball != null ? expectedColumnForBall(ball) : 0;
        final isMaster = _makeMode == MakeHousieRoundSpec.modeMake15Master;
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                ball != null ? '$ball' : '✓',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ball != null ? 'Place Ball #$ball' : 'All Placed!',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ball == null
                        ? 'Complete!'
                        : (isMaster
                              ? 'Master Mode: Deduce Col & Order'
                              : 'Hint: Col ${col + 1} (${columnDecadeLabel(col)})'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF34D399),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'level_0b_fix':
        final rem = _fixSpec.totalBugs - _repairedCellKeys.length;
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                '$rem',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$rem Bug${rem == 1 ? '' : 's'} Left to Spot',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Check Col Decades & Order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'level_0c_math':
        final prompt = _mathSpec.prompts[_mathPromptIndex];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  prompt.expression,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Formula ${_mathPromptIndex + 1} of ${_mathSpec.prompts.length} • Tap Answer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      default:
        final wave = _sumSpec.waves[_sumWaveIndex];
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active: Quadrant Q${wave.quadrant}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Wave ${_sumWaveIndex + 1} of ${_sumSpec.waves.length} • Sum 5 Balls',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildMakeDealPoolStrip(bool isWaiting) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isWaiting
                    ? '🎱 Number Pool (${_makeSpec.dealPool.length} balls — click "▶ Start" above to place)'
                    : '🎱 Number Pool (Tap a ball below or tap its [•] slot on the 3×9 grid)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Text(
                '${_placedBalls.length}/${_makeSpec.dealPool.length} Placed',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF34D399),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _makeSpec.dealPool.map((ball) {
              final isPlaced = _placedBalls.contains(ball);
              final isSelected = !isPlaced && _selectedDealBall == ball;
              return InkWell(
                onTap: (!isWaiting && !isPlaced && !_roundCompleted)
                    ? () => setState(() => _selectedDealBall = ball)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isPlaced
                        ? const Color(0xFF064E3B)
                        : (isSelected
                              ? AppTheme.secondaryColor
                              : const Color(0xFF1E293B)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPlaced
                          ? const Color(0xFF10B981)
                          : (isSelected
                                ? Colors.white
                                : const Color(0xFF334155)),
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Text(
                    isPlaced ? '✓' : '$ball',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isPlaced
                          ? const Color(0xFF34D399)
                          : (isSelected ? Colors.black : Colors.white),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSumMcqStrip(bool isWaiting) {
    final wave = _sumSpec.waves[_sumWaveIndex];
    final labels = ['A', 'B', 'C', 'D'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isWaiting
                ? '🧮 Quadrant Q${wave.quadrant} Sum Options (Click "▶ Start" above to reveal numbers & answer)'
                : '🧮 What is the exact sum of the 5 numbers in Quadrant Q${wave.quadrant}? (Watch for same-last-digit decoys!)',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(wave.options.length, (i) {
              final opt = wave.options[i];
              final isWrong = _wrongSumOptions.contains(opt);
              final isCorrectDone =
                  _roundCompleted && opt == wave.correctSum;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                  child: ElevatedButton(
                    onPressed: (isWaiting || _roundCompleted || isWrong)
                        ? null
                        : () => _handleSumOptionTap(opt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCorrectDone
                          ? const Color(0xFF10B981)
                          : (isWrong
                                ? const Color(0xFF7F1D1D)
                                : const Color(0xFF1E293B)),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isCorrectDone
                          ? const Color(0xFF10B981)
                          : (isWrong
                                ? const Color(0xFF450A0A)
                                : const Color(0xFF111827)),
                      disabledForegroundColor: isCorrectDone
                          ? Colors.black
                          : Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isCorrectDone
                              ? const Color(0xFF34D399)
                              : (isWrong
                                    ? AppTheme.accentDanger
                                    : AppTheme.secondaryColor.withValues(
                                        alpha: 0.5,
                                      )),
                        ),
                      ),
                    ),
                    child: Text(
                      isWaiting ? '${labels[i]}: ???' : '${labels[i]}: $opt',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isCorrectDone
                            ? Colors.black
                            : (isWaiting ? Colors.white38 : Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildGridContainer(bool isWaiting) {
    final hideDecadeHeaders =
        widget.gameId == 'level_0a_make' &&
        _makeMode == MakeHousieRoundSpec.modeMake15Master &&
        !isWaiting &&
        !_roundCompleted;

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
          // Top Quadrant Header Row
          Row(
            children: List.generate(3, (qIdx) {
              final qNum = qIdx + 1;
              final isActive = _isQuadrantActive(qNum);
              final ranges = [
                'Cols 1–3 (1–29)',
                'Cols 4–6 (30–59)',
                'Cols 7–9 (60–90)',
              ];
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
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
          const SizedBox(height: 6),

          // Column Decade Header Strip (Col 1: 1–9 ... Col 9: 80–90)
          if (!hideDecadeHeaders) ...[
            Row(
              children: [
                for (int c = 0; c < 9; c++) ...[
                  if (c == 3 || c == 6) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        columnDecadeLabel(c),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],

          // 3x9 Cells
          for (int r = 0; r < 3; r++)
            Padding(
              padding: EdgeInsets.only(bottom: r < 2 ? 6 : 0),
              child: Row(
                children: [
                  for (int c = 0; c < 9; c++) ...[
                    if (c == 3 || c == 6) const SizedBox(width: 6),
                    Expanded(
                      child: _buildCell(row: r, col: c, isWaiting: isWaiting),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _isQuadrantActive(int qNum) {
    switch (widget.gameId) {
      case 'level_0a_make':
        return _makeSpec.activeQuadrants.contains(qNum);
      case 'level_0d_sum':
        return _sumSpec.waves[_sumWaveIndex].quadrant == qNum ||
            _solvedSumQuadrants.contains(qNum);
      default:
        return true;
    }
  }

  Widget _buildCell({
    required int row,
    required int col,
    required bool isWaiting,
  }) {
    final isWrongFlash = _wrongFlashingCells.contains('${row}_$col');

    switch (widget.gameId) {
      case 'level_0a_make':
        return _buildMakeCell(row, col, isWaiting, isWrongFlash);
      case 'level_0b_fix':
        return _buildFixCell(row, col, isWaiting, isWrongFlash);
      case 'level_0c_math':
        return _buildMathCell(row, col, isWaiting, isWrongFlash);
      default:
        return _buildSumCell(row, col, isWaiting);
    }
  }

  Widget _buildMakeCell(
    int row,
    int col,
    bool isWaiting,
    bool isWrongFlash,
  ) {
    final trueVal = _makeSpec.trueMatrix[row][col];
    final isEmpty = trueVal == 0;
    final inActiveQuad = _makeSpec.isColumnActive(col);
    final isPlaced = !isEmpty && _placedBalls.contains(trueVal);

    String label = '';
    Color bg = const Color(0xFF0B1120);
    Color border = const Color(0xFF1E293B);
    Color textColor = Colors.white;

    if (isWrongFlash) {
      label = '✖';
      bg = const Color(0xFFDC2626);
      border = const Color(0xFFF87171);
    } else if (isEmpty) {
      bg = const Color(0xFF0B1120);
      border = const Color(0xFF1E293B);
    } else if (!inActiveQuad) {
      // Pre-filled helper quadrants in Make 5 mode
      label = '$trueVal';
      bg = const Color(0xFF1E293B);
      border = const Color(0xFF334155);
      textColor = const Color(0xFF94A3B8);
    } else if (isPlaced || _roundCompleted) {
      label = '$trueVal';
      bg = const Color(0xFF059669);
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else {
      // Target slot [•] waiting for player placement
      label = '•';
      bg = const Color(0xFF1E1B4B);
      border = AppTheme.secondaryColor.withValues(alpha: 0.65);
      textColor = AppTheme.secondaryColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: (!isWaiting && !_roundCompleted && inActiveQuad && !isPlaced)
            ? () => _handleMakeCellTap(row, col)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border,
              width: isPlaced || (!isEmpty && inActiveQuad) ? 1.6 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFixCell(
    int row,
    int col,
    bool isWaiting,
    bool isWrongFlash,
  ) {
    final bugVal = _fixSpec.bugMatrix[row][col];
    final trueVal = _fixSpec.trueMatrix[row][col];
    final isEmpty = trueVal == 0;
    final cellKey = '${row}_$col';
    final isRepaired = _repairedCellKeys.contains(cellKey);

    String label = '';
    Color bg = const Color(0xFF0B1120);
    Color border = const Color(0xFF1E293B);
    Color textColor = Colors.white;

    if (isEmpty) {
      bg = const Color(0xFF0B1120);
      border = const Color(0xFF1E293B);
    } else if (isWrongFlash) {
      label = '$bugVal';
      bg = const Color(0xFFDC2626);
      border = const Color(0xFFF87171);
    } else if (isWaiting) {
      label = '•';
      bg = const Color(0xFF1E1B4B);
      border = const Color(0xFF3730A3);
      textColor = Colors.white38;
    } else if (isRepaired) {
      label = '$trueVal';
      bg = const Color(0xFF059669);
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else {
      label = '$bugVal';
      bg = const Color(0xFF1E293B);
      border = const Color(0xFF475569);
      textColor = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: (!isWaiting && !_roundCompleted && !isEmpty && !isRepaired)
            ? () => _handleFixCellTap(row, col)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border,
              width: isRepaired ? 2.0 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMathCell(
    int row,
    int col,
    bool isWaiting,
    bool isWrongFlash,
  ) {
    final val = _mathSpec.ticketMatrix[row][col];
    final isEmpty = val == 0;
    final isSolved = !isEmpty && _solvedMathTargets.contains(val);

    String label = '';
    Color bg = const Color(0xFF0B1120);
    Color border = const Color(0xFF1E293B);
    Color textColor = Colors.white;

    if (isEmpty) {
      bg = const Color(0xFF0B1120);
      border = const Color(0xFF1E293B);
    } else if (isWrongFlash) {
      label = '✖';
      bg = const Color(0xFFDC2626);
      border = const Color(0xFFF87171);
    } else if (isWaiting) {
      label = '•';
      bg = const Color(0xFF1E1B4B);
      border = const Color(0xFF3730A3);
      textColor = Colors.white38;
    } else if (isSolved) {
      label = '$val';
      bg = const Color(0xFF059669);
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else {
      label = '$val';
      bg = const Color(0xFF1E293B);
      border = const Color(0xFF475569);
      textColor = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: (!isWaiting && !_roundCompleted && !isEmpty && !isSolved)
            ? () => _handleMathCellTap(row, col, val)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: border,
              width: isSolved ? 2.0 : 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSumCell(int row, int col, bool isWaiting) {
    final val = _sumSpec.ticketMatrix[row][col];
    final isEmpty = val == 0;
    final qNum = (col ~/ 3) + 1;
    final activeQuad = _sumSpec.waves[_sumWaveIndex].quadrant;
    final isSolvedQuad = _solvedSumQuadrants.contains(qNum);
    final isCurrentActiveQuad = qNum == activeQuad;

    String label = '';
    Color bg = const Color(0xFF0B1120);
    Color border = const Color(0xFF1E293B);
    Color textColor = Colors.white;

    if (isEmpty) {
      bg = const Color(0xFF0B1120);
      border = const Color(0xFF1E293B);
    } else if (isSolvedQuad) {
      label = '$val';
      bg = const Color(0xFF059669);
      border = const Color(0xFF34D399);
      textColor = Colors.white;
    } else if (!isCurrentActiveQuad) {
      label = '·';
      bg = const Color(0xFF111827);
      border = const Color(0xFF1F2937);
      textColor = Colors.white24;
    } else if (isWaiting) {
      label = '•';
      bg = const Color(0xFF1E1B4B);
      border = AppTheme.secondaryColor.withValues(alpha: 0.6);
      textColor = AppTheme.secondaryColor;
    } else {
      label = '$val';
      bg = const Color(0xFF312E81);
      border = AppTheme.secondaryColor;
      textColor = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: border,
            width: (isCurrentActiveQuad && !isEmpty) || isSolvedQuad
                ? 1.8
                : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
