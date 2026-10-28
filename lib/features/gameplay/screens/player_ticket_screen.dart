import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../core/utils/tambola_ticket.dart';
import '../../../core/utils/wake_lock_helper.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/celebration_overlay.dart';
import '../../../models/flash_housie_config.dart';
import '../../../models/mpt_called_number.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_game_trivia.dart';
import '../../../models/mpt_ticket.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';

class PlayerTicketScreen extends ConsumerStatefulWidget {
  final String gameId;

  const PlayerTicketScreen({super.key, required this.gameId});

  @override
  ConsumerState<PlayerTicketScreen> createState() => _PlayerTicketScreenState();
}

class _PlayerTicketScreenState extends ConsumerState<PlayerTicketScreen> {
  final Set<int> _markedNumbers = {};
  bool _isClaiming = false;
  bool _isClaimingBounty = false;
  bool _voiceEnabled = false;
  int _lastAnnouncedSeq = 0;
  bool _showCelebration = false;
  Timer? _finalGraceTimer;
  int _finalGraceSecondsLeft = 0;
  bool _hasStartedFinalGrace = false;

  // FlashHousie™ 5 / 10 / 15 & NeuroWave™ Spotlight State
  Timer? _neuroWaveUiTimer;
  final Map<int, Set<int>> _flashRecalledByCycle = {};
  final Map<int, int> _flashWrongTapsByCycle = {};
  final Map<int, int> _flashReactionMsByCycle = {};
  final Set<String> _autoClaimedFlashPrizes = {};
  int _freezeUntilMs = 0;
  int? _lastSeenFlashBall;
  int _lastFlashBallShownAtMs = 0;
  String? _flashTapFeedback;
  bool _flashTapFeedbackIsError = false;

  // Post-Game Corporate Recall Trivia Player State
  int? _playerSelectedOptionIndex;
  int _playerQuestionStartedAtMs = 0;
  int _lastPlayerSeenQuestionIndex = -1;
  bool _playerAnswerSubmitted = false;
  bool? _playerAnswerIsCorrect;
  int? _playerPointsAwarded;
  int? _playerCorrectOptionIndex;
  bool _isSubmittingTriviaAnswer = false;
  bool _isPeekingTicket = false;
  Timer? _peekTicketTimer;
  bool _isPeekingClaims = false;
  Timer? _peekClaimsTimer;
  int _triviaPeekPenalties = 0;
  bool _hasTriggeredTriviaActivation = false;
  bool _hasAttemptedQuestionAdvance = false;
  bool _showPlayerTriviaReview = false;
  Map<int, int>? _playerSelectedAnswers = {};
  Map<int, bool>? _playerAnswerCorrectness = {};
  Map<int, int>? _playerQuestionScores = {};
  Map<int, int>? _playerQuestionTimes = {};
  bool _hasFetchedPastTriviaAnswers = false;

  Map<int, int> get _safePlayerSelectedAnswers {
    _playerSelectedAnswers ??= {};
    return _playerSelectedAnswers!;
  }

  Map<int, bool> get _safePlayerAnswerCorrectness {
    _playerAnswerCorrectness ??= {};
    return _playerAnswerCorrectness!;
  }

  Map<int, int> get _safePlayerQuestionScores {
    _playerQuestionScores ??= {};
    return _playerQuestionScores!;
  }

  Map<int, int> get _safePlayerQuestionTimes {
    _playerQuestionTimes ??= {};
    return _playerQuestionTimes!;
  }

  void _fetchPastTriviaAnswersIfNeeded(String gameId, String? userId) {
    if (_hasFetchedPastTriviaAnswers || userId == null) return;
    _hasFetchedPastTriviaAnswers = true;
    Supabase.instance.client
        .from('MPT_trivia_responses')
        .select('question_index, selected_option_index, is_correct, score_points, response_time_ms')
        .eq('game_id', gameId)
        .eq('user_id', userId)
        .then((rows) {
      if (mounted) {
        for (final row in rows) {
          final q = (row['question_index'] as num?)?.toInt();
          final opt = (row['selected_option_index'] as num?)?.toInt();
          final cor = row['is_correct'] == true;
          final score = (row['score_points'] as num?)?.toInt() ?? 0;
          final timeMs = (row['response_time_ms'] as num?)?.toInt() ?? 0;
          if (q != null && opt != null) {
            _safePlayerSelectedAnswers[q] = opt;
            _safePlayerAnswerCorrectness[q] = cor;
            _safePlayerQuestionScores[q] = score;
            _safePlayerQuestionTimes[q] = timeMs;
          }
        }
        setState(() {});
      }
    }).catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    WakeLockHelper.keepScreenOn();
    _loadSavedMarks();
    _neuroWaveUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final game = ref.read(gameStreamProvider(widget.gameId)).value;
      if (game?.isInProgress == true ||
          game?.isFlashHousie == true ||
          game?.isPostGameTriviaEnabled == true) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _neuroWaveUiTimer?.cancel();
    _finalGraceTimer?.cancel();
    _peekTicketTimer?.cancel();
    _peekClaimsTimer?.cancel();
    WakeLockHelper.release();
    super.dispose();
  }

  Set<int> _recalledForCycle(int cycleIndex) =>
      _flashRecalledByCycle.putIfAbsent(cycleIndex, () => <int>{});

  int _wrongTapsForCycle(int cycleIndex) =>
      _flashWrongTapsByCycle[cycleIndex] ?? 0;

  int _reactionMsForCycle(int cycleIndex) =>
      _flashReactionMsByCycle[cycleIndex] ?? 0;

  int _netScoreForCycle(int cycleIndex) =>
      (_recalledForCycle(cycleIndex).length *
          MptMemoryRoundScore.pointsPerCorrectRecall) -
      (_wrongTapsForCycle(cycleIndex) * MptMemoryRoundScore.penaltyPerWrongTap);

  int get _cumulativeFlashCorrect =>
      _flashRecalledByCycle.values.fold(0, (sum, set) => sum + set.length);

  int get _cumulativeFlashWrong =>
      _flashWrongTapsByCycle.values.fold(0, (sum, count) => sum + count);

  int get _cumulativeFlashNetScore =>
      (_cumulativeFlashCorrect * MptMemoryRoundScore.pointsPerCorrectRecall) -
      (_cumulativeFlashWrong * MptMemoryRoundScore.penaltyPerWrongTap);

  bool get _isFrozen => DateTime.now().millisecondsSinceEpoch < _freezeUntilMs;

  int get _freezeRemainingSeconds =>
      ((_freezeUntilMs - DateTime.now().millisecondsSinceEpoch) / 1000)
          .ceil()
          .clamp(1, 5);

  /// Returns true as soon as the round is declared won, all target cells are recalled,
  /// or all balls in the round pool have been drawn and the final ball window has closed.
  bool _isFlashRoundLocked(
    FlashHousieConfig config,
    FlashHousieCycleSpec cycleSpec,
  ) {
    final game = ref.read(gameStreamProvider(widget.gameId)).value;
    if (game?.isCompleted == true) return true;
    if (config.awardedWinners.containsKey(cycleSpec.prizeKey) ||
        config.awardedWinners.containsKey('FULL_HOUSE')) {
      return true;
    }
    if (cycleSpec.winnerUserId != null && cycleSpec.winnerUserId!.isNotEmpty) {
      return true;
    }
    if (_autoClaimedFlashPrizes.contains(cycleSpec.prizeKey) ||
        _autoClaimedFlashPrizes.contains('FULL_HOUSE')) {
      return true;
    }
    final claims = ref.read(claimsStreamProvider(widget.gameId)).value ?? [];
    final hasApprovedRoundOrFullHouse = claims.any(
      (c) =>
          c.status == 'APPROVED' &&
          (c.prizeType == cycleSpec.prizeKey || c.prizeType == 'FULL_HOUSE'),
    );
    if (hasApprovedRoundOrFullHouse) return true;

    final recalledSet = _recalledForCycle(cycleSpec.cycleIndex);
    if (cycleSpec.trueNumbers.isNotEmpty &&
        recalledSet.length >= cycleSpec.trueNumbers.length) {
      return true;
    }

    if (cycleSpec.isCompleted &&
        _lastFlashBallShownAtMs > 0 &&
        DateTime.now().millisecondsSinceEpoch - _lastFlashBallShownAtMs >=
            2200) {
      return true;
    }
    return false;
  }

  Future<void> _triggerFlashPrizeClaim({
    required String prizeType,
    required List<int> markedNumbers,
    bool isAuto = true,
  }) async {
    if (markedNumbers.isEmpty) return;
    if (!isAuto) {
      setState(() => _isClaiming = true);
    }
    try {
      final res = await ref
          .read(gameplayRepositoryProvider)
          .submitClaim(
            gameId: widget.gameId,
            prizeType: prizeType,
            markedNumbers: markedNumbers,
          );
      if (!mounted) return;
      final status = res['status'] as String? ?? 'UNKNOWN';
      if (status == 'APPROVED') {
        _autoClaimedFlashPrizes.add(prizeType);
        ref.invalidate(claimsStreamProvider(widget.gameId));
        ref.invalidate(gameStreamProvider(widget.gameId));
        ref.invalidate(myRewardsProvider);
        final refCode = res['claim_reference'] as String? ?? 'FLASH-WIN';
        final regList =
            ref.read(registrationsStreamProvider(widget.gameId)).value ?? [];
        final confirmedCount = regList.where((r) => r.isConfirmed).length;
        final totalPlayers = confirmedCount > 0 ? confirmedCount : 1;
        _showWinnerDialog(prizeType, refCode, totalPlayers);
      } else if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['reason'] as String? ?? 'Unable to claim prize yet.',
            ),
            backgroundColor: AppTheme.accentWarning,
          ),
        );
      }
    } catch (e) {
      if (!isAuto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claim error: $e'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
      }
    } finally {
      if (!isAuto && mounted) {
        setState(() => _isClaiming = false);
      }
    }
  }

  Future<void> _handleFlashCellTap({
    required int numVal,
    required FlashHousieCycleSpec cycleSpec,
    required FlashHousieConfig config,
    required MptUser? user,
  }) async {
    if (numVal <= 0) return;
    if (_isFlashRoundLocked(config, cycleSpec)) {
      setState(() {
        _flashTapFeedback =
            '🔒 Round ${cycleSpec.cycleIndex} is already won & locked!';
        _flashTapFeedbackIsError = true;
      });
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _freezeUntilMs) return;

    final neuroState = cycleSpec.computeNeuroWaveState(nowMs);
    if (!neuroState.isCallingReady) return;

    final cycleIdx = cycleSpec.cycleIndex;
    final recalledSet = _recalledForCycle(cycleIdx);
    if (recalledSet.contains(numVal)) return;

    final displayName = (user?.displayName.trim().isNotEmpty == true)
        ? user!.displayName.trim()
        : 'Player';
    final avatar = Formatters.getAvatarEmoji(user?.avatar);

    // Check if the tapped cell matches a number called in this cycle.
    // Re-fetch latest game snapshot if not yet in cached cycleSpec.calledNumbers
    // so 2-second polling latency never causes a false wrong-tap penalty.
    var effectiveCycleSpec = cycleSpec;
    var effectiveCalled = effectiveCycleSpec.calledNumbers.contains(numVal);
    if (!effectiveCalled) {
      try {
        final freshGame = await ref
            .read(gameRepositoryProvider)
            .getGame(widget.gameId);
        final freshCfg = freshGame.flashHousieConfig;
        if (freshGame.isCompleted ||
            freshCfg?.awardedWinners.containsKey(cycleSpec.prizeKey) == true ||
            freshCfg?.awardedWinners.containsKey('FULL_HOUSE') == true) {
          ref.invalidate(gameStreamProvider(widget.gameId));
          if (mounted) {
            setState(() {
              _flashTapFeedback =
                  '🔒 Round ${cycleSpec.cycleIndex} is already won & locked!';
              _flashTapFeedbackIsError = true;
            });
          }
          return;
        }
        final freshSpec = freshCfg?.cycleAt(cycleIdx);
        if (freshSpec != null) {
          effectiveCycleSpec = freshSpec;
          effectiveCalled = freshSpec.calledNumbers.contains(numVal);
        }
      } catch (_) {}
    }

    if (effectiveCalled) {
      final isLatest = effectiveCycleSpec.latestCalledNumber == numVal;
      final deltaMs = (isLatest && _lastFlashBallShownAtMs > 0)
          ? (nowMs - _lastFlashBallShownAtMs).clamp(150, 10000)
          : 3500;

      setState(() {
        recalledSet.add(numVal);
        _markedNumbers.add(numVal);
        _flashReactionMsByCycle[cycleIdx] =
            _reactionMsForCycle(cycleIdx) + deltaMs;
        _flashTapFeedback =
            '✅ Recalled $numVal (+${MptMemoryRoundScore.pointsPerCorrectRecall} pts) in ${(deltaMs / 1000).toStringAsFixed(1)}s! (${recalledSet.length}/${effectiveCycleSpec.trueNumbers.length})';
        _flashTapFeedbackIsError = false;
      });
      _saveMarks();

      await ref
          .read(gameplayRepositoryProvider)
          .upsertMemoryRoundScore(
            gameId: widget.gameId,
            cycleIndex: cycleIdx,
            quadrantLabel: effectiveCycleSpec.label,
            displayName: displayName,
            avatar: avatar,
            correctNumbers: recalledSet.toList(),
            wrongTapCount: _wrongTapsForCycle(cycleIdx),
            totalReactionMs: _reactionMsForCycle(cycleIdx),
            lastRecalledNumber: numVal,
            lastReactionMs: deltaMs,
          );
      ref.invalidate(gameStreamProvider(widget.gameId));

      // Instant auto-crown if player recalled all target numbers in this round!
      if (recalledSet.length >= effectiveCycleSpec.trueNumbers.length &&
          !_autoClaimedFlashPrizes.contains(effectiveCycleSpec.prizeKey)) {
        _autoClaimedFlashPrizes.add(effectiveCycleSpec.prizeKey);
        await _triggerFlashPrizeClaim(
          prizeType: effectiveCycleSpec.prizeKey,
          markedNumbers: recalledSet.toList(),
          isAuto: true,
        );
      }

      // Instant auto-crown Full House if player recalled all target numbers across all rounds!
      if (_cumulativeFlashCorrect >= config.totalTargetNumbersAcrossAllCycles &&
          !_autoClaimedFlashPrizes.contains('FULL_HOUSE')) {
        _autoClaimedFlashPrizes.add('FULL_HOUSE');
        await _triggerFlashPrizeClaim(
          prizeType: 'FULL_HOUSE',
          markedNumbers: _markedNumbers.toList(),
          isAuto: true,
        );
      }
    } else {
      // Wrong cell or tapped during a Challenge (Decoy) Ball -> -3 pts score deduction + 3-second cooldown freeze + +3.0s reaction penalty!
      final newWrongCount = _wrongTapsForCycle(cycleIdx) + 1;
      final penaltyMs = config.freezePenaltySec * 1000;
      setState(() {
        _flashWrongTapsByCycle[cycleIdx] = newWrongCount;
        _flashReactionMsByCycle[cycleIdx] =
            _reactionMsForCycle(cycleIdx) + penaltyMs;
        _freezeUntilMs = nowMs + penaltyMs;
        _flashTapFeedback =
            '❄️ Wrong guess! -${MptMemoryRoundScore.penaltyPerWrongTap} pts & ${config.freezePenaltySec}s Cooldown';
        _flashTapFeedbackIsError = true;
      });

      await ref
          .read(gameplayRepositoryProvider)
          .upsertMemoryRoundScore(
            gameId: widget.gameId,
            cycleIndex: cycleIdx,
            quadrantLabel: effectiveCycleSpec.label,
            displayName: displayName,
            avatar: avatar,
            correctNumbers: recalledSet.toList(),
            wrongTapCount: newWrongCount,
            totalReactionMs: _reactionMsForCycle(cycleIdx),
          );
      ref.invalidate(gameStreamProvider(widget.gameId));
    }
  }

  Future<void> _loadSavedMarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = ref.read(currentUserProvider).value?.id;
      List<String>? saved;
      if (uid != null) {
        saved = prefs.getStringList('mpt_marked_${widget.gameId}_$uid');
      }
      saved ??= prefs.getStringList('mpt_marked_${widget.gameId}');

      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _markedNumbers.addAll(saved!.map(int.parse));
        });
      }
    } catch (_) {}
  }

  void _toggleMark(int number) {
    if (number == 0) return;
    if (_voiceEnabled) {
      TambolaAudioCaller().unlockAudio();
    }
    setState(() {
      if (_markedNumbers.contains(number)) {
        _markedNumbers.remove(number);
      } else {
        _markedNumbers.add(number);
      }
    });
    _saveMarks();
  }

  Future<void> _saveMarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = ref.read(currentUserProvider).value?.id;
      final list = _markedNumbers.map((n) => n.toString()).toList();
      if (uid != null) {
        await prefs.setStringList('mpt_marked_${widget.gameId}_$uid', list);
      }
      await prefs.setStringList('mpt_marked_${widget.gameId}', list);
    } catch (_) {}
  }

  Future<void> _handleClaimPrize({
    required String prizeType,
    required MptTicket ticket,
    required Set<int> calledSet,
  }) async {
    // 1. Strict validation: check for uncalled marked numbers (Bogey)
    var effectiveCalledSet = Set<int>.from(calledSet);
    var uncalled = _markedNumbers
        .where((n) => !effectiveCalledSet.contains(n))
        .toList();
    if (uncalled.isNotEmpty) {
      // Re-fetch latest called numbers from server to avoid false Bogey on stream latency
      try {
        final latestCalls = await ref
            .read(gameplayRepositoryProvider)
            .getCalledNumbers(widget.gameId);
        effectiveCalledSet = latestCalls.map((e) => e.number).toSet();
        uncalled = _markedNumbers
            .where((n) => !effectiveCalledSet.contains(n))
            .toList();
      } catch (_) {}

      if (uncalled.isNotEmpty) {
        _showBogeyDialog(
          'Invalid Claim: You have marked numbers that have not been called yet: ${uncalled.join(', ')}',
        );
        return;
      }
    }

    // 2. Strict validation: check pattern is complete (Item 15)
    final isPatternValid = TambolaTicketHelper.validatePrizePattern(
      ticket.matrix,
      _markedNumbers,
      prizeType,
    );
    if (!isPatternValid) {
      _showIncompletePatternDialog(prizeType);
      return;
    }

    setState(() => _isClaiming = true);
    try {
      final res = await ref
          .read(gameplayRepositoryProvider)
          .submitClaim(
            gameId: widget.gameId,
            prizeType: prizeType,
            markedNumbers: _markedNumbers.toList(),
          );

      if (!mounted) return;
      final status = res['status'] as String? ?? 'UNKNOWN';

      if (status == 'APPROVED') {
        final refCode = res['claim_reference'] as String? ?? 'N/A';
        final regList =
            ref.read(registrationsStreamProvider(widget.gameId)).value ?? [];
        final confirmedCount = regList.where((r) => r.isConfirmed).length;
        final totalPlayers = confirmedCount > 0
            ? confirmedCount
            : (ref
                      .read(gameStreamProvider(widget.gameId))
                      .value
                      ?.fundedCapacity ??
                  1);
        _showWinnerDialog(prizeType, refCode, totalPlayers);
        if (prizeType == 'FULL_HOUSE') {
          try {
            await ref.read(gameplayRepositoryProvider).endGame(widget.gameId);
            ref.invalidate(gameStreamProvider(widget.gameId));
          } catch (_) {}
        }
      } else if (status == 'BOGEY') {
        _showBogeyDialog(res['reason'] as String? ?? 'Invalid claim numbers');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Claim $status: ${res['reason'] ?? ''}'),
            backgroundColor: AppTheme.accentWarning,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Claim error: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  void _showWinnerDialog(String prizeType, String claimRef, int totalPlayers) {
    setState(() => _showCelebration = true);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showCelebration = false);
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.emoji_events,
              color: AppTheme.secondaryColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'WINNER! 🏆',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (totalPlayers > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '1 of $totalPlayers Players',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totalPlayers > 1
                  ? '🎉 Congratulations! You won "${Formatters.formatPrizeName(prizeType)}" competing against $totalPlayers players in this game!'
                  : 'Congratulations! Your claim for "${Formatters.formatPrizeName(prizeType)}" is APPROVED.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Voucher Claim Reference Code:',
              style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor),
              ),
              child: SelectableText(
                claimRef,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.secondaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppTheme.secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prizes must be claimed directly from your game organizer by presenting this voucher reference or QR code. DabHousie is a gameplay platform and does not distribute prizes.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade200,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                Navigator.of(ctx, rootNavigator: true).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentSuccess,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue Playing (Stay on Game)'),
          ),
          TextButton(
            onPressed: () {
              if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                Navigator.of(ctx, rootNavigator: true).pop();
              }
              context.push('/rewards');
            },
            child: const Text('View in Rewards'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleShareBountyToFacebook(MptTicket ticket, MptGame? game) async {
    final gameTitle = game?.name ?? 'DabHousie';
    final proofText = 'Played in $gameTitle with Ticket #${ticket.ticketNumber}! '
        'Marked ${_markedNumbers.length} numbers. Tagging @DabHousie to claim my \$1 Participation Bonus! 🎟️ '
        'Play free with brand prizes at https://www.dabhousie.com #DabHousie #Tambola #Housie';

    await Clipboard.setData(ClipboardData(text: proofText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Facebook proof remark copied to clipboard! Attach your ticket screenshot on Facebook.'),
          backgroundColor: AppTheme.secondaryColor,
          duration: Duration(seconds: 4),
        ),
      );
    }

    final fbUrl = Uri.parse(
      'https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwww.dabhousie.com&quote=${Uri.encodeComponent(proofText)}',
    );
    try {
      await launchUrl(fbUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _handleClaimBounty(MptTicket ticket, MptGame? game) async {
    if (_isClaimingBounty) return;
    setState(() => _isClaimingBounty = true);

    try {
      final res = await ref.read(gameplayRepositoryProvider).submitParticipationBounty(
        widget.gameId,
        _markedNumbers.toList(),
      );

      if (!mounted) return;
      setState(() => _isClaimingBounty = false);

      final code = res['code'] ?? 'DABBOUNTY1';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.redeem_rounded, color: AppTheme.secondaryColor, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Participation Bounty! 🎁',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thank you for actively playing! Here is your \$1.00 DabHousie Credit Voucher:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.secondaryColor),
                ),
                child: Column(
                  children: [
                    const Text(
                      'PROMO CODE',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Colors.white54, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      code,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor, letterSpacing: 2),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Value: \$1.00 USD (5 DabHousie Hosting Credits)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '📌 To complete verification, post your ticket screenshot on Facebook tagging @DabHousie with #DabHousie. Use code DABBOUNTY1 to host your own game for free!',
                style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.facebook, size: 16, color: Color(0xFF1877F2)),
              onPressed: () {
                launchUrl(
                  Uri.parse('https://www.facebook.com/dabhousie'),
                  mode: LaunchMode.externalApplication,
                );
              },
              label: const Text('@DabHousie', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voucher code copied to clipboard!')),
                );
              },
              child: const Text('Copy Code', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryColor, foregroundColor: AppTheme.primaryDark),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _isClaimingBounty = false);
    }
  }

  Widget _buildParticipationBountyCard(
    MptTicket ticket,
    MptGame? game,
    List<MptClaim> claims,
    String? currentUserId, {
    bool isCompact = false,
  }) {
    if (game == null || (!game.isCompleted && game.status != 'COMPLETED')) {
      return const SizedBox.shrink();
    }
    if (_markedNumbers.isEmpty) return const SizedBox.shrink();
    final hasWonAnyPrize = claims.any(
      (c) => c.userId == currentUserId && c.status == 'APPROVED' && c.prizeType != 'PARTICIPATION_BOUNTY',
    );
    if (hasWonAnyPrize) return const SizedBox.shrink();

    final hasClaimedBounty = claims.any(
      (c) => c.userId == currentUserId && c.prizeType == 'PARTICIPATION_BOUNTY',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppTheme.secondaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '\$1 Active Participant Bounty',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '5 DabHousie Hosting Credits',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasClaimedBounty
                      ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                      : AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasClaimedBounty
                        ? AppTheme.accentSuccess
                        : AppTheme.secondaryColor,
                  ),
                ),
                child: Text(
                  hasClaimedBounty ? 'CLAIMED ✅' : 'ELIGIBLE 🎁',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasClaimedBounty
                        ? AppTheme.accentSuccess
                        : AppTheme.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'You marked ${_markedNumbers.length} numbers on Ticket #${ticket.ticketNumber}! Share your ticket snapshot to Facebook tagging @DabHousie to claim 5 free hosting credits (\$1 value).',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFCBD5E1),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _handleShareBountyToFacebook(ticket, game),
                icon: const Icon(Icons.share_rounded, size: 15),
                label: const Text('Share to Facebook 📸'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isClaimingBounty ? null : () => _handleClaimBounty(ticket, game),
                icon: _isClaimingBounty
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondaryColor),
                      )
                    : const Icon(Icons.redeem_rounded, size: 15, color: AppTheme.secondaryColor),
                label: Text(
                  hasClaimedBounty ? 'View Voucher Code' : 'Claim 5 Credits',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.secondaryColor, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showIncompletePatternDialog(String prizeType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.accentWarning, size: 26),
            SizedBox(width: 8),
            Text(
              'Pattern Incomplete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Your marked numbers do not yet complete "${Formatters.formatPrizeName(prizeType)}".\nPlease ensure all required numbers for this pattern have been called and marked on your ticket.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                Navigator.of(ctx, rootNavigator: true).pop();
              }
            },
            child: const Text('OK, Got It'),
          ),
        ],
      ),
    );
  }

  void _showBogeyDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppTheme.accentDanger, size: 28),
            SizedBox(width: 8),
            Text(
              'Bogey Claim ⚠️',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          reason,
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (Navigator.of(ctx, rootNavigator: true).canPop()) {
                Navigator.of(ctx, rootNavigator: true).pop();
              }
            },
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveGame() async {
    final currentGame = ref.read(gameStreamProvider(widget.gameId)).value;
    if (currentGame?.status == 'COMPLETED' ||
        currentGame?.status == 'CANCELLED') {
      context.go('/');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.exit_to_app_rounded,
              color: AppTheme.accentDanger,
              size: 28,
            ),
            SizedBox(width: 8),
            Text('Leave Game?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to leave this game room?\n\nYour ticket and registration will be released, freeing up your seat in the room.',
          style: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay in Game'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave Game'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    WakeLockHelper.release();
    try {
      await ref.read(gameRepositoryProvider).leaveGame(widget.gameId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have left the game room.'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving game: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (prev, next) {
      if (_markedNumbers.isEmpty && next.value != null) {
        _loadSavedMarks();
      }
    });

    final ticketAsync = ref.watch(playerTicketProvider(widget.gameId));
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final registrationsStream = ref.watch(
      registrationsStreamProvider(widget.gameId),
    );
    final currentUserId = ref.watch(currentUserProvider).value?.id;

    final confirmedPlayers =
        registrationsStream.value?.where((r) => r.isConfirmed).toList() ?? [];
    final totalPlayers = confirmedPlayers.isNotEmpty
        ? confirmedPlayers.length
        : (gameStream.value?.fundedCapacity ?? 1);

    // Announce number when new called balls arrive
    ref.listen<AsyncValue<List<MptCalledNumber>>>(
      calledNumbersStreamProvider(widget.gameId),
      (prev, next) {
        final calledNumbers = next.value ?? [];
        if (calledNumbers.isNotEmpty &&
            calledNumbers.length > _lastAnnouncedSeq) {
          _lastAnnouncedSeq = calledNumbers.length;
          final latestNum = calledNumbers.last.number;
          if (_voiceEnabled) {
            TambolaAudioCaller().announceNumber(latestNum);
          }
        }
      },
    );

    if (_voiceEnabled) {
      calledStream.whenData((calledNumbers) {
        if (calledNumbers.isNotEmpty &&
            calledNumbers.length > _lastAnnouncedSeq) {
          _lastAnnouncedSeq = calledNumbers.length;
          final latestNum = calledNumbers.last.number;
          TambolaAudioCaller().announceNumber(latestNum);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              gameStream.value?.name ?? 'DabHousie Ticket',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            if (gameStream.value != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Code: ${gameStream.value!.inviteCode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondaryColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (totalPlayers > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '👥 $totalPlayers',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _voiceEnabled ? Icons.volume_up : Icons.volume_off,
              color: _voiceEnabled ? AppTheme.secondaryColor : Colors.white70,
            ),
            tooltip: _voiceEnabled
                ? 'Voice Calling ON (Tap to Mute)'
                : 'Tap to Unmute Voice Calling',
            onPressed: () async {
              final newState = !_voiceEnabled;
              setState(() => _voiceEnabled = newState);
              TambolaAudioCaller().isMuted = !newState;
              if (newState) {
                if (kIsWeb) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔊 Voice Calling ON! If silent: Turn OFF physical Silent Switch on left side of iPhone (hide orange line) & turn volume up.'),
                      duration: Duration(seconds: 6),
                    ),
                  );
                }
                await TambolaAudioCaller().testVoice();
              } else {
                await TambolaAudioCaller().stop();
              }
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('player_voice_calling_enabled', newState);
              } catch (_) {}
            },
          ),
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Board (Open in New Tab / Window)',
            onPressed: () =>
                LiveDisplayHelper.openInNewWindow(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: 'My Rewards',
            onPressed: () => context.push('/rewards'),
          ),
          if (gameStream.value?.status != 'COMPLETED' &&
              gameStream.value?.status != 'CANCELLED')
            IconButton(
              icon: const Icon(
                Icons.exit_to_app_rounded,
                color: AppTheme.accentDanger,
              ),
              tooltip: 'Quit / Leave Game Room',
              onPressed: _handleLeaveGame,
            ),
        ],
      ),
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.accentDanger,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load your ticket',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please tap retry to fetch your assigned ticket for this room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.refresh(playerTicketProvider(widget.gameId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (ticket) {
          return calledStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (calledNumbers) {
              final currentGame = gameStream.value;
              final flashConfig = currentGame?.flashHousieConfig;
              final activeCycleSpec = flashConfig?.activeCycleSpec;

              // Hydrate per-round recall sets from saved _markedNumbers across reloads
              if (flashConfig != null && _markedNumbers.isNotEmpty) {
                for (final c in flashConfig.cycles) {
                  final recalledSet = _recalledForCycle(c.cycleIndex);
                  final calledInCycle = c.calledNumbers.toSet();
                  for (final numVal in c.trueNumbers) {
                    if (_markedNumbers.contains(numVal) &&
                        calledInCycle.contains(numVal)) {
                      recalledSet.add(numVal);
                    }
                  }
                }
              }

              // Track reaction timer & voice caller when a new FlashHousie™ ball is drawn
              if (activeCycleSpec != null) {
                final latestFlashBall = activeCycleSpec.latestCalledNumber;
                if (latestFlashBall != null &&
                    latestFlashBall != _lastSeenFlashBall) {
                  _lastSeenFlashBall = latestFlashBall;
                  _lastFlashBallShownAtMs =
                      DateTime.now().millisecondsSinceEpoch;
                  if (_voiceEnabled) {
                    TambolaAudioCaller().announceNumber(latestFlashBall);
                  }
                }
              }

              final latestCalled = activeCycleSpec != null
                  ? activeCycleSpec.latestCalledNumber
                  : (calledNumbers.isNotEmpty
                        ? calledNumbers.last.number
                        : null);
              final latestCalledAt = calledNumbers.isNotEmpty
                  ? calledNumbers.last.calledAt
                  : null;
              final calledSet = activeCycleSpec != null
                  ? activeCycleSpec.calledNumbers.toSet()
                  : calledNumbers.map((e) => e.number).toSet();
              final totalCalledCount = activeCycleSpec != null
                  ? activeCycleSpec.calledNumbers.length
                  : calledNumbers.length;
              final poolTotalCount = activeCycleSpec != null
                  ? activeCycleSpec.drawPool.length
                  : 90;

              final is90NumbersDone =
                  flashConfig == null && calledNumbers.length >= 90;

              // Trigger 20-second final claim window on player side if all 90 numbers called
              if (is90NumbersDone && !_hasStartedFinalGrace) {
                _hasStartedFinalGrace = true;
                _finalGraceSecondsLeft = 20;
                _finalGraceTimer?.cancel();
                _finalGraceTimer =
                    Timer.periodic(const Duration(seconds: 1), (timer) {
                  if (!mounted) {
                    timer.cancel();
                    return;
                  }
                  if (_finalGraceSecondsLeft > 1) {
                    setState(() {
                      _finalGraceSecondsLeft--;
                    });
                  } else {
                    timer.cancel();
                    setState(() {
                      _finalGraceSecondsLeft = 0;
                    });
                  }
                });
              }

              final isInFinalGracePeriod =
                  is90NumbersDone && _finalGraceSecondsLeft > 0;

              final isGameEnded =
                  currentGame?.status == 'CANCELLED' ||
                  (!isInFinalGracePeriod &&
                      (currentGame?.isCompleted == true ||
                          currentGame?.status == 'COMPLETED' ||
                          (is90NumbersDone &&
                              _hasStartedFinalGrace &&
                              _finalGraceSecondsLeft <= 0)));
              final hasApprovedWinners =
                  (claimsStream.value ?? const <MptClaim>[]).any(
                    (c) => c.status == 'APPROVED',
                  ) ||
                  (flashConfig != null &&
                      flashConfig.cycles.any((c) => c.winnerUserId != null));
              final isCancelledOrNoWinners =
                  currentGame?.status == 'CANCELLED' ||
                  (isGameEnded && !hasApprovedWinners);
              final isGameActive =
                  (currentGame?.status == 'IN_PROGRESS' ||
                      calledNumbers.isNotEmpty ||
                      activeCycleSpec?.startedAtMs != null) &&
                  !isGameEnded &&
                  currentGame?.status != 'CANCELLED';
              final activePrizes =
                  currentGame?.prizesConfig ??
                  [
                    'EARLY_FIVE',
                    'TOP_LINE',
                    'MIDDLE_LINE',
                    'BOTTOM_LINE',
                    'FOUR_CORNERS',
                    'FULL_HOUSE',
                  ];
              final currentUser = ref.watch(currentUserProvider).value;
              final triviaRound = currentGame?.isPostGameTriviaEnabled == true
                  ? ref.watch(gameTriviaRoundStreamProvider(currentGame?.id ?? '')).value
                  : null;
              final isTriviaActive = currentGame?.isPostGameTriviaEnabled == true &&
                  isGameEnded &&
                  triviaRound != null &&
                  (triviaRound.isActive || triviaRound.isCountdown);
              final isTriviaCompleted = triviaRound?.isCompleted == true;

              return CelebrationOverlay(
                isCelebrating: _showCelebration && !isCancelledOrNoWinners,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final orientation = MediaQuery.of(ctx).orientation;
                    final isLandscape =
                        orientation == Orientation.landscape ||
                        (constraints.maxWidth > 560 &&
                            constraints.maxWidth >
                                constraints.maxHeight * 1.15);

                    if (isLandscape) {
                      // ========================================================
                      // MOBILE LANDSCAPE 2-COLUMN LAYOUT
                      // Left: Player Banner, Latest Call/Ended, Expanded Ticket Matrix
                      // Right: Recent Calls, Prize Claims Panel, Quit Game
                      // NOTE: Strict ad policy: NO ad banner in landscape mode.
                      // ========================================================
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column (Ticket & Current Ball) - Maximize width for 9-column ticket
                            Expanded(
                              flex: 7,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildLobbyWaitingNotice(context, currentGame),
                                    _buildCorporateTriviaPreGameNotice(currentGame),
                                    if (isTriviaActive) ...[
                                      // 1. Pink Banner at top during Trivia
                                      _buildLatestNumberBanner(
                                        latestCalled,
                                        totalCalledCount,
                                        poolTotalCount: poolTotalCount,
                                        cycleLabel: activeCycleSpec?.label,
                                        totalPlayers: totalPlayers,
                                        isGameEnded: isGameEnded,
                                        isCancelledOrNoWinners: isCancelledOrNoWinners,
                                        context: context,
                                        isCompact: true,
                                        latestCalledAt: latestCalledAt,
                                        isTriviaActive: true,
                                        isTriviaCompleted: isTriviaCompleted,
                                        callIntervalSeconds: currentGame?.callIntervalSeconds ?? 15,
                                      ),
                                      const SizedBox(height: 8),

                                      // 2. Player Identity Banner (Player count hidden)
                                      _buildPlayerIdentityBanner(
                                        currentUser,
                                        ticket,
                                        game: currentGame,
                                        totalPlayers: totalPlayers,
                                        isCompact: true,
                                        isGameEnded: isGameEnded || currentGame?.status == 'CANCELLED',
                                        hidePlayerCount: true,
                                      ),
                                    ] else ...[
                                      if (isInFinalGracePeriod) ...[
                                        _buildFinalGraceBanner(),
                                        const SizedBox(height: 10),
                                      ],
                                      _buildPlayerIdentityBanner(
                                        currentUser,
                                        ticket,
                                        game: currentGame,
                                        totalPlayers: totalPlayers,
                                        isCompact: true,
                                        isGameEnded:
                                            isGameEnded ||
                                            currentGame?.status == 'CANCELLED',
                                      ),
                                      const SizedBox(height: 8),
                                      _buildLatestNumberBanner(
                                        latestCalled,
                                        totalCalledCount,
                                        poolTotalCount: poolTotalCount,
                                        cycleLabel: activeCycleSpec?.label,
                                        totalPlayers: totalPlayers,
                                        isGameEnded: isGameEnded,
                                        isCancelledOrNoWinners:
                                            isCancelledOrNoWinners,
                                        context: context,
                                        isCompact: true,
                                        latestCalledAt: latestCalledAt,
                                        isTriviaActive: false,
                                        isTriviaCompleted: isTriviaCompleted,
                                        callIntervalSeconds: currentGame?.callIntervalSeconds ?? 15,
                                      ),
                                    ],
                                    if (flashConfig != null &&
                                        activeCycleSpec != null) ...[
                                      const SizedBox(height: 8),
                                      _buildNeuroWaveStatusBanner(
                                        flashConfig,
                                        activeCycleSpec,
                                        isCompact: true,
                                      ),
                                    ],
                                    _buildParticipationBountyCard(
                                      ticket,
                                      currentGame,
                                      claimsStream.value ?? const [],
                                      currentUserId,
                                      isCompact: true,
                                    ),
                                    if (currentGame?.isPostGameTriviaEnabled == true && isGameEnded) ...[
                                      const SizedBox(height: 10),
                                      _buildPlayerTriviaSection(currentGame, currentUser, isCompact: true),
                                    ],
                                    const SizedBox(height: 8),
                                    if (isTriviaActive && !_isPeekingTicket)
                                      _buildConcealedTicketRecallCard(onPeek: _handlePeekTicket)
                                    else ...[
                                      if (isTriviaActive && _isPeekingTicket) ...[
                                        _buildPeekingActiveBanner(isTicket: true),
                                        const SizedBox(height: 6),
                                      ],
                                      _buildTicketMatrix(
                                        ticket,
                                        calledSet,
                                        isGameEnded: isGameEnded,
                                        cellHeight: 52,
                                        flashConfig: flashConfig,
                                        currentUser: currentUser,
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Right Column (Recent Numbers & Prize Claims) - Tiny claim buttons
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (isTriviaActive && !_isPeekingClaims)
                                      _buildConcealedWinnersRecallCard(onPeek: _handlePeekClaims)
                                    else ...[
                                      if (isTriviaActive && _isPeekingClaims) ...[
                                        _buildPeekingActiveBanner(isTicket: false),
                                        const SizedBox(height: 6),
                                      ],
                                      if (activeCycleSpec != null &&
                                          activeCycleSpec
                                              .calledNumbers
                                              .isNotEmpty) ...[
                                        _buildRecentCallsFromInts(
                                          activeCycleSpec.calledNumbers,
                                        ),
                                        const SizedBox(height: 10),
                                      ] else if (calledNumbers.isNotEmpty) ...[
                                        _buildRecentCallsBar(calledNumbers),
                                        const SizedBox(height: 10),
                                      ],
                                      claimsStream.when(
                                        loading: () => _buildPrizeClaimsSection(
                                          activePrizes,
                                          {},
                                          currentUserId,
                                          ticket,
                                          calledSet,
                                          isGameEnded: isGameEnded,
                                          isCompact: true,
                                          flashConfig: flashConfig,
                                        ),
                                        error: (_, __) =>
                                            _buildPrizeClaimsSection(
                                              activePrizes,
                                              {},
                                              currentUserId,
                                              ticket,
                                              calledSet,
                                              isGameEnded: isGameEnded,
                                              isCompact: true,
                                              flashConfig: flashConfig,
                                            ),
                                        data: (claims) {
                                          final approvedClaims =
                                              <String, MptClaim>{};
                                          for (final c in claims) {
                                            if (c.status == 'APPROVED') {
                                              approvedClaims[c.prizeType] = c;
                                            }
                                          }
                                          return _buildPrizeClaimsSection(
                                            activePrizes,
                                            approvedClaims,
                                            currentUserId,
                                            ticket,
                                            calledSet,
                                            isGameEnded: isGameEnded,
                                            isCompact: true,
                                            flashConfig: flashConfig,
                                          );
                                        },
                                      ),
                                    ],
                                    if (!isGameEnded &&
                                        currentGame?.status != 'CANCELLED') ...[
                                      const SizedBox(height: 14),
                                      OutlinedButton.icon(
                                        onPressed: _handleLeaveGame,
                                        icon: const Icon(
                                          Icons.exit_to_app_rounded,
                                          color: AppTheme.accentDanger,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Leave Game Room',
                                          style: TextStyle(
                                            color: AppTheme.accentDanger,
                                            fontSize: 12,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Color(0xFFEF4444),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // ========================================================
                    // PORTRAIT / NARROW 1-COLUMN LAYOUT
                    // ========================================================
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildLobbyWaitingNotice(context, currentGame),
                          _buildCorporateTriviaPreGameNotice(currentGame),
                          if (isTriviaActive) ...[
                            // 1. Pink Banner at top during Trivia
                            _buildLatestNumberBanner(
                              latestCalled,
                              totalCalledCount,
                              poolTotalCount: poolTotalCount,
                              cycleLabel: activeCycleSpec?.label,
                              totalPlayers: totalPlayers,
                              isGameEnded: isGameEnded,
                              isCancelledOrNoWinners: isCancelledOrNoWinners,
                              context: context,
                              latestCalledAt: latestCalledAt,
                              isTriviaActive: true,
                              isTriviaCompleted: isTriviaCompleted,
                              callIntervalSeconds: currentGame?.callIntervalSeconds ?? 15,
                            ),
                            const SizedBox(height: 10),

                            // 2. Player Identity Banner (Player count hidden)
                            _buildPlayerIdentityBanner(
                              currentUser,
                              ticket,
                              game: currentGame,
                              totalPlayers: totalPlayers,
                              isGameEnded:
                                  isGameEnded ||
                                  currentGame?.status == 'CANCELLED',
                              hidePlayerCount: true,
                            ),
                          ] else ...[
                            if (isInFinalGracePeriod) ...[
                              _buildFinalGraceBanner(),
                              const SizedBox(height: 10),
                            ],
                            // Player Identity & Ticket Number Card
                            _buildPlayerIdentityBanner(
                              currentUser,
                              ticket,
                              game: currentGame,
                              totalPlayers: totalPlayers,
                              isGameEnded:
                                  isGameEnded ||
                                  currentGame?.status == 'CANCELLED',
                            ),
                            const SizedBox(height: 10),

                            // Latest Called Ball / Game Concluded Banner
                            _buildLatestNumberBanner(
                              latestCalled,
                              totalCalledCount,
                              poolTotalCount: poolTotalCount,
                              cycleLabel: activeCycleSpec?.label,
                              totalPlayers: totalPlayers,
                              isGameEnded: isGameEnded,
                              isCancelledOrNoWinners: isCancelledOrNoWinners,
                              context: context,
                              latestCalledAt: latestCalledAt,
                              isTriviaActive: false,
                              isTriviaCompleted: isTriviaCompleted,
                              callIntervalSeconds: currentGame?.callIntervalSeconds ?? 15,
                            ),
                          ],
                          const SizedBox(height: 10),

                          if (flashConfig != null &&
                              activeCycleSpec != null) ...[
                            _buildNeuroWaveStatusBanner(
                              flashConfig,
                              activeCycleSpec,
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Recent Calls List
                          if (isTriviaActive && _isPeekingClaims) ...[
                            _buildPeekingActiveBanner(isTicket: false),
                            const SizedBox(height: 8),
                            if (activeCycleSpec != null && activeCycleSpec.calledNumbers.isNotEmpty) ...[
                              _buildRecentCallsFromInts(activeCycleSpec.calledNumbers),
                              const SizedBox(height: 12),
                            ] else if (calledNumbers.isNotEmpty) ...[
                              _buildRecentCallsBar(calledNumbers),
                              const SizedBox(height: 14),
                            ],
                          ] else if (!isTriviaActive) ...[
                            if (activeCycleSpec != null &&
                                activeCycleSpec.calledNumbers.isNotEmpty &&
                                !isGameEnded) ...[
                              _buildRecentCallsFromInts(
                                activeCycleSpec.calledNumbers,
                              ),
                              const SizedBox(height: 12),
                            ] else if (calledNumbers.isNotEmpty &&
                                !isGameEnded) ...[
                              _buildRecentCallsBar(calledNumbers),
                              const SizedBox(height: 14),
                            ],
                          ],

                          _buildParticipationBountyCard(
                            ticket,
                            currentGame,
                            claimsStream.value ?? const [],
                            currentUserId,
                          ),
                          const SizedBox(height: 12),

                          if (currentGame?.isPostGameTriviaEnabled == true && isGameEnded) ...[
                            const SizedBox(height: 10),
                            _buildPlayerTriviaSection(currentGame, currentUser),
                          ],
                          // Interactive 3x9 Ticket (Concealed if trivia is active)
                          if (isTriviaActive && !_isPeekingTicket)
                            _buildConcealedTicketRecallCard(onPeek: _handlePeekTicket)
                          else ...[
                            if (isTriviaActive && _isPeekingTicket) ...[
                              _buildPeekingActiveBanner(isTicket: true),
                              const SizedBox(height: 8),
                            ],
                            _buildTicketMatrix(
                              ticket,
                              calledSet,
                              isGameEnded: isGameEnded,
                              flashConfig: flashConfig,
                              currentUser: currentUser,
                            ),
                          ],
                          const SizedBox(height: 20),

                          // Prize Claims Section (Concealed if trivia is active)
                          if (isTriviaActive && !_isPeekingClaims)
                            _buildConcealedWinnersRecallCard(onPeek: _handlePeekClaims)
                          else ...[
                            claimsStream.when(
                              loading: () => _buildPrizeClaimsSection(
                                activePrizes,
                                {},
                                currentUserId,
                                ticket,
                                calledSet,
                                isGameEnded: isGameEnded,
                                flashConfig: flashConfig,
                              ),
                              error: (_, __) => _buildPrizeClaimsSection(
                                activePrizes,
                                {},
                                currentUserId,
                                ticket,
                                calledSet,
                                isGameEnded: isGameEnded,
                                flashConfig: flashConfig,
                              ),
                              data: (claims) {
                                final approvedClaims = <String, MptClaim>{};
                                for (final c in claims) {
                                  if (c.status == 'APPROVED') {
                                    approvedClaims[c.prizeType] = c;
                                  }
                                }
                                return _buildPrizeClaimsSection(
                                  activePrizes,
                                  approvedClaims,
                                  currentUserId,
                                  ticket,
                                  calledSet,
                                  isGameEnded: isGameEnded,
                                  flashConfig: flashConfig,
                                );
                              },
                            ),
                          ],
                          if (!isGameEnded &&
                              currentGame?.status != 'CANCELLED') ...[
                            const SizedBox(height: 24),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: _handleLeaveGame,
                                icon: const Icon(
                                  Icons.exit_to_app_rounded,
                                  color: AppTheme.accentDanger,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Quit / Leave Game Room',
                                  style: TextStyle(
                                    color: AppTheme.accentDanger,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (!isLandscape && !isGameActive) ...[
                            const SizedBox(height: 18),
                            const AdBannerSlot(
                              slotId: 'DAB-PLAYER-GAME-BOTTOM',
                              title: 'Sponsored Partner',
                              subtitle:
                                  'Enjoying DabHousie? Host your next family or corporate event!',
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFinalGraceBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB45309), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            color: Color(0xFFFEF3C7),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'All 90 Numbers Called!',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_finalGraceSecondsLeft}s Left',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFDE68A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Final claim window is open! Mark your last numbers and claim your remaining lines or Full House now.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFFEF3C7),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyWaitingNotice(BuildContext context, MptGame? game) {
    if (game == null || !game.isOpen) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.meeting_room_rounded, color: AppTheme.secondaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  game.scheduledAt != null
                      ? '⏳ GAME SCHEDULED: ${Formatters.formatShortDate(game.scheduledAt!)}'
                      : '⏳ WAITING FOR ORGANIZER TO START',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Viewing ticket preview. Live balls will call automatically here once game starts.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => context.push('/game-status/${widget.gameId}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.primaryLight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Lobby', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCorporateTriviaPreGameNotice(MptGame? game) {
    if (game == null || !game.isPostGameTriviaEnabled) return const SizedBox.shrink();
    if (game.isCompleted || game.status == 'COMPLETED') return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF818CF8).withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              color: Color(0xFF818CF8),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '🧠 POST-GAME RECALL TRIVIA ACTIVE',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC7D2FE),
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 14),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  'Pay close attention to draw milestones, winner sequence, and numbers called! An automated observation recall challenge runs immediately after the game for bonus podium recognition.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerTriviaSection(
    MptGame? game,
    MptUser? user, {
    bool isCompact = false,
  }) {
    if (game == null || !game.isPostGameTriviaEnabled) return const SizedBox.shrink();
    if (!game.isCompleted && game.status != 'COMPLETED') return const SizedBox.shrink();

    final triviaRoundAsync = ref.watch(gameTriviaRoundStreamProvider(game.id));
    final triviaWinnersAsync = ref.watch(gameTriviaWinnersStreamProvider(game.id));
    final round = triviaRoundAsync.value;
    final winners = triviaWinnersAsync.value ?? const [];

    if (round == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
            ),
            SizedBox(width: 12),
            Text(
              'Preparing DabHousie Recall Trivia Challenge...',
              style: TextStyle(fontSize: 12, color: Color(0xFFC7D2FE), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (round.isCountdown) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF818CF8), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF4F46E5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🧠 GET READY FOR TRIVIA!',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Trivia starts in moments on this screen. Speed & accuracy count!',
                    style: TextStyle(fontSize: 11, color: Color(0xFFC7D2FE)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (ctx) {
              int secondsRemaining = 0;
              if (round.startsAt != null) {
                secondsRemaining = round.startsAt!.difference(DateTime.now()).inSeconds;
                if (secondsRemaining < 0) secondsRemaining = 0;
              }
              if (secondsRemaining <= 0 && !_hasTriggeredTriviaActivation) {
                _hasTriggeredTriviaActivation = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(gameplayRepositoryProvider).launchTriviaActive(game.id).catchError((_) {});
                });
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  secondsRemaining > 0 ? 'STARTING IN ${secondsRemaining}s' : 'STARTING NOW...',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              );
            }),
          ],
        ),
      );
    }

    if (round.isActive) {
      if (round.questions.isEmpty || round.currentQuestionIndex >= round.questions.length) {
        return const SizedBox.shrink();
      }
      final currentQ = round.questions[round.currentQuestionIndex];

      // Reset selection state when moving to a new question index
      if (_lastPlayerSeenQuestionIndex != round.currentQuestionIndex) {
        _lastPlayerSeenQuestionIndex = round.currentQuestionIndex;
        _playerSelectedOptionIndex = null;
        _playerAnswerSubmitted = false;
        _playerAnswerIsCorrect = null;
        _playerPointsAwarded = null;
        _playerCorrectOptionIndex = null;
        _playerQuestionStartedAtMs = DateTime.now().millisecondsSinceEpoch;
        _hasAttemptedQuestionAdvance = false;
      }

      final qSecondsAllotted = round.secondsPerQuestion > 0 ? round.secondsPerQuestion : 15;
      final qElapsedSecs = ((DateTime.now().millisecondsSinceEpoch - _playerQuestionStartedAtMs) / 1000).floor();
      final qSecsLeft = (qSecondsAllotted - qElapsedSecs).clamp(0, qSecondsAllotted);

      // Autonomous question advance fallback if host / TV screen is not advancing
      if (qSecsLeft <= 0 && !_hasAttemptedQuestionAdvance) {
        _hasAttemptedQuestionAdvance = true;
        final nextIdx = round.currentQuestionIndex + 1;
        final isLast = nextIdx >= round.questions.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(gameplayRepositoryProvider).advanceTriviaQuestion(
            gameId: game.id,
            nextIndex: nextIdx,
            isLast: isLast,
          ).catchError((_) {});
        });
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6366F1),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header: Question count + Category + Live Score indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    currentQ.categoryName.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC7D2FE)),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Q${round.currentQuestionIndex + 1} of ${round.questions.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: qSecsLeft <= 5 ? AppTheme.accentDanger.withValues(alpha: 0.25) : const Color(0xFF38BDF8).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: qSecsLeft <= 5 ? AppTheme.accentDanger : const Color(0xFF38BDF8),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 11,
                            color: qSecsLeft <= 5 ? AppTheme.accentDanger : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${qSecsLeft}s',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: qSecsLeft <= 5 ? AppTheme.accentDanger : const Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_playerAnswerSubmitted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (_playerAnswerIsCorrect == true)
                          ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                          : AppTheme.accentDanger.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _playerAnswerIsCorrect == true
                          ? '+${_playerPointsAwarded ?? 500} pts${_triviaPeekPenalties > 0 ? ' (-$_triviaPeekPenalties peek)' : ''}'
                          : '0 pts',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _playerAnswerIsCorrect == true ? AppTheme.accentSuccess : AppTheme.accentDanger,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Question Text
            Text(
              currentQ.question,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // 4 Fast-Recall Option Tiles (2x2 Grid on desktop / wide screens, stacked on small mobile)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 380;
                final optWidgets = currentQ.options.asMap().entries.map((optEntry) {
                  final optIdx = optEntry.key;
                  final optText = optEntry.value;
                  return _buildPlayerOptionButton(
                    index: optIdx,
                    optionText: optText,
                    currentQ: currentQ,
                    gameId: game.id,
                    user: user,
                  );
                }).toList();

                if (isWide && optWidgets.length >= 2) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: optWidgets[0]),
                          const SizedBox(width: 10),
                          Expanded(child: optWidgets[1]),
                        ],
                      ),
                      if (optWidgets.length > 2) ...[
                        Row(
                          children: [
                            Expanded(child: optWidgets[2]),
                            const SizedBox(width: 10),
                            if (optWidgets.length > 3)
                              Expanded(child: optWidgets[3])
                            else
                              const Spacer(),
                          ],
                        ),
                      ],
                    ],
                  );
                } else {
                  return Column(children: optWidgets);
                }
              },
            ),

            if (_playerAnswerSubmitted) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: (_playerAnswerIsCorrect == true)
                      ? AppTheme.accentSuccess.withValues(alpha: 0.15)
                      : AppTheme.accentDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _playerAnswerIsCorrect == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: _playerAnswerIsCorrect == true ? AppTheme.accentSuccess : AppTheme.accentDanger,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _playerAnswerIsCorrect == true
                            ? 'Spot on! Speed bonus added. Next question coming...'
                            : 'Incorrect. Answer: ${currentQ.correctAnswer}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _playerAnswerIsCorrect == true ? AppTheme.accentSuccess : AppTheme.accentDanger,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // COMPLETED: Either Question & Answer Review OR Podium Standings
    if (_showPlayerTriviaReview) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.quiz_rounded, color: Color(0xFF818CF8), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Trivia Questions and Answers',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFC7D2FE), letterSpacing: 0.5),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showPlayerTriviaReview = false),
                  icon: const Icon(Icons.workspace_premium_rounded, size: 15, color: Color(0xFFFBBF24)),
                  label: const Text('Podium 🏆', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            Builder(builder: (ctx) {
              _fetchPastTriviaAnswersIfNeeded(game.id, user?.id);
              return const SizedBox.shrink();
            }),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isTwoColumn = constraints.maxWidth > 580;
                final cards = round.questions.asMap().entries.map((entry) {
                  final qIdx = entry.key;
                  final q = entry.value;
                  final playerPickedIdx = _safePlayerSelectedAnswers[qIdx];
                  final playerWasCorrect = _safePlayerAnswerCorrectness[qIdx] == true;
                  final playerScore = _safePlayerQuestionScores[qIdx];
                  final playerTimeMs = _safePlayerQuestionTimes[qIdx];
                  return _buildTriviaReviewQuestionCard(
                    qIdx: qIdx,
                    q: q,
                    playerPickedIdx: playerPickedIdx,
                    playerWasCorrect: playerWasCorrect,
                    playerScore: playerScore,
                    playerTimeMs: playerTimeMs,
                  );
                }).toList();

                if (isTwoColumn && cards.length >= 2) {
                  final rows = <Widget>[];
                  for (int i = 0; i < cards.length; i += 2) {
                    final left = cards[i];
                    final right = (i + 1 < cards.length) ? cards[i + 1] : null;
                    rows.add(
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 12),
                            Expanded(child: right ?? const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(children: rows);
                } else {
                  return Column(
                    children: cards
                        .map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: c,
                            ))
                        .toList(),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _showPlayerTriviaReview = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back to Official Podium 🏆'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // COMPLETED: Podium Standings
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 24),
              SizedBox(width: 8),
              Text(
                'TRIVIA RECALL PODIUM',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24), letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (winners.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Calculating official trivia standings...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ),
            )
          else ...[
            ...winners.map((w) {
              final isMe = w.userId == user?.id;
              Color badgeColor;
              String emoji;
              switch (w.rank) {
                case 1:
                  badgeColor = const Color(0xFFFBBF24); // Gold
                  emoji = '🥇';
                  break;
                case 2:
                  badgeColor = const Color(0xFFCBD5E1); // Silver
                  emoji = '🥈';
                  break;
                case 3:
                  badgeColor = const Color(0xFFF97316); // Bronze
                  emoji = '🥉';
                  break;
                case 4:
                  badgeColor = const Color(0xFFA78BFA); // Purple / Star
                  emoji = '🎖️';
                  break;
                case 5:
                  badgeColor = const Color(0xFF38BDF8); // Sky Blue
                  emoji = '🌟';
                  break;
                default:
                  badgeColor = const Color(0xFF94A3B8); // Slate
                  emoji = '#${w.rank}';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF6366F1).withValues(alpha: 0.25) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMe ? const Color(0xFF818CF8) : const Color(0xFF334155),
                    width: isMe ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${w.userName} (You)' : w.userName,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isMe ? Colors.white : const Color(0xFFCBD5E1),
                            ),
                          ),
                          Text(
                            w.title,
                            style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${w.totalScore} pts',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: badgeColor),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showPlayerTriviaReview = true),
                icon: const Icon(Icons.quiz_rounded, size: 16, color: Color(0xFF818CF8)),
                label: const Text(
                  'Review Questions & Your Answers 📝',
                  style: TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerOptionButton({
    required int index,
    required String optionText,
    required MptTriviaQuestion currentQ,
    required String gameId,
    required MptUser? user,
  }) {
    Color baseColor;
    String symbol;
    switch (index) {
      case 0:
        baseColor = const Color(0xFFEF4444);
        symbol = '▲';
        break;
      case 1:
        baseColor = const Color(0xFF3B82F6);
        symbol = '◆';
        break;
      case 2:
        baseColor = const Color(0xFFF59E0B);
        symbol = '●';
        break;
      default:
        baseColor = const Color(0xFF10B981);
        symbol = '■';
        break;
    }

    final isSelected = _playerSelectedOptionIndex == index;
    final isSubmitted = _playerAnswerSubmitted;
    final isCorrectOption = _playerCorrectOptionIndex == index;

    Color tileColor = baseColor.withValues(alpha: 0.2);
    Color borderColor = baseColor.withValues(alpha: 0.6);

    if (isSubmitted) {
      if (isSelected) {
        tileColor = (_playerAnswerIsCorrect == true)
            ? AppTheme.accentSuccess.withValues(alpha: 0.35)
            : AppTheme.accentDanger.withValues(alpha: 0.35);
        borderColor = (_playerAnswerIsCorrect == true) ? AppTheme.accentSuccess : AppTheme.accentDanger;
      } else if (isCorrectOption) {
        tileColor = AppTheme.accentSuccess.withValues(alpha: 0.25);
        borderColor = AppTheme.accentSuccess;
      } else {
        tileColor = Colors.white.withValues(alpha: 0.04);
        borderColor = Colors.white.withValues(alpha: 0.1);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: 'TRIVIA_OPTION_$index: $optionText',
        button: true,
        enabled: !isSubmitted && !_isSubmittingTriviaAnswer,
        child: InkWell(
        onTap: (isSubmitted || _isSubmittingTriviaAnswer)
            ? null
            : () async {
                setState(() {
                  _playerSelectedOptionIndex = index;
                  _isSubmittingTriviaAnswer = true;
                });
                final responseTimeMs = DateTime.now().millisecondsSinceEpoch -
                    (_playerQuestionStartedAtMs > 0 ? _playerQuestionStartedAtMs : DateTime.now().millisecondsSinceEpoch);

                try {
                  final res = await ref.read(gameplayRepositoryProvider).submitTriviaAnswer(
                    gameId: gameId,
                    userId: user?.id ?? 'guest',
                    userName: user?.displayName ?? 'Player',
                    userAvatar: user?.avatar,
                    questionIndex: _lastPlayerSeenQuestionIndex,
                    selectedOptionIndex: index,
                    responseTimeMs: responseTimeMs < 100 ? 100 : responseTimeMs,
                  );
                  if (mounted) {
                    final rawPoints = (res['points_awarded'] as num?)?.toInt() ?? 0;
                    final netPoints = rawPoints > 0 ? (rawPoints - _triviaPeekPenalties).clamp(0, 10000) : 0;
                    final isCorrect = res['is_correct'] == true;
                    _safePlayerSelectedAnswers[_lastPlayerSeenQuestionIndex] = index;
                    _safePlayerAnswerCorrectness[_lastPlayerSeenQuestionIndex] = isCorrect;
                    _safePlayerQuestionScores[_lastPlayerSeenQuestionIndex] = netPoints;
                    _safePlayerQuestionTimes[_lastPlayerSeenQuestionIndex] = responseTimeMs;
                    setState(() {
                      _playerAnswerSubmitted = true;
                      _playerAnswerIsCorrect = isCorrect;
                      _playerPointsAwarded = netPoints;
                      _playerCorrectOptionIndex = (res['correct_index'] as num?)?.toInt() ?? currentQ.correctIndex;
                      _isSubmittingTriviaAnswer = false;
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    final rawPoints = index == currentQ.correctIndex ? 500 : 0;
                    final netPoints = rawPoints > 0 ? (rawPoints - _triviaPeekPenalties).clamp(0, 10000) : 0;
                    final isCorrect = index == currentQ.correctIndex;
                    _safePlayerSelectedAnswers[_lastPlayerSeenQuestionIndex] = index;
                    _safePlayerAnswerCorrectness[_lastPlayerSeenQuestionIndex] = isCorrect;
                    _safePlayerQuestionScores[_lastPlayerSeenQuestionIndex] = netPoints;
                    _safePlayerQuestionTimes[_lastPlayerSeenQuestionIndex] = responseTimeMs;
                    setState(() {
                      _isSubmittingTriviaAnswer = false;
                      _playerAnswerSubmitted = true;
                      _playerAnswerIsCorrect = isCorrect;
                      _playerPointsAwarded = netPoints;
                      _playerCorrectOptionIndex = currentQ.correctIndex;
                    });
                  }
                }
              },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isSelected ? 2.0 : 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  optionText,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  _playerAnswerIsCorrect == true ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded,
                  color: borderColor,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildTriviaReviewQuestionCard({
    required int qIdx,
    required MptTriviaQuestion q,
    required int? playerPickedIdx,
    required bool playerWasCorrect,
    int? playerScore,
    int? playerTimeMs,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: playerWasCorrect
              ? AppTheme.accentSuccess.withValues(alpha: 0.5)
              : (playerPickedIdx != null ? AppTheme.accentDanger.withValues(alpha: 0.4) : const Color(0xFF334155)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Q${qIdx + 1} • ${q.categoryName.toUpperCase()}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
              ),
              if (playerPickedIdx != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: playerWasCorrect
                        ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                        : AppTheme.accentDanger.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: playerWasCorrect
                          ? AppTheme.accentSuccess.withValues(alpha: 0.5)
                          : AppTheme.accentDanger.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        playerWasCorrect ? '✅ Correct' : '❌ Missed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: playerWasCorrect ? AppTheme.accentSuccess : AppTheme.accentDanger,
                        ),
                      ),
                      if (playerScore != null && playerTimeMs != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          playerWasCorrect
                              ? '+$playerScore pts (${(playerTimeMs / 1000).toStringAsFixed(1)}s)'
                              : '0 pts (${(playerTimeMs / 1000).toStringAsFixed(1)}s)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: playerWasCorrect ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                const Text('⏳ No response', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            q.question,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          ...q.options.asMap().entries.map((optEntry) {
            final optIdx = optEntry.key;
            final optText = optEntry.value;
            final isCorrect = optIdx == q.correctIndex;
            final isPlayerChoice = optIdx == playerPickedIdx;

            Color tileBg = Colors.white.withValues(alpha: 0.03);
            Color borderColor = Colors.white.withValues(alpha: 0.08);
            String badge = '';

            if (isCorrect && isPlayerChoice) {
              tileBg = AppTheme.accentSuccess.withValues(alpha: 0.25);
              borderColor = AppTheme.accentSuccess;
              badge = '🎯 Your Pick (Correct!)';
            } else if (isCorrect) {
              tileBg = AppTheme.accentSuccess.withValues(alpha: 0.18);
              borderColor = AppTheme.accentSuccess.withValues(alpha: 0.8);
              badge = '✅ Correct Answer';
            } else if (isPlayerChoice) {
              tileBg = AppTheme.accentDanger.withValues(alpha: 0.2);
              borderColor = AppTheme.accentDanger;
              badge = '❌ Your Pick';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor, width: (isCorrect || isPlayerChoice) ? 1.4 : 1.0),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      optText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isCorrect || isPlayerChoice) ? FontWeight.bold : FontWeight.normal,
                        color: isCorrect ? AppTheme.accentSuccess : (isPlayerChoice ? AppTheme.accentDanger : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                  if (badge.isNotEmpty)
                    Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isCorrect ? AppTheme.accentSuccess : AppTheme.accentDanger,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _handlePeekTicket() {
    setState(() {
      _isPeekingTicket = true;
      _triviaPeekPenalties += 150;
    });
    _peekTicketTimer?.cancel();
    _peekTicketTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isPeekingTicket = false;
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Ticket visible for 5s! -150 pts memory penalty deducted.'),
        backgroundColor: AppTheme.accentDanger,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _handlePeekClaims() {
    setState(() {
      _isPeekingClaims = true;
      _triviaPeekPenalties += 200;
    });
    _peekClaimsTimer?.cancel();
    _peekClaimsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isPeekingClaims = false;
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Claims & Recent Calls visible for 5s! -200 pts memory penalty deducted.'),
        backgroundColor: Color(0xFFF59E0B),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Widget _buildPeekingActiveBanner({required bool isTicket}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.accentDanger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accentDanger),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger, size: 16),
          const SizedBox(width: 6),
          Text(
            isTicket
                ? '⚠️ PEEKING ACTIVE (-150 PTS) • Re-locking in 5s'
                : '⚠️ PEEKING ACTIVE (-200 PTS) • Re-locking in 5s',
            style: const TextStyle(
              color: AppTheme.accentDanger,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConcealedTicketRecallCard({required VoidCallback onPeek}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_clock_rounded, color: Color(0xFF818CF8), size: 36),
          const SizedBox(height: 8),
          const Text(
            '🔒 TICKET NUMBERS CONCEALED',
            style: TextStyle(
              color: Color(0xFFC7D2FE),
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Memory Recall in progress! Rely on your memory to answer recall questions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onPeek,
            icon: const Icon(Icons.visibility_rounded, size: 16),
            label: const Text('Peek at Ticket (-150 pts penalty)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.9),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConcealedWinnersRecallCard({required VoidCallback onPeek}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.visibility_off_rounded, color: Color(0xFFFBBF24), size: 36),
          const SizedBox(height: 8),
          const Text(
            '🔒 CLAIMS & DRAWN BALLS CONCEALED',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Recall who claimed which prize and recent balls from memory!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onPeek,
            icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
            label: const Text('Peek at Claims & Balls (-200 pts penalty)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerIdentityBanner(
    MptUser? user,
    MptTicket ticket, {
    MptGame? game,
    int totalPlayers = 1,
    bool isCompact = false,
    bool isGameEnded = false,
    bool hidePlayerCount = false,
  }) {
    final emoji = Formatters.getAvatarEmoji(user?.avatar);
    final name =
        (user?.displayName != null && user!.displayName.trim().isNotEmpty)
        ? user.displayName
        : 'Player';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 30 : 38,
            height: isCompact ? 30 : 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryLight.withOpacity(0.5)),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: TextStyle(fontSize: isCompact ? 16 : 20)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: isCompact ? 13 : 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  game != null
                      ? '${game.name} • Code: ${game.inviteCode}'
                      : 'Playing Live Game',
                  style: TextStyle(
                    fontSize: isCompact ? 9.5 : 11,
                    color: AppTheme.secondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.secondaryColor.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              game?.isFlashHousie == true
                  ? '⚡ ${game!.flashHousieConfig!.activeCycleSpec.label}'
                  : 'Ticket #${ticket.ticketNumber}',
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.groups_rounded,
                  size: 13,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 4),
                Text(
                  hidePlayerCount ? '? Players' : '$totalPlayers Players',
                  style: TextStyle(
                    fontSize: isCompact ? 10.5 : 11.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ],
            ),
          ),
          if (!isGameEnded) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(
                Icons.exit_to_app_rounded,
                color: AppTheme.accentDanger,
                size: 20,
              ),
              tooltip: 'Quit Game Room',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _handleLeaveGame,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLatestNumberBanner(
    int? latestNumber,
    int totalCalled, {
    int poolTotalCount = 90,
    String? cycleLabel,
    int totalPlayers = 1,
    bool isGameEnded = false,
    bool isCancelledOrNoWinners = false,
    BuildContext? context,
    bool isCompact = false,
    DateTime? latestCalledAt,
    bool isTriviaActive = false,
    bool isTriviaCompleted = false,
    int callIntervalSeconds = 15,
  }) {
    if (isGameEnded) {
      final accentColor = isCancelledOrNoWinners
          ? const Color(0xFFF87171)
          : (isTriviaActive ? const Color(0xFF818CF8) : AppTheme.secondaryColor);
      return Container(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isCancelledOrNoWinners
                ? const [Color(0xFF331B26), Color(0xFF1E1B2E)]
                : (isTriviaActive
                    ? const [Color(0xFF312E81), Color(0xFF1E1B4B)]
                    : const [Color(0xFF4338CA), Color(0xFF1E1B4B)]),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCancelledOrNoWinners
                      ? Icons.cancel_outlined
                      : (isTriviaActive ? Icons.psychology_rounded : Icons.celebration),
                  color: accentColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isCancelledOrNoWinners
                        ? 'GAME CANCELLED / ENDED WITHOUT WINNERS 🚫'
                        : (isTriviaActive
                            ? 'CLASSIC GAME COMPLETED • TRIVIA FOLLOWS 🧠'
                            : 'GAME CONCLUDED 🎉'),
                    style: TextStyle(
                      fontSize: isCompact ? 14 : 17,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                      letterSpacing: 0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isCancelledOrNoWinners
                  ? 'This game was cancelled or ended early without any prize winners.'
                  : (isTriviaActive
                      ? 'Classic game completed. Corporate Recall Trivia follows below! Put your memory to the test.'
                      : (totalCalled >= 90
                          ? 'All 90 numbers called across $totalPlayers players! Prize claiming is now finalized.'
                          : 'Game concluded across $totalPlayers players! Check your rewards below.')),
              style: TextStyle(
                fontSize: isCompact ? 11.5 : 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isTriviaActive || isTriviaCompleted) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (context != null && !isCancelledOrNoWinners)
                    ElevatedButton.icon(
                      onPressed: () => context.push('/rewards'),
                      icon: const Icon(Icons.emoji_events, size: 16),
                      label: const Text('View My Rewards 🏆'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: AppTheme.primaryDark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (context != null)
                    OutlinedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.home_rounded, size: 16),
                      label: const Text('Return Home'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 20,
        vertical: isCompact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cycleLabel != null
                    ? '⚡ $cycleLabel • CURRENT CALL'
                    : 'CURRENT CALL',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 2),
              Semantics(
                label: latestNumber != null
                    ? 'CURRENT_CALLED_NUMBER_$latestNumber'
                    : 'CURRENT_CALLED_NUMBER_READY',
                child: Text(
                  latestNumber != null ? '$latestNumber' : 'READY',
                  style: TextStyle(
                    fontSize: isCompact ? 32 : 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ),
              if (!isGameEnded && latestNumber != null && latestCalledAt != null) ...[
                Builder(
                  builder: (_) {
                    final elapsed = DateTime.now().difference(latestCalledAt).inSeconds;
                    final secsLeft = (callIntervalSeconds - elapsed).clamp(0, callIntervalSeconds);
                    return Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 11,
                            color: Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            secsLeft > 0
                                ? 'Next in ~${secsLeft}s'
                                : 'Drawing next ball...',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF38BDF8),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 14,
              vertical: isCompact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$totalCalled / $poolTotalCount',
                  style: TextStyle(
                    fontSize: isCompact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  cycleLabel != null ? 'Round Pool' : 'Called',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the NeuroWave™ Spotlight digital countdown timer, column wave indicator, 3s cooldown freeze,
  /// and live player memory recall telemetry without a vertical progress bar.
  Widget _buildNeuroWaveStatusBanner(
    FlashHousieConfig config,
    FlashHousieCycleSpec cycleSpec, {
    bool isCompact = false,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final neuroState = cycleSpec.computeNeuroWaveState(nowMs);
    final isFrozen = nowMs < _freezeUntilMs;
    final isRoundLocked = _isFlashRoundLocked(config, cycleSpec);
    final recalledCount = _recalledForCycle(cycleSpec.cycleIndex).length;
    final targetCount = cycleSpec.trueNumbers.length;
    final wrongCount = _wrongTapsForCycle(cycleSpec.cycleIndex);
    final roundNetScore = _netScoreForCycle(cycleSpec.cycleIndex);
    final totalNetScore = _cumulativeFlashNetScore;
    final neuroSecsLeft = (neuroState.remainingMsInPhase / 1000).ceil();
    final digitalSecs = isFrozen ? _freezeRemainingSeconds : neuroSecsLeft;
    final formattedDigital =
        '00:${digitalSecs.clamp(0, 99).toString().padLeft(2, '0')}';

    Color borderColor = AppTheme.secondaryColor.withValues(alpha: 0.65);
    Color bgColor = AppTheme.darkCard;
    if (isFrozen) {
      borderColor = AppTheme.accentDanger;
      bgColor = AppTheme.accentDanger.withValues(alpha: 0.14);
    } else if (neuroState.phase == NeuroWavePhase.columnWave) {
      borderColor = AppTheme.secondaryColor;
      bgColor = AppTheme.secondaryColor.withValues(alpha: 0.12);
    } else if (neuroState.phase == NeuroWavePhase.callingActive) {
      borderColor = AppTheme.accentSuccess.withValues(alpha: 0.7);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Round ${config.currentCycle}/${config.totalCycles} • ${cycleSpec.label}',
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFrozen
                      ? '❄️ Cooldown Freeze — Wait before tapping!'
                      : isRoundLocked
                      ? '🏆 Round ${config.currentCycle} Won & Locked!'
                      : neuroState.statusLabel,
                  style: TextStyle(
                    fontSize: isCompact ? 13 : 14.5,
                    fontWeight: FontWeight.w800,
                    color: isFrozen
                        ? const Color(0xFFFCA5A5)
                        : isRoundLocked
                        ? AppTheme.secondaryColor
                        : Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFrozen || neuroState.isRevealing) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFrozen
                          ? AppTheme.accentDanger
                          : AppTheme.secondaryColor,
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isFrozen
                                    ? AppTheme.accentDanger
                                    : AppTheme.secondaryColor)
                                .withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFrozen ? Icons.ac_unit_rounded : Icons.timer_outlined,
                        size: isCompact ? 18 : 20,
                        color: isFrozen
                            ? const Color(0xFFFCA5A5)
                            : AppTheme.secondaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formattedDigital,
                        style: TextStyle(
                          fontSize: isCompact ? 20 : 24,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                          color: isFrozen
                              ? const Color(0xFFFCA5A5)
                              : AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildTelemetryPill(
                '⭐ Score: $roundNetScore pts (Total: $totalNetScore pts)',
                AppTheme.secondaryColor,
              ),
              _buildTelemetryPill(
                '🎯 Recalls: $recalledCount/$targetCount (+${recalledCount * MptMemoryRoundScore.pointsPerCorrectRecall})',
                AppTheme.accentSuccess,
              ),
              _buildTelemetryPill(
                '❄️ Wrong Taps: $wrongCount (${wrongCount > 0 ? "-${wrongCount * MptMemoryRoundScore.penaltyPerWrongTap} pts" : "0 pts"})',
                wrongCount > 0
                    ? AppTheme.accentWarning
                    : const Color(0xFF94A3B8),
              ),
              if (_flashTapFeedback != null)
                Text(
                  _flashTapFeedback!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _flashTapFeedbackIsError
                        ? const Color(0xFFFCA5A5)
                        : AppTheme.accentSuccess,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRecentCallsFromInts(List<int> called) {
    final recent = called.reversed.toList();
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Text(
              'ROUND BALLS (${called.length}):',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, idx) {
                final numVal = recent[idx];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: idx == 0
                        ? AppTheme.secondaryColor
                        : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Text(
                    '$numVal',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: idx == 0 ? Colors.black : Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCallsBar(List<MptCalledNumber> called) {
    final recent = called.reversed.take(6).toList();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final item = recent[idx];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: idx == 0 ? AppTheme.secondaryColor : AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Text(
              '${item.number}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: idx == 0 ? Colors.black : Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTicketMatrix(
    MptTicket ticket,
    Set<int> calledSet, {
    bool isGameEnded = false,
    double cellHeight = 52,
    FlashHousieConfig? flashConfig,
    MptUser? currentUser,
  }) {
    final activeSpec = flashConfig?.activeCycleSpec;
    final matrixToRender = activeSpec != null
        ? activeSpec.ticketMatrix
        : ticket.matrix;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: activeSpec != null
              ? AppTheme.secondaryColor
              : AppTheme.primaryLight,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    activeSpec != null
                        ? '⚡ ${flashConfig!.modeDisplayName.toUpperCase()} • ${activeSpec.label}'
                        : 'DABHOUSIE TICKET #${ticket.ticketNumber}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: activeSpec != null
                          ? AppTheme.secondaryColor
                          : AppTheme.primaryLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  activeSpec != null
                      ? '${_recalledForCycle(activeSpec.cycleIndex).length} / ${activeSpec.trueNumbers.length} Recalled • ⭐ ${_netScoreForCycle(activeSpec.cycleIndex)} pts'
                      : (isGameEnded
                            ? '${_markedNumbers.length} / 15 Marked (Final)'
                            : '${_markedNumbers.length} / 15 Marked'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 14),
            if (activeSpec != null) ...[
              // Quadrant Header Bar (Q1: Cols 1-3 | Q2: Cols 4-6 | Q3: Cols 7-9)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (int q = 1; q <= 3; q++)
                      Expanded(
                        flex: 3,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: activeSpec.activeQuadrants.contains(q)
                                ? AppTheme.secondaryColor.withValues(
                                    alpha: 0.18,
                                  )
                                : const Color(0xFF1E2235),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: activeSpec.activeQuadrants.contains(q)
                                  ? AppTheme.secondaryColor
                                  : const Color(0xFF2E334D),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            activeSpec.activeQuadrants.contains(q)
                                ? '⚡ Q$q (${(q - 1) * 30 + 1}–${q * 30}) ACTIVE'
                                : '🔒 Q$q (${(q - 1) * 30 + 1}–${q * 30})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: activeSpec.activeQuadrants.contains(q)
                                  ? AppTheme.secondaryColor
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            for (int r = 0; r < 3; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    for (int c = 0; c < 9; c++)
                      Expanded(
                        child: activeSpec != null
                            ? _buildFlashTicketCell(
                                numVal: matrixToRender[r][c],
                                col: c,
                                cycleSpec: activeSpec,
                                config: flashConfig!,
                                currentUser: currentUser,
                                isGameEnded: isGameEnded,
                                height: cellHeight,
                              )
                            : _buildTicketCell(
                                matrixToRender[r][c],
                                calledSet,
                                isGameEnded: isGameEnded,
                                height: cellHeight,
                              ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Renders a cell on the preserved 3x9 ticket grid during FlashHousie™ 5/10/15:
  /// - Inactive quadrants are dimmed (`opacity: 0.30`) and locked.
  /// - Active quadrant cells unmask ONLY when `neuroState.visibleColumn == col` during `NeuroWavePhase.columnWave`,
  ///   or after the player recalls them during `NeuroWavePhase.callingActive`.
  Widget _buildFlashTicketCell({
    required int numVal,
    required int col,
    required FlashHousieCycleSpec cycleSpec,
    required FlashHousieConfig config,
    required MptUser? currentUser,
    required bool isGameEnded,
    required double height,
  }) {
    final quadrant = (col ~/ 3) + 1;
    final isActiveQuad = cycleSpec.activeQuadrants.contains(quadrant);

    if (numVal == 0) {
      return Opacity(
        opacity: isActiveQuad ? 1.0 : 0.30,
        child: Container(
          height: height,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppTheme.darkBackground.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActiveQuad
                  ? const Color(0xFF2E334D)
                  : Colors.transparent,
              width: 0.6,
            ),
          ),
        ),
      );
    }

    if (!isActiveQuad) {
      // Inactive quadrant cell: dimmed & locked to preserve 3x9 spatial memory
      return Opacity(
        opacity: 0.28,
        child: Container(
          height: height,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF161929),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF252A40)),
          ),
          child: const Center(
            child: Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      );
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final neuroState = cycleSpec.computeNeuroWaveState(nowMs);
    final isRecalled = _recalledForCycle(cycleSpec.cycleIndex).contains(numVal);
    final isRoundLocked = _isFlashRoundLocked(config, cycleSpec);
    final isSpotlightVisible =
        neuroState.phase == NeuroWavePhase.columnWave &&
        neuroState.visibleColumn == col;
    final showTrueNumber = isRecalled || isSpotlightVisible;
    final canTap =
        neuroState.isCallingReady &&
        !isRecalled &&
        !isGameEnded &&
        !isRoundLocked &&
        !_isFrozen;

    Color bgColor = AppTheme.darkSurface;
    Color borderColor = const Color(0xFF3B4163);
    Color textColor = Colors.white;

    if (isRecalled) {
      bgColor = AppTheme.accentSuccess;
      borderColor = AppTheme.accentSuccess;
      textColor = Colors.white;
    } else if (isSpotlightVisible) {
      bgColor = AppTheme.secondaryColor.withValues(alpha: 0.26);
      borderColor = AppTheme.secondaryColor;
      textColor = AppTheme.secondaryColor;
    } else if (isRoundLocked || isGameEnded) {
      bgColor = const Color(0xFF161929);
      borderColor = const Color(0xFF2E334D);
      textColor = const Color(0xFF64748B);
    } else if (neuroState.isCallingReady) {
      bgColor = const Color(0xFF1E243B);
      borderColor = AppTheme.primaryLight.withValues(alpha: 0.75);
      textColor = const Color(0xFF93C5FD);
    }

    return Semantics(
      label: showTrueNumber ? 'Ticket number $numVal' : 'Masked memory cell',
      button: true,
      enabled: canTap,
      onTap: canTap
          ? () => _handleFlashCellTap(
              numVal: numVal,
              cycleSpec: cycleSpec,
              config: config,
              user: currentUser,
            )
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: canTap
              ? () => _handleFlashCellTap(
                  numVal: numVal,
                  cycleSpec: cycleSpec,
                  config: config,
                  user: currentUser,
                )
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: borderColor,
                width: (isRecalled || isSpotlightVisible) ? 2.0 : 1.2,
              ),
              boxShadow: isSpotlightVisible
                  ? [
                      BoxShadow(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                showTrueNumber ? '$numVal' : '?',
                style: TextStyle(
                  fontSize: height >= 52 ? 20 : 18,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTicketCell(
    int numVal,
    Set<int> calledSet, {
    bool isGameEnded = false,
    double height = 52,
  }) {
    if (numVal == 0) {
      return Container(
        height: height,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppTheme.darkBackground.withOpacity(0.6),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final isMarked = _markedNumbers.contains(numVal);
    Color bgColor = isMarked ? AppTheme.accentSuccess : AppTheme.darkSurface;
    Color textColor = Colors.white;

    return Semantics(
      label: 'Ticket number $numVal',
      value: isMarked ? 'marked' : 'unmarked',
      button: true,
      enabled: !isGameEnded,
      onTap: isGameEnded ? null : () => _toggleMark(numVal),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: isGameEnded ? null : () => _toggleMark(numVal),
          child: Container(
            height: height,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isMarked
                    ? AppTheme.accentSuccess
                    : const Color(0xFF3B4163),
                width: isMarked ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$numVal',
                style: TextStyle(
                  fontSize: height >= 52 ? 20 : 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _formatPrizeGiftDetail(MptGame? game, String prizeKey) {
    if (game == null) return null;
    final raw = game.prizeGiftsConfig[prizeKey];
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      return s.isNotEmpty ? s : null;
    }
    if (raw is Map) {
      final title = (raw['title'] ?? raw['brand_name'] ?? '').toString().trim();
      final val = (raw['prize_value'] as num?)?.toDouble() ?? 0.0;
      final sym =
          (raw['currency_symbol'] ??
                  game.prizeGiftsConfig['_currency_symbol'] ??
                  '₹')
              .toString()
              .trim();
      final valStr = val > 0
          ? '$sym${val == val.roundToDouble() ? val.toInt() : val.toStringAsFixed(2)}'
          : '';
      if (title.isNotEmpty && valStr.isNotEmpty) {
        return '$title ($valStr)';
      }
      if (title.isNotEmpty) return title;
      if (valStr.isNotEmpty) return 'Prize Value: $valStr';
    }
    return null;
  }

  Widget _buildPrizeClaimsSection(
    List<String> activePrizes,
    Map<String, MptClaim> approvedClaims,
    String? currentUserId,
    MptTicket ticket,
    Set<int> calledSet, {
    bool isGameEnded = false,
    bool isCompact = false,
    FlashHousieConfig? flashConfig,
  }) {
    final currentGame = ref.watch(gameStreamProvider(widget.gameId)).value;
    final registrations =
        ref.watch(registrationsStreamProvider(widget.gameId)).value ?? [];
    final regMap = {for (final r in registrations) r.userId: r};

    // Auto-claim for FlashHousie™ 5 / 10 / 15:
    // 1. If host crowned this player in FlashHousieConfig.awardedWinners, OR
    // 2. If player recalled all target numbers in a round (5/5), OR
    // 3. If all 8/8 balls of a round have been called and player has recalled numbers in that round!
    if (flashConfig != null && currentUserId != null && !isGameEnded) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final entry in flashConfig.awardedWinners.entries) {
        final prizeKey = entry.key;
        final winnerUid = entry.value;
        if (winnerUid == currentUserId &&
            approvedClaims[prizeKey] == null &&
            !_autoClaimedFlashPrizes.contains(prizeKey)) {
          _autoClaimedFlashPrizes.add(prizeKey);
          Future.microtask(
            () => _triggerFlashPrizeClaim(
              prizeType: prizeKey,
              markedNumbers: _markedNumbers.toList(),
              isAuto: true,
            ),
          );
        }
      }

      for (final c in flashConfig.cycles) {
        final prizeKey = c.prizeKey;
        final recalledSet = _recalledForCycle(c.cycleIndex);
        final isFullRecall =
            c.trueNumbers.isNotEmpty &&
            recalledSet.length >= c.trueNumbers.length;
        final isRoundPoolDone =
            c.isCompleted &&
            recalledSet.isNotEmpty &&
            (_lastFlashBallShownAtMs == 0 ||
                nowMs - _lastFlashBallShownAtMs >= 2000);
        if ((isFullRecall || isRoundPoolDone) &&
            approvedClaims[prizeKey] == null &&
            flashConfig.awardedWinners[prizeKey] == null &&
            !_autoClaimedFlashPrizes.contains(prizeKey)) {
          _autoClaimedFlashPrizes.add(prizeKey);
          Future.microtask(
            () => _triggerFlashPrizeClaim(
              prizeType: prizeKey,
              markedNumbers: recalledSet.toList(),
              isAuto: true,
            ),
          );
        }
      }

      if (activePrizes.contains('FULL_HOUSE') &&
          approvedClaims['FULL_HOUSE'] == null &&
          flashConfig.awardedWinners['FULL_HOUSE'] == null &&
          !_autoClaimedFlashPrizes.contains('FULL_HOUSE') &&
          _cumulativeFlashCorrect > 0) {
        final totalTargets = flashConfig.totalTargetNumbersAcrossAllCycles;
        final isAllRecalled = _cumulativeFlashCorrect >= totalTargets;
        final isFinalRoundDone =
            flashConfig.cycles.isNotEmpty &&
            flashConfig.cycles.last.isCompleted &&
            (_lastFlashBallShownAtMs == 0 ||
                nowMs - _lastFlashBallShownAtMs >= 2200);
        if (isAllRecalled || isFinalRoundDone) {
          _autoClaimedFlashPrizes.add('FULL_HOUSE');
          Future.microtask(
            () => _triggerFlashPrizeClaim(
              prizeType: 'FULL_HOUSE',
              markedNumbers: _markedNumbers.toList(),
              isAuto: true,
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                flashConfig != null
                    ? '🏆 Prizes & Winners (Round & Full House)'
                    : '🏆 Prizes & Winners',
                style: TextStyle(
                  fontSize: isCompact ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isGameEnded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3B4163)),
                ),
                child: const Text(
                  'CONCLUDED',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA0AEC0),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isGameEnded
              ? 'Game is over. Final prize winners and scores are shown below.'
              : (flashConfig != null
                    ? 'Winners are crowned automatically by highest memory recall & fastest reaction speed!'
                    : 'Tap when completed. Server will validate your ticket.'),
          style: TextStyle(
            fontSize: isCompact ? 11 : 12.5,
            color: const Color(0xFFCBD5E1),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: isCompact ? 6 : 10,
          mainAxisSpacing: isCompact ? 6 : 10,
          childAspectRatio: isCompact ? 2.35 : 2.05,
          children: activePrizes.map((prize) {
            final approvedClaim = approvedClaims[prize];
            final flashWinnerUid = flashConfig?.awardedWinners[prize];
            final flashWinnerName = flashConfig?.awardedWinnerNames[prize];
            final isApproved = approvedClaim != null || flashWinnerUid != null;
            final winnerUid = approvedClaim?.userId ?? flashWinnerUid;
            final isWonByMe =
                isApproved && winnerUid != null && winnerUid == currentUserId;
            final giftDetail = _formatPrizeGiftDetail(currentGame, prize);

            // Build score summary if FlashHousie prize
            String? scoreSummary =
                flashConfig?.awardedWinnerScoreSummaries[prize];
            if ((scoreSummary == null || scoreSummary.isEmpty) &&
                approvedClaim?.rejectionReason != null &&
                approvedClaim!.rejectionReason!.trim().startsWith('✓')) {
              scoreSummary = approvedClaim.rejectionReason!.trim();
            }
            if ((scoreSummary == null || scoreSummary.isEmpty) &&
                flashConfig != null &&
                prize.startsWith('ROUND_')) {
              final rNum = int.tryParse(prize.replaceFirst('ROUND_', ''));
              if (rNum != null) {
                final cSpec = flashConfig.cycleAt(rNum);
                if (cSpec != null && cSpec.winnerCorrectCount != null) {
                  final sec = ((cSpec.winnerReactionMs ?? 0) / 1000)
                      .toStringAsFixed(1);
                  scoreSummary =
                      '✓ ${cSpec.winnerCorrectCount}/${cSpec.trueNumbers.length} Recalled • ⚡ ${sec}s';
                } else if (isWonByMe && cSpec != null) {
                  final myRecalled = _recalledForCycle(rNum).length;
                  final sec = (_reactionMsForCycle(rNum) / 1000)
                      .toStringAsFixed(1);
                  if (myRecalled > 0) {
                    scoreSummary =
                        '✓ $myRecalled/${cSpec.trueNumbers.length} Recalled • ⚡ ${sec}s';
                  }
                }
              }
            }

            if (isApproved) {
              final playerReg = winnerUid != null ? regMap[winnerUid] : null;
              final displayName = (playerReg?.displayName.isNotEmpty == true)
                  ? playerReg!.displayName
                  : (flashWinnerName != null && flashWinnerName.isNotEmpty)
                  ? flashWinnerName
                  : (approvedClaim?.userName != null &&
                        approvedClaim!.userName != 'Player')
                  ? approvedClaim.userName!
                  : 'Player';

              return ElevatedButton(
                onPressed: null, // Disabled
                style: ElevatedButton.styleFrom(
                  backgroundColor: isWonByMe
                      ? AppTheme.accentSuccess.withValues(alpha: 0.22)
                      : Colors.black26,
                  disabledBackgroundColor: isWonByMe
                      ? AppTheme.accentSuccess.withValues(alpha: 0.25)
                      : const Color(0xFF222639),
                  disabledForegroundColor: isWonByMe
                      ? AppTheme.accentSuccess
                      : Colors.white,
                  side: BorderSide(
                    color: isWonByMe
                        ? AppTheme.accentSuccess
                        : AppTheme.secondaryColor.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 6 : 10,
                    vertical: isCompact ? 4 : 6,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: TextStyle(
                        fontSize: isCompact ? 12.5 : 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWonByMe
                          ? (registrations.length > 1
                                ? '🏆 Won by You! (1 of ${registrations.length})'
                                : '🏆 Won by You!')
                          : '👑 Winner: $displayName',
                      style: TextStyle(
                        fontSize: isCompact ? 11.5 : 13,
                        fontWeight: FontWeight.w800,
                        color: isWonByMe
                            ? AppTheme.accentSuccess
                            : AppTheme.secondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (scoreSummary != null && scoreSummary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          scoreSummary,
                          style: TextStyle(
                            fontSize: isCompact ? 10 : 11.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF38BDF8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (giftDetail != null && giftDetail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '🎁 $giftDetail',
                          style: TextStyle(
                            fontSize: isCompact ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFBBF24),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            }

            if (isGameEnded) {
              return ElevatedButton(
                onPressed: null, // Disabled when game ended
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF1E2235),
                  disabledForegroundColor: const Color(0xFF94A3B8),
                  side: const BorderSide(color: Color(0xFF2E334D)),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 6 : 10,
                    vertical: isCompact ? 4 : 6,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: TextStyle(
                        fontSize: isCompact ? 12.5 : 14.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Unclaimed',
                      style: TextStyle(
                        fontSize: isCompact ? 10.5 : 12,
                        color: const Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (giftDetail != null && giftDetail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '🎁 $giftDetail',
                          style: TextStyle(
                            fontSize: isCompact ? 10 : 11,
                            color: const Color(0xFFFBBF24),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            }

            if (flashConfig != null) {
              bool canClaimNow = false;
              String flashSubtitle = '⚡ Live Memory Leaderboard';
              List<int> claimNums = _markedNumbers.toList();

              if (prize.startsWith('ROUND_')) {
                final rNum =
                    int.tryParse(prize.replaceFirst('ROUND_', '')) ?? 1;
                final cSpec = flashConfig.cycleAt(rNum);
                final recalledInRound = _recalledForCycle(rNum);
                claimNums = recalledInRound.toList();
                if (cSpec != null) {
                  if (recalledInRound.length >= cSpec.trueNumbers.length ||
                      (cSpec.isCompleted && recalledInRound.isNotEmpty)) {
                    canClaimNow = true;
                    flashSubtitle =
                        '🏆 ${recalledInRound.length}/${cSpec.trueNumbers.length} Recalled • Tap to Claim!';
                  } else if (rNum == flashConfig.currentCycle) {
                    flashSubtitle =
                        '🎯 ${recalledInRound.length}/${cSpec.trueNumbers.length} Recalled • Auto-Crowns';
                  } else if (rNum > flashConfig.currentCycle) {
                    flashSubtitle = '⏳ Unlocks in Round $rNum';
                  }
                }
              } else if (prize == 'FULL_HOUSE' ||
                  prize == 'SECOND_FULL_HOUSE') {
                final totalTargets =
                    flashConfig.totalTargetNumbersAcrossAllCycles;
                final isLastDone =
                    flashConfig.cycles.isNotEmpty &&
                    flashConfig.cycles.last.isCompleted;
                if (_cumulativeFlashCorrect >= totalTargets ||
                    (isLastDone && _cumulativeFlashCorrect > 0)) {
                  canClaimNow = true;
                  flashSubtitle =
                      '🏆 $_cumulativeFlashCorrect/$totalTargets Recalled • Tap to Claim!';
                } else {
                  flashSubtitle =
                      '🎯 $_cumulativeFlashCorrect/$totalTargets Total Recalls';
                }
              }

              return ElevatedButton(
                onPressed: (canClaimNow && !_isClaiming)
                    ? () => _triggerFlashPrizeClaim(
                        prizeType: prize,
                        markedNumbers: claimNums,
                        isAuto: false,
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canClaimNow
                      ? AppTheme.accentSuccess.withValues(alpha: 0.22)
                      : AppTheme.darkSurface,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.darkSurface,
                  disabledForegroundColor: Colors.white,
                  side: BorderSide(
                    color: canClaimNow
                        ? AppTheme.accentSuccess
                        : AppTheme.secondaryColor.withValues(alpha: 0.55),
                    width: canClaimNow ? 1.6 : 1.3,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 6 : 10,
                    vertical: isCompact ? 4 : 6,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: TextStyle(
                        fontSize: isCompact ? 12.5 : 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      flashSubtitle,
                      style: TextStyle(
                        fontSize: isCompact ? 10.5 : 12,
                        color: canClaimNow
                            ? AppTheme.accentSuccess
                            : AppTheme.secondaryColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (giftDetail != null && giftDetail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '🎁 $giftDetail',
                          style: TextStyle(
                            fontSize: isCompact ? 10 : 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFBBF24),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            }

            return ElevatedButton(
              onPressed: _isClaiming
                  ? null
                  : () => _handleClaimPrize(
                      prizeType: prize,
                      ticket: ticket,
                      calledSet: calledSet,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.darkSurface,
                foregroundColor: Colors.white,
                side: const BorderSide(
                  color: AppTheme.primaryColor,
                  width: 1.3,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 6 : 10,
                  vertical: isCompact ? 4 : 6,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    Formatters.formatPrizeName(prize),
                    style: TextStyle(
                      fontSize: isCompact ? 12.5 : 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (giftDetail != null && giftDetail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '🎁 $giftDetail',
                      style: TextStyle(
                        fontSize: isCompact ? 10 : 11.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFFBBF24),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
