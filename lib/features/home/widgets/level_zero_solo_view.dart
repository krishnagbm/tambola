import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/level_zero_skill_engine.dart';
import 'skill_friend_squad_controller.dart';

class LevelZeroSoloView extends StatefulWidget {
  final String gameId; // 'level_0a_make', 'level_0b_fix', 'level_0c_math', 'level_0d_sum'
  final VoidCallback? onLevelCompleted;
  final ValueChanged<String>? onSelectGameId;
  final SkillFriendSquadController? squadController;
  final int? sharedSeed;
  final String? sharedSubMode;
  final bool autoStart;
  final void Function(String subMode, int seed)? onLocalStateChanged;

  const LevelZeroSoloView({
    super.key,
    required this.gameId,
    this.onLevelCompleted,
    this.onSelectGameId,
    this.squadController,
    this.sharedSeed,
    this.sharedSubMode,
    this.autoStart = false,
    this.onLocalStateChanged,
  });

  @override
  State<LevelZeroSoloView> createState() => _LevelZeroSoloViewState();
}

class _LevelZeroSoloViewState extends State<LevelZeroSoloView> {
  Timer? _uiTimer;
  int _currentSeed = 1001;
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

  // Level 0A: MakeHousie state (Mystery ? balls + Drag & Drop + DAB to Validate)
  String _makeMode = MakeHousieRoundSpec.modeMake5Quad;
  late MakeHousieRoundSpec _makeSpec;
  late List<List<int>> _makeLiveBoard;
  final Set<int> _revealedMakeBalls = <int>{};
  final Set<int> _onBoardMakeBalls = <int>{};
  final Set<String> _dabFlaggedCells = <String>{};
  int? _selectedDealBall;
  bool _isDraggingMakeBall = false;

  // Level 0B: FixHousie state
  String _fixMode = FixHousieRoundSpec.modeFix3;
  late FixHousieRoundSpec _fixSpec;
  final Set<String> _repairedCellKeys = <String>{};
  int? _fixSelectedBall;
  bool _isDraggingFixBall = false;

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

  String get _activeSubModeForGame {
    switch (widget.gameId) {
      case 'level_0a_make':
        return _makeMode;
      case 'level_0b_fix':
        return _fixMode;
      case 'level_0c_math':
        return _mathMode;
      default:
        return _sumMode;
    }
  }

  void _applySubModeIfMatching(String? subMode) {
    if (subMode == null || subMode.isEmpty) return;
    if (widget.gameId == 'level_0a_make' &&
        (subMode == MakeHousieRoundSpec.modeMake5Quad ||
            subMode == MakeHousieRoundSpec.modeMake15Guided ||
            subMode == MakeHousieRoundSpec.modeMake15Master)) {
      _makeMode = subMode;
    } else if (widget.gameId == 'level_0b_fix' &&
        (subMode == FixHousieRoundSpec.modeFix1 ||
            subMode == FixHousieRoundSpec.modeFix3 ||
            subMode == FixHousieRoundSpec.modeFix5)) {
      _fixMode = subMode;
    } else if (widget.gameId == 'level_0c_math' &&
        (subMode == MathHousieRoundSpec.modeAddSub5 ||
            subMode == MathHousieRoundSpec.modeMulDiv5 ||
            subMode == MathHousieRoundSpec.modeMixed10)) {
      _mathMode = subMode;
    } else if (widget.gameId == 'level_0d_sum' &&
        (subMode == SumHousieRoundSpec.modeSumQ1 ||
            subMode == SumHousieRoundSpec.modeSumQ2 ||
            subMode == SumHousieRoundSpec.modeSumQ3 ||
            subMode == SumHousieRoundSpec.modeSumAll3)) {
      _sumMode = subMode;
    }
  }

  @override
  void initState() {
    super.initState();
    _applySubModeIfMatching(widget.sharedSubMode);
    _initCurrentGame(
      autoStart: widget.autoStart,
      explicitSeed: widget.sharedSeed,
      broadcastToSquad: false,
    );
    // Rebuild when squad mate claims/releases a ball
    widget.squadController?.addListener(_onSquadChanged);
    _attachSquadGameCallbacks();
  }

  void _attachSquadGameCallbacks() {
    final sq = widget.squadController;
    if (sq == null) return;
    sq.onRemoteBogeyDab = (flaggedCells, issue, playerName) {
      if (!mounted) return;
      setState(() {
        _dabFlaggedCells
          ..clear()
          ..addAll(flaggedCells);
        _feedbackBannerText = '🚨 $playerName pressed Bogey Dab! $issue';
        _feedbackIsError = true;
      });
    };
    sq.onRemoteCancelGame = (playerName) {
      if (!mounted) return;
      setState(() {
        _feedbackBannerText = '🛑 $playerName cancelled the active game round.';
        _feedbackIsError = true;
      });
      _initCurrentGame(autoStart: false, broadcastToSquad: false);
    };
  }

  @override
  void didUpdateWidget(covariant LevelZeroSoloView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.squadController != widget.squadController) {
      oldWidget.squadController?.removeListener(_onSquadChanged);
      widget.squadController?.addListener(_onSquadChanged);
      _attachSquadGameCallbacks();
    }
    if (oldWidget.gameId != widget.gameId) {
      _applySubModeIfMatching(widget.sharedSubMode);
      _initCurrentGame(
        autoStart: widget.autoStart,
        explicitSeed: widget.sharedSeed,
        broadcastToSquad: false,
      );
    } else if ((widget.sharedSeed != null &&
            widget.sharedSeed != _currentSeed) ||
        (widget.sharedSubMode != null &&
            widget.sharedSubMode != _activeSubModeForGame) ||
        (widget.autoStart && _startedAtMs == null)) {
      _applySubModeIfMatching(widget.sharedSubMode);
      _initCurrentGame(
        autoStart: widget.autoStart,
        explicitSeed: widget.sharedSeed,
        broadcastToSquad: false,
      );
    }
  }

  void _onSquadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    widget.squadController?.removeListener(_onSquadChanged);
    super.dispose();
  }

  void _startClockTicker() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _roundCompleted) return;
      setState(() {});
    });
  }

  void _initCurrentGame({
    required bool autoStart,
    int? explicitSeed,
    bool broadcastToSquad = true,
  }) {
    _uiTimer?.cancel();
    _uiTimer = null;
    _currentSeed = explicitSeed ?? (1000 + Random().nextInt(899999));
    final rng = Random(_currentSeed);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    _makeSpec = MakeHousieRoundSpec.generate(mode: _makeMode, random: rng);
    _makeLiveBoard = _makeSpec.createInitialBoard();
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

      _revealedMakeBalls.clear();
      _onBoardMakeBalls.clear();
      _dabFlaggedCells.clear();
      _selectedDealBall = null;
      _isDraggingMakeBall = false;

      _repairedCellKeys.clear();
      _fixSelectedBall = null;
      _isDraggingFixBall = false;

      _mathPromptIndex = 0;
      _solvedMathTargets.clear();

      _sumWaveIndex = 0;
      _solvedSumQuadrants.clear();
      _wrongSumOptions.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onLocalStateChanged?.call(_activeSubModeForGame, _currentSeed);
      if (broadcastToSquad && (widget.squadController?.isInSquad ?? false)) {
        widget.squadController!.broadcastRoundSync(
          gameId: widget.gameId,
          subMode: _activeSubModeForGame,
          roundSeed: _currentSeed,
          autoStart: autoStart,
        );
      }
      _reportSquadProgress();
    });

    if (autoStart) {
      _startClockTicker();
    }
  }

  void _reportSquadProgress({String? eventText}) {
    final sq = widget.squadController;
    if (sq == null) return;
    final progressVal = widget.gameId == 'level_0a_make' && !_roundCompleted
        ? _onBoardMakeBalls.length
        : _correctCount;
    sq.reportLocalProgress(
      score: _netScore,
      progress: progressVal,
      target: _targetStepCount,
      wrongCount: _wrongCount,
      reactionMs: _totalReactionMs,
      completed: _roundCompleted,
      eventText: eventText,
    );
  }

  void _launchRound({bool broadcastToSquad = true}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _startedAtMs = nowMs;
      _stepStartedAtMs = nowMs;
      _roundCompleted = false;
      _feedbackBannerText = null;
      _feedbackIsError = false;
    });
    if (broadcastToSquad && (widget.squadController?.isInSquad ?? false)) {
      widget.squadController!.broadcastRoundSync(
        gameId: widget.gameId,
        subMode: _activeSubModeForGame,
        roundSeed: _currentSeed,
        autoStart: true,
      );
    }
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

    final elapsedSec = _startedAtMs != null
        ? ((nowMs - _startedAtMs!) / 1000).clamp(0.1, 999.0).toStringAsFixed(1)
        : '0.0';
    _reportSquadProgress(
      eventText: '🏆 VALID DAB! Cleared in ${elapsedSec}s ($_netScore pts)!',
    );

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

  /// Called when the player grabs/starts dragging or taps a ball in MakeHousie™.
  /// Auto-starts the round clock if not already running and reveals the mystery ball!
  void _onMakeBallPicked(int ball, {required bool isDrag}) {
    if (_roundCompleted) return;
    if (_startedAtMs == null) {
      _launchRound();
    }
    setState(() {
      _revealedMakeBalls.add(ball);
      _selectedDealBall = ball;
      if (isDrag) {
        _isDraggingMakeBall = true;
      }
      _feedbackBannerText =
          '🎯 Ball #$ball revealed! Drop it onto its Decade Column & Row — then hit ✋ DAB when all balls are placed!';
      _feedbackIsError = false;
    });
  }

  void _onMakeDragEnded() {
    if (!mounted) return;
    setState(() {
      _isDraggingMakeBall = false;
    });
  }

  /// Handles dropping [ball] onto cell ([row], [col]) on the 3×9 grid.
  /// Does NOT validate until all balls are placed and the player presses "✋ DAB TO VALIDATE!"
  void _handleMakeBallDrop(int ball, int row, int col) {
    if (_roundCompleted) return;
    if (_startedAtMs == null) {
      _launchRound();
    }
    if (!_makeSpec.isColumnActive(col)) {
      setState(() {
        _isDraggingMakeBall = false;
        _feedbackBannerText =
            '🔒 Col ${col + 1} is pre-filled! Drop Ball #$ball into an active quadrant.';
        _feedbackIsError = true;
      });
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stepMs = _stepStartedAtMs != null
        ? (nowMs - _stepStartedAtMs!).clamp(150, 30000)
        : 1000;

    // Locate if [ball] was already sitting on _makeLiveBoard
    int? fromR;
    int? fromC;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        if (_makeLiveBoard[r][c] == ball) {
          fromR = r;
          fromC = c;
          break;
        }
      }
    }

    // If dropped onto the exact same cell it came from, just clear drag state
    if (fromR == row && fromC == col) {
      setState(() {
        _isDraggingMakeBall = false;
      });
      return;
    }

    if (fromR != null && fromC != null) {
      _makeLiveBoard[fromR][fromC] = 0;
      _dabFlaggedCells.remove('${fromR}_$fromC');
    }

    final occupant = _makeLiveBoard[row][col];
    if (occupant > 0 && occupant != ball) {
      if (fromR != null && fromC != null) {
        // Swap with the origin grid cell!
        _makeLiveBoard[fromR][fromC] = occupant;
      } else {
        // Came from Deal Pool onto an occupied cell -> shift occupant to an open row in this column if available
        int? openRow;
        if (ball < occupant && row == 0) {
          if (_makeLiveBoard[1][col] == 0) {
            openRow = 1;
          } else if (_makeLiveBoard[2][col] == 0) {
            openRow = 2;
          }
        } else if (ball > occupant && row == 2) {
          if (_makeLiveBoard[1][col] == 0) {
            openRow = 1;
          } else if (_makeLiveBoard[0][col] == 0) {
            openRow = 0;
          }
        }
        openRow ??= [0, 1, 2].cast<int?>().firstWhere(
          (r) => r != row && _makeLiveBoard[r!][col] == 0,
          orElse: () => null,
        );
        if (openRow != null) {
          _makeLiveBoard[openRow][col] = occupant;
          _dabFlaggedCells.remove('${openRow}_$col');
        } else {
          // All 3 rows in this column were full -> return occupant to Deal Pool (already revealed)
          _onBoardMakeBalls.remove(occupant);
        }
      }
    }

    // Broadcast ball_lifted for the ball's old cell if it was already on the board
    if (fromR != null && fromC != null) {
      widget.squadController?.broadcastBallLifted(ball: ball);
    }

    _makeLiveBoard[row][col] = ball;
    _onBoardMakeBalls.add(ball);
    _revealedMakeBalls.add(ball);
    _dabFlaggedCells.remove('${row}_$col');

    // Broadcast ball_placed so squad mates can see this cell is claimed
    widget.squadController?.broadcastBallPlaced(ball: ball, row: row, col: col);
    // Also remove this ball from remote claims (we own it now)
    widget.squadController?.remotePlacements.remove(ball);

    // If the player is actively fixing cells after a Bogey Dab, refresh _dabFlaggedCells
    // so once a row overflow (e.g. 7 balls -> 5 balls) is resolved, the remaining 5 balls in that row unflag!
    final wasFixingBogeyDab = _dabFlaggedCells.isNotEmpty;
    if (wasFixingBogeyDab) {
      final stillOverflowCells = _makeSpec.findRowOverflowCells(_makeLiveBoard);
      _dabFlaggedCells.retainWhere((cellKey) {
        final parts = cellKey.split('_');
        final r = int.parse(parts[0]);
        final c = int.parse(parts[1]);
        if (_makeLiveBoard[r][c] <= 0) return false;
        if (_makeSpec.evaluateCellIssue(_makeLiveBoard, r, c) != null) {
          return true;
        }
        return stillOverflowCells.contains(cellKey);
      });
    }

    final allPlaced = _onBoardMakeBalls.length >= _makeSpec.dealPool.length;

    setState(() {
      _isDraggingMakeBall = false;
      _selectedDealBall = null;
      _totalReactionMs += stepMs;
      _stepStartedAtMs = nowMs;

      if (allPlaced) {
        if (wasFixingBogeyDab && _dabFlaggedCells.isNotEmpty) {
          final rowIssue = _makeSpec.evaluateRowOverflowIssue(_makeLiveBoard);
          _feedbackBannerText =
              rowIssue ??
              '⚠️ Moved Ball #$ball to Col ${col + 1}, Row ${row + 1} • Fix remaining red cell(s), then press "✋ DAB TO VALIDATE!"';
          _feedbackIsError = true;
        } else {
          _feedbackBannerText =
              '✋ All ${_makeSpec.dealPool.length} balls filled in! Check Col Decades, Order & 5-per-Row, then press "✋ DAB TO VALIDATE!"';
          _feedbackIsError = false;
        }
      } else {
        _feedbackBannerText =
            'Dropped Ball #$ball into Col ${col + 1}, Row ${row + 1} (${_onBoardMakeBalls.length}/${_makeSpec.dealPool.length} placed — grab next ? ball!)';
        _feedbackIsError = false;
      }
    });
    _reportSquadProgress();
  }

  /// Triggered when the player clicks the "✋ DAB TO VALIDATE!" button once all balls are placed.
  void _handleMakeDabValidate() {
    if (_roundCompleted) return;
    if (_onBoardMakeBalls.length < _makeSpec.dealPool.length) {
      setState(() {
        _feedbackBannerText =
            '⚠️ Place all ${_makeSpec.dealPool.length} balls onto the grid before pressing ✋ DAB!';
        _feedbackIsError = true;
      });
      return;
    }

    final flagged = <String>{};
    String? firstIssue;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        if (!_makeSpec.isColumnActive(c)) continue;
        if (_makeLiveBoard[r][c] > 0) {
          final iss = _makeSpec.evaluateCellIssue(_makeLiveBoard, r, c);
          if (iss != null) {
            flagged.add('${r}_$c');
            firstIssue ??= iss;
          }
        }
      }
    }

    // Check Rule 3: Horizontal Row Balance (Every row must have 5 numbers — no row overflow!)
    final rowOverflowIssue = _makeSpec.evaluateRowOverflowIssue(_makeLiveBoard);
    if (rowOverflowIssue != null) {
      flagged.addAll(_makeSpec.findRowOverflowCells(_makeLiveBoard));
      firstIssue ??= rowOverflowIssue;
    }

    if (flagged.isEmpty && _makeSpec.isBoardSolved(_makeLiveBoard)) {
      setState(() {
        _dabFlaggedCells.clear();
        _correctCount = _makeSpec.dealPool.length;
        _feedbackBannerText =
            '🏆 VALID DAB! All ${_makeSpec.dealPool.length} balls verified in right Column Decades, Ascending Order & 5 per Row!';
        _feedbackIsError = false;
      });
      _completeRound();
    } else {
      setState(() {
        _wrongCount++;
        _totalReactionMs += 2000;
        _dabFlaggedCells
          ..clear()
          ..addAll(flagged);
        _correctCount = _makeSpec.countValidPlacements(_makeLiveBoard);
        _feedbackBannerText =
            '🚨 BOGEY DAB (-3 pts)! $firstIssue';
        _feedbackIsError = true;
      });
      widget.squadController?.broadcastBogeyDab(
        flaggedCells: flagged.toList(),
        issue: firstIssue ?? 'Ticket has column decade, order, or row overflow issues!',
      );
      _reportSquadProgress(eventText: '🚨 Bogey Dab (-3 pts)! Fixing board...');
    }
  }

  void _handleMakeCellTap(int row, int col) {
    if (_roundCompleted) return;
    final currentCellVal = _makeLiveBoard[row][col];
    // If a ball is currently picked/selected, tapping a cell drops it there
    if (_selectedDealBall != null) {
      _handleMakeBallDrop(_selectedDealBall!, row, col);
      return;
    }
    // Otherwise, tapping an already-placed ball on the grid picks it up so the player can move it
    if (currentCellVal > 0 && _makeSpec.isColumnActive(col)) {
      _onMakeBallPicked(currentCellVal, isDrag: false);
    }
  }

  void _onFixBallPicked(int ball, {required bool isDrag}) {
    if (_roundCompleted) return;
    if (_startedAtMs == null) {
      _launchRound();
    }
    setState(() {
      _fixSelectedBall = ball;
      if (isDrag) {
        _isDraggingFixBall = true;
      }
      _feedbackBannerText =
          '🎯 Ball #$ball grabbed! Drop it into its correct column decade & order or tap the buggy cell.';
      _feedbackIsError = false;
    });
  }

  void _onFixDragEnded() {
    if (!mounted) return;
    setState(() {
      _isDraggingFixBall = false;
    });
  }

  void _handleFixBallDrop(int ball, int targetRow, int targetCol) {
    if (_startedAtMs == null) {
      _launchRound();
    }
    if (_roundCompleted) return;
    setState(() {
      _isDraggingFixBall = false;
      _fixSelectedBall = null;
    });

    final targetKey = '${targetRow}_$targetCol';
    if (_repairedCellKeys.contains(targetKey)) return;

    // Check if target cell has a bug
    final bug = _fixSpec.bugsByCellKey[targetKey];
    if (bug != null) {
      // Repaired! Either dragging the bug ball to its target or dropping correct ball
      _repairFixBug(targetRow, targetCol, bug);
      return;
    }

    // Check if the dragged ball originated from a buggy cell
    for (final entry in _fixSpec.bugsByCellKey.entries) {
      if (_repairedCellKeys.contains(entry.key)) continue;
      if (entry.value.bugValue == ball) {
        // Dragged a buggy ball! If dropped into correct column or cell, repair it
        final expectedCol = expectedColumnForBall(ball);
        if (targetCol == expectedCol || targetCol == entry.value.col) {
          _repairFixBug(entry.value.row, entry.value.col, entry.value);
          return;
        }
      }
    }

    // Otherwise, dropping onto a valid cell that had no bug
    _flashWrongCell(targetRow, targetCol);
    setState(() {
      _wrongCount++;
      _totalReactionMs += 2000;
      _feedbackBannerText =
          '✖ Misplaced Drop (-5 pts): Col ${targetCol + 1} (${columnDecadeLabel(targetCol)}) is not the bug location!';
      _feedbackIsError = true;
    });
    _reportSquadProgress(eventText: '✖ Wrong drop (-5 pts)');
  }

  void _repairFixBug(int row, int col, FixBugSpec bug) {
    final cellKey = '${row}_$col';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
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
    } else {
      _reportSquadProgress();
    }
  }

  void _handleFixCellTap(int row, int col) {
    if (_startedAtMs == null) {
      _launchRound();
    }
    if (_roundCompleted) return;
    final cellKey = '${row}_$col';
    if (_repairedCellKeys.contains(cellKey)) return;

    // If a ball was selected/picked, tapping a cell drops it
    if (_fixSelectedBall != null) {
      _handleFixBallDrop(_fixSelectedBall!, row, col);
      return;
    }

    final bug = _fixSpec.bugsByCellKey[cellKey];
    if (bug != null) {
      _repairFixBug(row, col, bug);
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
      _reportSquadProgress(eventText: '✖ Wrong tap (-5 pts)');
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
      } else {
        _reportSquadProgress();
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
      _reportSquadProgress(eventText: '✖ Wrong formula tap (-3 pts)');
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
      } else {
        _reportSquadProgress();
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
      _reportSquadProgress(eventText: '✖ Decoy sum (-5 pts)');
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

        // 4. Game-Specific Interactive Strip (Deal Pool for MakeHousie, Fix Strip for FixHousie, MCQ Bar for SumHousie)
        if (widget.gameId == 'level_0a_make') ...[
          _buildMakeDealPoolStrip(isWaiting),
          const SizedBox(height: 10),
        ] else if (widget.gameId == 'level_0b_fix') ...[
          _buildFixHelperStrip(isWaiting),
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
          (MakeHousieRoundSpec.modeMake15Guided, 'Make 10 (2 Quads)'),
          (MakeHousieRoundSpec.modeMake15Master, 'Make 15 (Full Grid)'),
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
          (SumHousieRoundSpec.modeSumQ3, 'Sum Q3 (Hard 60–90)'),
          (SumHousieRoundSpec.modeSumAll3, 'Sum All 3 (Hardest Q1→Q3)'),
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            if (!isWaiting && !_roundCompleted) ...[
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () {
                  widget.squadController?.broadcastCancelGame();
                  setState(() {
                    _feedbackBannerText = '🛑 Game round cancelled.';
                    _feedbackIsError = true;
                  });
                  _initCurrentGame(autoStart: false, broadcastToSquad: false);
                },
                icon: const Icon(Icons.cancel_outlined, size: 15),
                label: const Text('Cancel Game'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                  side: const BorderSide(
                    color: Color(0xFFEF4444),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
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
              '🏆 LEVEL 0A CLEARED! ALL ${_makeSpec.dealPool.length} MYSTERY BALLS PLACED VALIDLY!';
          subline =
              'You mastered 3×9 column decades, ascending order & 5-per-row balance! Try Make 10/15 or advance to 0B FixHousie™.';
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
              '🎓 MakeHousie™ Ready • Drag & Drop ${_makeSpec.dealPool.length} Mystery (?) Balls onto the 3×9 Grid';
          subline =
              'Pick any (?) ball to reveal its number, drop into its Column Decade & Ascending Row (5 balls per row), then press ✋ DAB!';
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
            headline = _selectedDealBall != null
                ? '🎯 Ball #$_selectedDealBall revealed! Drag & drop it into its valid Decade Column & Ascending Row!'
                : '🎱 Grab & drag any Mystery (?) ball below to reveal its number and drop it on the 3×9 grid!';
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
          'Rule 1: Col Decades (1–9 … 80–90) • Rule 2: Ascending Col Order • Rule 3: 5 Numbers per Row • Press ✋ DAB to validate!';
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
                  widget.gameId == 'level_0a_make' && !_roundCompleted
                      ? '📥 ${_onBoardMakeBalls.length}/$_targetStepCount  •  ✖ $_wrongCount'
                      : '✓ $_correctCount/$_targetStepCount  •  ✖ $_wrongCount',
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
        final allPlaced = _onBoardMakeBalls.length >= _makeSpec.dealPool.length;
        if (allPlaced && ball == null) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: _handleMakeDabValidate,
                icon: const Icon(Icons.pan_tool_alt_rounded, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '✋ DAB TO VALIDATE!',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _dabFlaggedCells.isNotEmpty
                    ? '${_dabFlaggedCells.length} cell(s) flagged • Fix & DAB!'
                    : 'All ${_makeSpec.dealPool.length} placed • Lock in claim!',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _dabFlaggedCells.isNotEmpty
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFF34D399),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ball != null
                    ? AppTheme.secondaryColor
                    : const Color(0xFF1E293B),
                shape: BoxShape.circle,
                border: Border.all(
                  color: ball != null ? Colors.white : AppTheme.secondaryColor,
                  width: 1.5,
                ),
              ),
              child: Text(
                ball != null ? '$ball' : '?',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: ball != null ? Colors.black : AppTheme.secondaryColor,
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
                    ball != null
                        ? 'Ball #$ball Revealed!'
                        : 'Drag Any (?) Ball',
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
                    ball != null
                        ? 'Drop into valid Col & Row!'
                        : 'Reveals on grab • Drop on grid',
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

  Widget _buildDragFeedbackBadge(int ball) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 48,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.secondaryColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          '$ball',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  bool _isBallFlaggedByDab(int ball) {
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 9; c++) {
        if (_makeLiveBoard[r][c] == ball) {
          return _dabFlaggedCells.contains('${r}_$c');
        }
      }
    }
    return false;
  }

  Widget _buildMakeDealPoolStrip(bool isWaiting) {
    final allPlaced = _onBoardMakeBalls.length >= _makeSpec.dealPool.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allPlaced && !_roundCompleted
              ? const Color(0xFF10B981)
              : const Color(0xFF2E334D),
          width: allPlaced && !_roundCompleted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isWaiting
                      ? '🎱 Mystery Ball Pool (${_makeSpec.dealPool.length} random ? balls — click "▶ Start" or drag any ? ball!)'
                      : (allPlaced
                            ? '✋ All ${_makeSpec.dealPool.length} balls placed on grid! Press "✋ DAB TO VALIDATE!" when ready'
                            : '🎱 Mystery Ball Pool (Drag any ? ball to reveal its number & drop onto the 3×9 grid)'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: allPlaced && !_roundCompleted
                        ? const Color(0xFF34D399)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_roundCompleted)
                ElevatedButton.icon(
                  onPressed: allPlaced ? _handleMakeDabValidate : null,
                  icon: const Icon(Icons.pan_tool_alt_rounded, size: 14),
                  label: Text(
                    allPlaced
                        ? '✋ DAB TO VALIDATE!'
                        : 'DAB (${_onBoardMakeBalls.length}/${_makeSpec.dealPool.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF1E293B),
                    disabledForegroundColor: const Color(0xFF64748B),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 30),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
              else
                Text(
                  '✓ ${_makeSpec.dealPool.length}/${_makeSpec.dealPool.length} Validated!',
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
              final isOnBoard = _onBoardMakeBalls.contains(ball);
              final isFlagged = isOnBoard && _isBallFlaggedByDab(ball);
              final isRevealed = _revealedMakeBalls.contains(ball);
              final isSelected = !isOnBoard && _selectedDealBall == ball;

              // Squad mate claimed this ball (placed it on their grid)
              final remotePlacement =
                  !isOnBoard ? widget.squadController?.remotePlacements[ball] : null;
              final isClaimed = remotePlacement != null;

              final chipWidget = Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isOnBoard
                          ? (_roundCompleted
                                ? const Color(0xFF064E3B)
                                : (isFlagged
                                      ? const Color(0xFF7F1D1D)
                                      : const Color(0xFF1E293B)))
                          : (isClaimed
                                ? const Color(0xFF422006) // amber-dark for claimed
                                : (isSelected
                                      ? AppTheme.secondaryColor
                                      : (isRevealed
                                            ? const Color(0xFF312E81)
                                            : const Color(0xFF1E293B)))),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isOnBoard
                            ? (_roundCompleted
                                  ? const Color(0xFF10B981)
                                  : (isFlagged
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF475569)))
                            : (isClaimed
                                  ? const Color(0xFFF59E0B) // amber border
                                  : (isSelected
                                        ? Colors.white
                                        : (isRevealed
                                              ? AppTheme.secondaryColor
                                              : const Color(0xFF475569)))),
                        width: (isSelected || isRevealed || isClaimed) ? 1.6 : 1.0,
                      ),
                    ),
                    child: Text(
                      isOnBoard
                          ? (_roundCompleted ? '✓' : (isFlagged ? '⚠️' : '📥'))
                          : (isClaimed
                                ? '🔒'
                                : (isRevealed ? '$ball' : '?')),
                      style: TextStyle(
                        fontSize: isClaimed ? 15 : 13.5,
                        fontWeight: FontWeight.w900,
                        color: isOnBoard
                            ? (_roundCompleted
                                  ? const Color(0xFF34D399)
                                  : (isFlagged
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF94A3B8)))
                            : (isClaimed
                                  ? const Color(0xFFF59E0B)
                                  : (isSelected
                                        ? Colors.black
                                        : (isRevealed
                                              ? Colors.white
                                              : AppTheme.secondaryColor))),
                      ),
                    ),
                  ),
                  // Claimer avatar badge (top-right corner)
                  if (isClaimed)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF59E0B),
                            width: 1.2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          remotePlacement.playerAvatar,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                ],
              );

              if (isOnBoard || _roundCompleted || isClaimed) {
                // Claimed balls: show tooltip with claimer name, but not draggable
                if (isClaimed) {
                  return Tooltip(
                    message: '${remotePlacement.playerAvatar} ${remotePlacement.playerName} placed this ball',
                    preferBelow: false,
                    child: chipWidget,
                  );
                }
                return chipWidget;
              }

              return Draggable<int>(
                data: ball,
                feedback: _buildDragFeedbackBadge(ball),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: chipWidget,
                ),
                onDragStarted: () => _onMakeBallPicked(ball, isDrag: true),
                onDragEnd: (_) => _onMakeDragEnded(),
                onDraggableCanceled: (_, _) => _onMakeDragEnded(),
                child: InkWell(
                  onTap: () => _onMakeBallPicked(ball, isDrag: false),
                  borderRadius: BorderRadius.circular(8),
                  child: chipWidget,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFixHelperStrip(bool isWaiting) {
    final remBugs = _fixSpec.totalBugs - _repairedCellKeys.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: remBugs == 0 ? const Color(0xFF10B981) : const Color(0xFF2E334D),
          width: remBugs == 0 ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              isWaiting
                  ? '🔍 FixHousie™ • Spot & fix $_remBugText (tap or drag balls to swap/fix!)'
                  : (remBugs == 0
                        ? '🎉 All $_remBugText repaired! Mastered 3×9 ticket audit!'
                        : '🔍 Spot $_remBugText: Drag any buggy ball into its correct column, or tap the cell!'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: remBugs == 0 ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: remBugs == 0
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: remBugs == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              ),
            ),
            child: Text(
              remBugs == 0 ? '✓ ALL FIXED' : '$remBugs LEFT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: remBugs == 0 ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _remBugText {
    final count = _fixSpec.totalBugs;
    return '$count bug${count == 1 ? '' : 's'}';
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
    final inActiveQuad = _makeSpec.isColumnActive(col);
    final cellVal = _makeLiveBoard[row][col];
    final showDropPlaceholders =
        inActiveQuad &&
        !_roundCompleted &&
        (_isDraggingMakeBall || _selectedDealBall != null);

    // Pre-filled locked quadrant cells (in Make 5 or Make 10 modes)
    if (!inActiveQuad) {
      final isEmpty = cellVal == 0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isEmpty ? const Color(0xFF0B1120) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEmpty
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF334155),
            ),
          ),
          child: Text(
            isEmpty ? '' : '$cellVal',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => !_roundCompleted,
        onAcceptWithDetails: (details) =>
            _handleMakeBallDrop(details.data, row, col),
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;
          final isMisplaced = _dabFlaggedCells.contains('${row}_$col');

          String label = '';
          Color bg = const Color(0xFF0B1120);
          Color border = const Color(0xFF1E293B);
          Color textColor = Colors.white;
          double borderWidth = 1.0;

          if (cellVal > 0) {
            if (_roundCompleted) {
              // Validated & Solved!
              label = '$cellVal';
              bg = const Color(0xFF059669);
              border = const Color(0xFF34D399);
              textColor = Colors.white;
              borderWidth = 1.6;
            } else if (isMisplaced) {
              // Flagged by a Bogey Dab — drag to fix!
              label = '$cellVal ⇄';
              bg = isHovered
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFF7F1D1D);
              border = const Color(0xFFFBBF24);
              textColor = const Color(0xFFFDE68A);
              borderWidth = 1.8;
            } else {
              // Placed on board, awaiting "✋ DAB TO VALIDATE!" (neutral, unspoiled)
              label = '$cellVal';
              bg = isHovered
                  ? const Color(0xFF4338CA)
                  : const Color(0xFF312E81);
              border = AppTheme.secondaryColor;
              textColor = Colors.white;
              borderWidth = 1.6;
            }
          } else if (isHovered) {
            label = '⬇';
            bg = AppTheme.secondaryColor.withValues(alpha: 0.30);
            border = AppTheme.secondaryColor;
            textColor = AppTheme.secondaryColor;
            borderWidth = 2.0;
          } else if (showDropPlaceholders) {
            // Uniform drop placeholder on all empty cells of active quadrant(s) while dragging/holding a ball
            label = '⬇';
            bg = const Color(0xFF172554);
            border = AppTheme.secondaryColor.withValues(alpha: 0.55);
            textColor = AppTheme.secondaryColor.withValues(alpha: 0.85);
            borderWidth = 1.3;
          } else {
            // Idle empty cell: NO pre-highlighted cells!
            label = '';
            bg = const Color(0xFF0B1120);
            border = const Color(0xFF1E293B);
            borderWidth = 1.0;
          }

          final remotePlacement = widget.squadController?.remotePlacements[cellVal];
          final isClaimed = remotePlacement != null &&
              remotePlacement.playerName != widget.squadController?.localName;

          final cellBox = InkWell(
            onTap: !_roundCompleted
                ? () => _handleMakeCellTap(row, col)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isClaimed ? const Color(0xFFF59E0B) : border,
                      width: isClaimed ? 1.8 : borderWidth,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: isMisplaced ? 13.5 : 15,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                ),
                if (isClaimed)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Tooltip(
                      message: '${remotePlacement.playerAvatar} ${remotePlacement.playerName} dropped this ball (Drag to rearrange!)',
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF59E0B),
                            width: 1.2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          remotePlacement.playerAvatar,
                          style: const TextStyle(fontSize: 9.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );

          // Any placed ball on the grid (including squad mates' placed balls) can be dragged to another cell!
          if (cellVal > 0 && !_roundCompleted) {
            return Draggable<int>(
              data: cellVal,
              feedback: _buildDragFeedbackBadge(cellVal),
              childWhenDragging: Opacity(opacity: 0.35, child: cellBox),
              onDragStarted: () => _onMakeBallPicked(cellVal, isDrag: true),
              onDragEnd: (_) => _onMakeDragEnded(),
              onDraggableCanceled: (_, _) => _onMakeDragEnded(),
              child: cellBox,
            );
          }

          return cellBox;
        },
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) =>
            !isWaiting && !_roundCompleted && !isRepaired,
        onAcceptWithDetails: (details) =>
            _handleFixBallDrop(details.data, row, col),
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;

          String label = '';
          Color bg = const Color(0xFF0B1120);
          Color border = const Color(0xFF1E293B);
          Color textColor = Colors.white;

          if (isEmpty) {
            if (isHovered) {
              label = '⬇';
              bg = AppTheme.secondaryColor.withValues(alpha: 0.25);
              border = AppTheme.secondaryColor;
              textColor = AppTheme.secondaryColor;
            } else if (_isDraggingFixBall || _fixSelectedBall != null) {
              label = '⬇';
              bg = const Color(0xFF172554);
              border = AppTheme.secondaryColor.withValues(alpha: 0.45);
              textColor = AppTheme.secondaryColor.withValues(alpha: 0.75);
            } else {
              bg = const Color(0xFF0B1120);
              border = const Color(0xFF1E293B);
            }
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
          } else if (isHovered) {
            label = '$bugVal';
            bg = const Color(0xFF4338CA);
            border = AppTheme.secondaryColor;
            textColor = Colors.white;
          } else {
            label = '$bugVal';
            bg = const Color(0xFF1E293B);
            border = const Color(0xFF475569);
            textColor = Colors.white;
          }

          final cellBox = InkWell(
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
          );

          // Allow dragging buggy or unrepaired numbers to drop onto target cells!
          if (!isWaiting && !_roundCompleted && !isEmpty && !isRepaired) {
            return Draggable<int>(
              data: bugVal,
              feedback: _buildDragFeedbackBadge(bugVal),
              childWhenDragging: Opacity(opacity: 0.35, child: cellBox),
              onDragStarted: () => _onFixBallPicked(bugVal, isDrag: true),
              onDragEnd: (_) => _onFixDragEnded(),
              onDraggableCanceled: (_, _) => _onFixDragEnded(),
              child: cellBox,
            );
          }

          return cellBox;
        },
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
