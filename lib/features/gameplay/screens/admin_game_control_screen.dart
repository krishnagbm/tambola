import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../models/flash_housie_config.dart';
import '../../../models/mpt_called_number.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
import '../../../providers/app_providers.dart';

class AdminGameControlScreen extends ConsumerStatefulWidget {
  final String gameId;
  final bool autoPilot;

  const AdminGameControlScreen({
    super.key,
    required this.gameId,
    this.autoPilot = false,
  });

  @override
  ConsumerState<AdminGameControlScreen> createState() =>
      _AdminGameControlScreenState();
}

class _AdminGameControlScreenState
    extends ConsumerState<AdminGameControlScreen> {
  bool _isCalling = false;
  bool _isMuted = false;
  Timer? _celebrationTimer;
  int _celebrationSecondsLeft = 0;
  int _knownApprovedCount = -1;
  String? _celebrationMessage;

  // Auto-Pilot Host State
  bool _isAutoPilotEnabled = false;
  bool _isAutoPilotPaused = false;
  int _autoCallIntervalSeconds = 15;
  int _countdownSecondsLeft = 15;
  Timer? _autoCallTimer;
  bool _hasAutoConcluded = false;
  int _autoEndSecondsLeft = 0;
  Timer? _autoEndTimer;
  Timer? _neuroWaveUiTimer;
  NeuroWavePhase? _lastNeuroPhase;
  bool _isAutoFinalizingGrandWinners = false;

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;
    _neuroWaveUiTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      final game = ref.read(gameStreamProvider(widget.gameId)).value;
      if (game?.isFlashHousie == true) {
        final neuro = game!.flashHousieConfig?.computeNeuroWaveState(
          DateTime.now().millisecondsSinceEpoch,
        );
        if (neuro != null &&
            (neuro.isRevealing || _lastNeuroPhase != neuro.phase)) {
          _lastNeuroPhase = neuro.phase;
          setState(() {});
        }
      }
    });
    if (widget.autoPilot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoPilot();
      });
    }
  }

  @override
  void dispose() {
    _neuroWaveUiTimer?.cancel();
    _autoCallTimer?.cancel();
    _celebrationTimer?.cancel();
    _autoEndTimer?.cancel();
    super.dispose();
  }

  void _startAutoPilot() {
    _autoCallTimer?.cancel();
    setState(() {
      _isAutoPilotEnabled = true;
      _isAutoPilotPaused = false;
      _countdownSecondsLeft = _autoCallIntervalSeconds;
    });

    _autoCallTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isAutoPilotEnabled || _hasAutoConcluded) {
        timer.cancel();
        return;
      }
      // Hold countdown if FlashHousie NeuroWave Spotlight is currently revealing
      final currentGame = ref.read(gameStreamProvider(widget.gameId)).value;
      if (currentGame?.isFlashHousie == true &&
          currentGame?.flashHousieConfig != null) {
        final neuro = currentGame!.flashHousieConfig!.computeNeuroWaveState(
          DateTime.now().millisecondsSinceEpoch,
        );
        if (neuro.isRevealing) {
          return;
        }
      }
      // If celebrating a winner or currently making an async call, auto-concluding, or paused, hold the countdown
      if (_celebrationSecondsLeft > 0 ||
          _isCalling ||
          _isAutoPilotPaused ||
          _autoEndSecondsLeft > 0) {
        return;
      }

      setState(() {
        if (_countdownSecondsLeft > 1) {
          _countdownSecondsLeft--;
        } else {
          _countdownSecondsLeft = _autoCallIntervalSeconds;
          _handleCallNext();
        }
      });
    });
  }

  void _pauseAutoPilot() {
    setState(() {
      _isAutoPilotPaused = true;
    });
  }

  void _resumeAutoPilot() {
    setState(() {
      _isAutoPilotPaused = false;
    });
  }

  void _stopAutoPilot() {
    _autoCallTimer?.cancel();
    setState(() {
      _isAutoPilotEnabled = false;
      _isAutoPilotPaused = false;
      _countdownSecondsLeft = _autoCallIntervalSeconds;
    });
  }

  void _updateAutoCallInterval(int seconds) {
    setState(() {
      _autoCallIntervalSeconds = seconds;
      if (_countdownSecondsLeft > seconds) {
        _countdownSecondsLeft = seconds;
      }
    });
  }

  void _triggerCelebrationPause(String message) {
    _celebrationTimer?.cancel();
    setState(() {
      _celebrationSecondsLeft = 10;
      _celebrationMessage = message;
      // Reset countdown to full interval so players have ample time after celebration
      _countdownSecondsLeft = _autoCallIntervalSeconds;
    });

    _celebrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_celebrationSecondsLeft > 1) {
          _celebrationSecondsLeft--;
        } else {
          _celebrationSecondsLeft = 0;
          timer.cancel();
        }
      });
    });
  }

  void _triggerAutoConclusion() {
    if (_hasAutoConcluded) return;
    _hasAutoConcluded = true;
    _stopAutoPilot();
    _autoEndTimer?.cancel();

    // Immediately mark the game COMPLETED in the database so navigating away
    // to the Dashboard never leaves the game stuck in IN_PROGRESS!
    _autoFinalizeGame();
  }

  Future<void> _autoFinalizeGame() async {
    try {
      await ref.read(gameplayRepositoryProvider).endGame(widget.gameId);
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(myHostedGamesProvider);
      ref.invalidate(myJoinedGamesProvider);
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(myRewardsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🏆 All prizes won! Game concluded and final results published.',
            ),
            backgroundColor: AppTheme.accentSuccess,
          ),
        );
      }
    } catch (_) {}
  }

  void _handleCopyCode(String inviteCode) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite Code copied to clipboard!')),
    );
  }

  void _handleCopyLink(String inviteCode) {
    final link = '${AppConfig.appBaseUrl}/#/join/$inviteCode';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct join link copied to clipboard!')),
    );
  }

  Future<void> _handleShareInvite(MptGame game) async {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text =
        '🎉 You are invited to play DabHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to join directly on web or in app:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  Future<void> _handleAdvanceOrFinalizeFlashCycle(MptGame game) async {
    if (_isCalling) return;

    setState(() => _isCalling = true);
    try {
      MptGame latestGame = game;
      try {
        latestGame =
            await ref.read(gameRepositoryProvider).getGame(widget.gameId);
      } catch (_) {}
      final flashCfg = latestGame.flashHousieConfig;
      if (flashCfg == null) return;

      final repo = ref.read(gameplayRepositoryProvider);
      if (!flashCfg.isLastCycle) {
        final currentCycleNum = flashCfg.currentCycle;
        final roundLabel = flashCfg.activeCycleSpec.roundBadgeLabel;
        final updatedCfg = await repo.finalizeFlashHousieCycleAndAdvance(
          game: latestGame,
          advanceToNextCycle: true,
        );
        final finalizedSpec = updatedCfg?.cycles
            .where((c) => c.cycleIndex == currentCycleNum)
            .firstOrNull;
        ref.invalidate(gameStreamProvider(widget.gameId));
        ref.invalidate(calledNumbersStreamProvider(widget.gameId));
        ref.invalidate(claimsStreamProvider(widget.gameId));
        ref.invalidate(memoryRoundScoresStreamProvider(widget.gameId));
        ref.invalidate(hostGameRewardsProvider(widget.gameId));

        if (!mounted) return;
        if (finalizedSpec?.winnerName != null) {
          _triggerCelebrationPause(
            '🏆 ${finalizedSpec!.winnerName} won Round $currentCycleNum ($roundLabel) with ${finalizedSpec.winnerCorrectCount ?? 0} recalls! Launching Round ${currentCycleNum + 1} NeuroWave™ Spotlight...',
          );
        } else {
          _triggerCelebrationPause(
            '⚡ Round $currentCycleNum ($roundLabel) complete! Launching Round ${currentCycleNum + 1} NeuroWave™ Spotlight...',
          );
        }
      } else {
        final finalCfg = await repo.finalizeFlashHousieGrandWinners(latestGame);
        ref.invalidate(gameStreamProvider(widget.gameId));
        ref.invalidate(claimsStreamProvider(widget.gameId));
        ref.invalidate(memoryRoundScoresStreamProvider(widget.gameId));
        ref.invalidate(hostGameRewardsProvider(widget.gameId));
        if (!mounted) return;
        final fhWinner = finalCfg?.awardedWinnerNames['FULL_HOUSE'];
        if (fhWinner != null) {
          _triggerCelebrationPause(
            '🏆 $fhWinner crowned FlashHousie™ Full House Champion! Finalizing event results...',
          );
        }
        _triggerAutoConclusion();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error advancing FlashHousie™ round: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  Future<void> _handleCallNext() async {
    final cachedGame = ref.read(gameStreamProvider(widget.gameId)).value;
    if (cachedGame?.status == 'COMPLETED') {
      _stopAutoPilot();
      return;
    }

    // Special handling for FlashHousie™ 5 / 10 / 15 multi-cycle gameplay
    if (cachedGame != null &&
        cachedGame.isFlashHousie &&
        cachedGame.flashHousieConfig != null) {
      if (_isCalling) return;
      setState(() {
        _isCalling = true;
        _countdownSecondsLeft = _autoCallIntervalSeconds;
      });
      try {
        MptGame game = cachedGame;
        try {
          game = await ref.read(gameRepositoryProvider).getGame(widget.gameId);
        } catch (_) {}
        final flashCfg = game.flashHousieConfig!;
        final cycle = flashCfg.activeCycleSpec;

        if (cycle.startedAtMs == null) {
          await ref.read(gameplayRepositoryProvider).launchFlashHousieCycle(
                game: game,
                cycleIndex: flashCfg.currentCycle,
              );
          ref.invalidate(gameStreamProvider(widget.gameId));
          return;
        }

        final neuroState = flashCfg.computeNeuroWaveState(
          DateTime.now().millisecondsSinceEpoch,
        );
        if (neuroState.isRevealing) {
          if (!_isAutoPilotEnabled && mounted) {
            final secsLeft = (neuroState.remainingMsInPhase / 1000).ceil();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚡ NeuroWave™ Spotlight is active ($secsLeft s remaining in phase). Calling unlocks right after the wave!',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        final claimsNow =
            ref.read(claimsStreamProvider(widget.gameId)).value ?? [];
        final isCycleAlreadyWon =
            flashCfg.awardedWinners.containsKey(cycle.prizeKey) ||
            claimsNow.any(
              (c) => c.status == 'APPROVED' && c.prizeType == cycle.prizeKey,
            );

        if (cycle.isCompleted || isCycleAlreadyWon) {
          if (mounted) setState(() => _isCalling = false);
          await _handleAdvanceOrFinalizeFlashCycle(game);
          return;
        }

        final num = await ref
            .read(gameplayRepositoryProvider)
            .callNextFlashHousieNumber(game);
        ref.invalidate(calledNumbersStreamProvider(widget.gameId));
        ref.invalidate(gameStreamProvider(widget.gameId));

        if (num != null) {
          TambolaAudioCaller().announceNumber(num);
          // If this was the final ball of the round pool (e.g. 8/8), auto-crown the round winner
          // after a brief 3s tap window so players/host see the winner immediately!
          if (cycle.calledCount + 1 >= cycle.drawPool.length) {
            final completedCycleIdx = cycle.cycleIndex;
            final isFinalCycle = flashCfg.isLastCycle;
            Future.delayed(const Duration(seconds: 3), () async {
              if (!mounted) return;
              try {
                final freshGame = await ref
                    .read(gameRepositoryProvider)
                    .getGame(widget.gameId);
                final freshCfg = freshGame.flashHousieConfig;
                if (freshCfg == null ||
                    freshCfg.currentCycle != completedCycleIdx) {
                  return;
                }
                final repo = ref.read(gameplayRepositoryProvider);
                if (isFinalCycle) {
                  await repo.finalizeFlashHousieGrandWinners(freshGame);
                } else {
                  await repo.finalizeFlashHousieCycleAndAdvance(
                    game: freshGame,
                    advanceToNextCycle: false,
                  );
                }
                if (!mounted) return;
                ref.invalidate(gameStreamProvider(widget.gameId));
                ref.invalidate(claimsStreamProvider(widget.gameId));
                ref.invalidate(memoryRoundScoresStreamProvider(widget.gameId));
                ref.invalidate(hostGameRewardsProvider(widget.gameId));
              } catch (_) {}
            });
          }
        } else {
          if (mounted) {
            setState(() => _isCalling = false);
            await _handleAdvanceOrFinalizeFlashCycle(game);
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error calling FlashHousie™ ball: $e'),
            backgroundColor: AppTheme.accentDanger,
          ),
        );
      } finally {
        if (mounted) setState(() => _isCalling = false);
      }
      return;
    }

    final game = cachedGame;

    final claims = ref.read(claimsStreamProvider(widget.gameId)).value ?? [];
    final activePrizes = game?.prizesConfig ??
        [
          'EARLY_FIVE',
          'TOP_LINE',
          'MIDDLE_LINE',
          'BOTTOM_LINE',
          'FOUR_CORNERS',
          'FULL_HOUSE',
        ];
    final approvedClaimPrizes = claims
        .where((c) => c.status == 'APPROVED')
        .map((c) => c.prizeType)
        .toSet();
    final allPrizesWon = activePrizes.isNotEmpty &&
        activePrizes.every((p) => approvedClaimPrizes.contains(p));

    if (allPrizesWon) {
      _stopAutoPilot();
      _triggerAutoConclusion();
      return;
    }

    setState(() {
      _isCalling = true;
      _countdownSecondsLeft = _autoCallIntervalSeconds;
    });
    try {
      final num = await ref
          .read(gameplayRepositoryProvider)
          .callNextNumber(widget.gameId);
      ref.invalidate(calledNumbersStreamProvider(widget.gameId));

      if (num != null) {
        TambolaAudioCaller().announceNumber(num);
      } else {
        if (!mounted) return;
        _autoCallTimer?.cancel();
        setState(() => _isAutoPilotEnabled = false);
        await ref.read(gameplayRepositoryProvider).endGame(widget.gameId);
        ref.invalidate(gameStreamProvider(widget.gameId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All 90 numbers have been called! Game completed.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error calling number: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  Future<void> _handleEndGame() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag_rounded, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('End Game?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to conclude this DabHousie game?\n\nThis will mark the game as COMPLETED and display final results to all players.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('End & Finalize Game'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gameplayRepositoryProvider).endGame(widget.gameId);
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(myHostedGamesProvider);
      ref.invalidate(myJoinedGamesProvider);
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Game concluded successfully! Final results published.',
          ),
        ),
      );
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to end game: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    }
  }

  void _showEditGameNameDialog(String currentGameName) {
    final controller = TextEditingController(text: currentGameName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Event Name',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Event Name',
            hintText: 'e.g. Saturday Family DabHousie',
            prefixIcon: Icon(Icons.edit),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != currentGameName) {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(gameRepositoryProvider)
                      .updateGameName(widget.gameId, newName);
                  ref.invalidate(gameStreamProvider(widget.gameId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Event name updated successfully!'),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to update event name: $e'),
                      backgroundColor: AppTheme.accentDanger,
                    ),
                  );
                }
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExpandCapacity(int extraCapacity) async {
    try {
      await ref
          .read(gameRepositoryProvider)
          .increaseCapacity(
            gameId: widget.gameId,
            additionalCapacity: extraCapacity,
          );
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(registrationsStreamProvider(widget.gameId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Room capacity expanded by +$extraCapacity seats! Waiting players promoted automatically. 🚀',
          ),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error expanding capacity: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    }
  }

  void _showCapacityUpgradeDialog(
    BuildContext context,
    MptGame? game,
    int waitingCount,
  ) {
    final currentCap = game?.fundedCapacity ?? 5;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.upgrade_rounded,
              color: AppTheme.secondaryColor,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'Switch Plan / Add Seats',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Room Capacity: $currentCap Seats',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.bold,
              ),
            ),
            if (waitingCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentWarning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentWarning),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppTheme.accentWarning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$waitingCount player${waitingCount > 1 ? "s are" : " is"} waiting in the overflow queue and will be promoted immediately upon adding seats.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFDE68A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Select seats boost to add to this room:',
              style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildCapacityOptionButton(
                  ctx,
                  '+5 Seats',
                  5,
                  isRecommended: waitingCount > 0 && waitingCount <= 5,
                ),
                _buildCapacityOptionButton(
                  ctx,
                  '+10 Seats',
                  10,
                  isRecommended: waitingCount > 5 && waitingCount <= 10,
                ),
                _buildCapacityOptionButton(
                  ctx,
                  '+15 Seats',
                  15,
                  isRecommended: waitingCount > 10 && waitingCount <= 15,
                ),
                _buildCapacityOptionButton(
                  ctx,
                  '+25 Seats',
                  25,
                  isRecommended: waitingCount > 15 && waitingCount <= 25,
                ),
                _buildCapacityOptionButton(
                  ctx,
                  '+50 Seats',
                  50,
                  isRecommended: waitingCount > 25,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityOptionButton(
    BuildContext ctx,
    String label,
    int seats, {
    bool isRecommended = false,
  }) {
    return ElevatedButton(
      onPressed: () {
        Navigator.pop(ctx);
        _handleExpandCapacity(seats);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isRecommended
            ? AppTheme.secondaryColor
            : AppTheme.darkSurface,
        foregroundColor: isRecommended ? AppTheme.primaryDark : Colors.white,
        side: BorderSide(
          color: isRecommended
              ? AppTheme.secondaryColor
              : const Color(0xFF3B4163),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isRecommended ? AppTheme.primaryDark : Colors.white,
        ),
      ),
    );
  }

  void _showPlayersModal(
    BuildContext context,
    List<MptRegistration> registrations,
    MptGame? game,
  ) {
    final confirmed = registrations.where((r) => r.isConfirmed).toList();
    final waiting = registrations.where((r) => r.isWaiting).toList();
    final capacity = game?.fundedCapacity ?? 5;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: AppTheme.secondaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Joined Players (${confirmed.length} / $capacity)',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (waiting.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accentWarning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.accentWarning),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppTheme.accentWarning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${waiting.length} player(s) in lobby over $capacity limit.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showCapacityUpgradeDialog(
                                context,
                                game,
                                waiting.length,
                              );
                            },
                            icon: const Icon(Icons.upgrade_rounded, size: 14),
                            label: const Text('Upgrade Plan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentWarning,
                              foregroundColor: AppTheme.primaryDark,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (game != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E334D)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'INVITE CODE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  game.inviteCode,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    color: AppTheme.secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _handleShareInvite(game),
                            icon: const Icon(Icons.share_rounded, size: 16),
                            label: const Text('Share Invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondaryColor,
                              foregroundColor: AppTheme.primaryDark,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Expanded(
                    child: registrations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 48,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No players have joined yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Share the invite code or direct link with your players so they can get their tickets.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (game != null)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleShareInvite(game);
                                    },
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Share Invite Link'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: AppTheme.primaryDark,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            children: [
                              if (confirmed.isNotEmpty) ...[
                                Text(
                                  'CONFIRMED PLAYERS (${confirmed.length})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accentSuccess,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...confirmed.map(
                                  (r) => _buildPlayerTile(r, isConfirmed: true),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (waiting.isNotEmpty) ...[
                                Text(
                                  'WAITING ROOM PLAYERS (${waiting.length})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accentWarning,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...waiting.map(
                                  (r) =>
                                      _buildPlayerTile(r, isConfirmed: false),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerTile(MptRegistration r, {required bool isConfirmed}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConfirmed
              ? const Color(0xFF2E334D)
              : AppTheme.accentWarning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isConfirmed
                      ? AppTheme.primaryColor.withValues(alpha: 0.3)
                      : AppTheme.accentWarning.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  Formatters.getAvatarEmoji(r.avatar),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.darkSurface, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isConfirmed
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.6),
                        blurRadius: 3,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.displayName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isConfirmed
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Ticket #${r.registrationSeq}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${isConfirmed ? "Live" : "Waiting"}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isConfirmed
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                  : AppTheme.accentWarning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isConfirmed ? 'CONFIRMED' : 'WAITING',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isConfirmed
                    ? AppTheme.accentSuccess
                    : AppTheme.accentWarning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calledStream = ref.watch(calledNumbersStreamProvider(widget.gameId));
    final claimsStream = ref.watch(claimsStreamProvider(widget.gameId));
    final gameStream = ref.watch(gameStreamProvider(widget.gameId));
    final regStream = ref.watch(registrationsStreamProvider(widget.gameId));

    final game = gameStream.value;
    final registrations = regStream.value ?? [];
    final confirmedPlayers = registrations.where((r) => r.isConfirmed).toList();
    final waitingPlayers = registrations.where((r) => r.isWaiting).toList();
    final capacity = game?.fundedCapacity ?? 5;
    final isGameCompleted = game?.status == 'COMPLETED';
    final activePrizes =
        game?.prizesConfig ??
        [
          'EARLY_FIVE',
          'TOP_LINE',
          'MIDDLE_LINE',
          'BOTTOM_LINE',
          'FOUR_CORNERS',
          'FULL_HOUSE',
        ];
    final claims = claimsStream.value ?? [];
    final approvedClaimsList = claims
        .where((c) => c.status == 'APPROVED')
        .toList();
    final approvedClaimPrizes = {
      ...approvedClaimsList.map((c) => c.prizeType),
      ...(game?.flashHousieConfig?.awardedWinners.keys ?? const <String>[]),
    };
    final allPrizesWon =
        activePrizes.isNotEmpty &&
        activePrizes.every((p) => approvedClaimPrizes.contains(p));
    final regMap = {for (final r in registrations) r.userId: r};

    // If FlashHousie final round (e.g. ROUND_3) is won early (before 8/8 balls),
    // automatically crown FULL_HOUSE & conclude immediately without waiting for decoy balls!
    final flashCfgTop = game?.flashHousieConfig;
    if (game?.isFlashHousie == true &&
        flashCfgTop != null &&
        !isGameCompleted &&
        !_isAutoFinalizingGrandWinners &&
        approvedClaimPrizes.contains('ROUND_${flashCfgTop.totalCycles}') &&
        !approvedClaimPrizes.contains('FULL_HOUSE')) {
      _isAutoFinalizingGrandWinners = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await ref
              .read(gameplayRepositoryProvider)
              .finalizeFlashHousieGrandWinners(game!);
          if (!mounted) return;
          ref.invalidate(gameStreamProvider(widget.gameId));
          ref.invalidate(claimsStreamProvider(widget.gameId));
          ref.invalidate(memoryRoundScoresStreamProvider(widget.gameId));
          ref.invalidate(hostGameRewardsProvider(widget.gameId));
        } catch (_) {
          _isAutoFinalizingGrandWinners = false;
        }
      });
    }

    if (allPrizesWon && !isGameCompleted && !_hasAutoConcluded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasAutoConcluded) {
          _triggerAutoConclusion();
        }
      });
    }

    if (claimsStream.hasValue) {
      if (_knownApprovedCount == -1) {
        _knownApprovedCount = approvedClaimsList.length;
      } else if (approvedClaimsList.length > _knownApprovedCount) {
        final latestClaim = approvedClaimsList.first;
        _knownApprovedCount = approvedClaimsList.length;
        if (!isGameCompleted && !allPrizesWon) {
          final playerReg = regMap[latestClaim.userId];
          final winnerName = (playerReg?.displayName.isNotEmpty == true)
              ? playerReg!.displayName
              : (latestClaim.userName != null &&
                      latestClaim.userName != 'Player')
              ? latestClaim.userName!
              : 'Player';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.invalidate(hostGameRewardsProvider(widget.gameId));
              _triggerCelebrationPause(
                'Player "$winnerName" won ${Formatters.formatPrizeName(latestClaim.prizeType)}!',
              );
            }
          });
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () {
            ref.invalidate(myHostedGamesProvider);
            ref.invalidate(myJoinedGamesProvider);
            context.go('/');
          },
        ),
        title: const Text('Organizer Game Control'),
        actions: [
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: _isMuted ? Colors.grey : AppTheme.secondaryColor,
            ),
            tooltip: _isMuted ? 'Unmute Audio Caller' : 'Mute Audio Caller',
            onPressed: () {
              setState(() {
                _isMuted = !_isMuted;
                TambolaAudioCaller().isMuted = _isMuted;
              });
            },
          ),
          if (game != null)
            IconButton(
              icon: const Icon(
                Icons.share_rounded,
                color: AppTheme.secondaryColor,
              ),
              tooltip: 'Share Invite Code & Link',
              onPressed: () => _handleShareInvite(game),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: registrations.isNotEmpty,
              label: Text('${registrations.length}'),
              backgroundColor: AppTheme.secondaryColor,
              textColor: AppTheme.primaryDark,
              child: const Icon(Icons.groups_rounded, color: Colors.white),
            ),
            tooltip: 'View Players (${registrations.length})',
            onPressed: () => _showPlayersModal(context, registrations, game),
          ),
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Display Game on TV / Projector',
            onPressed: () =>
                LiveDisplayHelper.showDisplayOnTvDialog(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(calledNumbersStreamProvider(widget.gameId));
              ref.invalidate(claimsStreamProvider(widget.gameId));
              ref.invalidate(gameStreamProvider(widget.gameId));
              ref.invalidate(registrationsStreamProvider(widget.gameId));
              ref.invalidate(hostGameRewardsProvider(widget.gameId));
            },
          ),
        ],
      ),
      body: calledStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (calledNumbers) {
          final isFlashHousie =
              game?.isFlashHousie == true && game?.flashHousieConfig != null;
          final flashCfg = game?.flashHousieConfig;
          final activeFlashCycle = flashCfg?.activeCycleSpec;
          final flashCalledInts =
              activeFlashCycle?.calledNumbers ?? const <int>[];

          final latest = isFlashHousie
              ? (flashCalledInts.isNotEmpty ? flashCalledInts.last : null)
              : (calledNumbers.isNotEmpty ? calledNumbers.last.number : null);
          final calledSet = isFlashHousie
              ? flashCalledInts.toSet()
              : calledNumbers.map((e) => e.number).toSet();
          final effectiveCalledCount = isFlashHousie
              ? flashCalledInts.length
              : calledNumbers.length;
          final isMaxNumbers = isFlashHousie
              ? (flashCfg!.isLastCycle &&
                  activeFlashCycle!.isCompleted &&
                  flashCfg.awardedWinners.containsKey('FULL_HOUSE'))
              : calledNumbers.length >= 90;
          final disableCalling =
              _isCalling ||
              isMaxNumbers ||
              allPrizesWon ||
              isGameCompleted ||
              (_celebrationSecondsLeft > 0);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final is3Column = constraints.maxWidth >= 1080;
                    final is2Column =
                        constraints.maxWidth >= 750 &&
                        constraints.maxWidth < 1080;

                    // ========================================================
                    // 1. WIDE SCREEN: 3-COLUMN LAYOUT
                    // Left: Pre-Game Banner, Header, Claims, End Game | Middle: Caller & Master Board (Full Visibility) | Right: Two Dedicated Cards (Confirmed & Waiting with own scrollbars)
                    // ========================================================
                    if (is3Column) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column (Pre-Game Banner, Header, Prize Claims & Winners, End Game)
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (effectiveCalledCount == 0 &&
                                    !isGameCompleted) ...[
                                  _buildPreGameBanner(
                                    game,
                                    confirmedPlayers.length,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (allPrizesWon && !isGameCompleted) ...[
                                  _buildAllPrizesWonBanner(),
                                  const SizedBox(height: 10),
                                ],
                                _buildGameHeaderAndInviteCard(
                                  game,
                                  registrations,
                                  isGameCompleted,
                                ),
                                const SizedBox(height: 12),
                                _buildClaimsQueue(
                                  claimsStream,
                                  regMap,
                                  game: game,
                                  activePrizes: activePrizes,
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: isGameCompleted
                                      ? null
                                      : _handleEndGame,
                                  icon: const Icon(
                                    Icons.flag_outlined,
                                    color: AppTheme.accentDanger,
                                  ),
                                  label: Text(
                                    isGameCompleted
                                        ? 'Game Concluded'
                                        : 'End Game & Conclude Event',
                                    style: TextStyle(
                                      color: isGameCompleted
                                          ? Colors.grey
                                          : AppTheme.accentDanger,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: isGameCompleted
                                          ? Colors.grey
                                          : AppTheme.accentDanger,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Middle Column (Max Width: Latest Number, Call Button, Compact Master Board)
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_celebrationSecondsLeft > 0)
                                  _buildCelebrationPauseBanner(),
                                _buildCallerHeader(
                                  game,
                                  latest,
                                  effectiveCalledCount,
                                  calledNumbers,
                                  isGameCompleted,
                                ),
                                if (game?.isFlashHousie == true) ...[
                                  const SizedBox(height: 8),
                                  _buildFlashHousieHostControlCard(game!),
                                ],
                                const SizedBox(height: 8),
                                _buildMainActionButton(
                                  game: game,
                                  isGameCompleted: isGameCompleted,
                                  allPrizesWon: allPrizesWon,
                                  isMaxNumbers: isMaxNumbers,
                                  calledCount: effectiveCalledCount,
                                  disableCalling: disableCalling,
                                  verticalPadding: 13,
                                  fontSize: 15,
                                  iconSize: 24,
                                ),
                                const SizedBox(height: 8),
                                _buildMasterBoard(calledSet, game: game),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Right Column: Two distinct sidebar cards, each with its own vertical scrollbar
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: 680,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: _buildConfirmedPlayersSidebarCard(
                                      game,
                                      confirmedPlayers,
                                      capacity,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    flex: 2,
                                    child: _buildWaitingPlayersSidebarCard(
                                      game,
                                      waitingPlayers,
                                      capacity,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // ========================================================
                    // 2. MEDIUM SCREEN (e.g. 800px monitor / Tablet): 2 COLUMNS
                    // ========================================================
                    if (is2Column) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGameHeaderAndInviteCard(
                            game,
                            registrations,
                            isGameCompleted,
                          ),
                          const SizedBox(height: 12),
                          if (allPrizesWon && !isGameCompleted) ...[
                            _buildAllPrizesWonBanner(),
                            const SizedBox(height: 14),
                          ],
                          if (effectiveCalledCount == 0 && !isGameCompleted) ...[
                            _buildPreGameBanner(game, confirmedPlayers.length),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (_celebrationSecondsLeft > 0)
                                      _buildCelebrationPauseBanner(),
                                    _buildCallerHeader(
                                      game,
                                      latest,
                                      effectiveCalledCount,
                                      calledNumbers,
                                      isGameCompleted,
                                    ),
                                    if (game?.isFlashHousie == true) ...[
                                      const SizedBox(height: 12),
                                      _buildFlashHousieHostControlCard(game!),
                                    ],
                                    const SizedBox(height: 14),
                                    _buildMainActionButton(
                                      game: game,
                                      isGameCompleted: isGameCompleted,
                                      allPrizesWon: allPrizesWon,
                                      isMaxNumbers: isMaxNumbers,
                                      calledCount: effectiveCalledCount,
                                      disableCalling: disableCalling,
                                      verticalPadding: 18,
                                      fontSize: 17,
                                      iconSize: 28,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildMasterBoard(calledSet, game: game),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: isGameCompleted
                                          ? null
                                          : _handleEndGame,
                                      icon: const Icon(
                                        Icons.flag_outlined,
                                        color: AppTheme.accentDanger,
                                      ),
                                      label: Text(
                                        isGameCompleted
                                            ? 'Game Concluded'
                                            : 'End Game & Conclude Event',
                                        style: TextStyle(
                                          color: isGameCompleted
                                              ? Colors.grey
                                              : AppTheme.accentDanger,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: isGameCompleted
                                              ? Colors.grey
                                              : AppTheme.accentDanger,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildClaimsQueue(
                                      claimsStream,
                                      regMap,
                                      game: game,
                                      activePrizes: activePrizes,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildConfirmedPlayersSidebarCard(
                                      game,
                                      confirmedPlayers,
                                      capacity,
                                      height: 280,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildWaitingPlayersSidebarCard(
                                      game,
                                      waitingPlayers,
                                      capacity,
                                      height: 200,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    // ========================================================
                    // 3. MOBILE SCREEN (< 750px): STACKED 1 COLUMN
                    // ========================================================
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGameHeaderAndInviteCard(
                          game,
                          registrations,
                          isGameCompleted,
                        ),
                        const SizedBox(height: 12),
                        if (allPrizesWon && !isGameCompleted) ...[
                          _buildAllPrizesWonBanner(),
                          const SizedBox(height: 14),
                        ],
                        if (effectiveCalledCount == 0 && !isGameCompleted) ...[
                          _buildPreGameBanner(game, confirmedPlayers.length),
                          const SizedBox(height: 14),
                        ],
                        if (_celebrationSecondsLeft > 0)
                          _buildCelebrationPauseBanner(),
                        _buildCallerHeader(
                          game,
                          latest,
                          effectiveCalledCount,
                          calledNumbers,
                          isGameCompleted,
                        ),
                        if (game?.isFlashHousie == true) ...[
                          const SizedBox(height: 12),
                          _buildFlashHousieHostControlCard(game!),
                        ],
                        const SizedBox(height: 14),
                        _buildMainActionButton(
                          game: game,
                          isGameCompleted: isGameCompleted,
                          allPrizesWon: allPrizesWon,
                          isMaxNumbers: isMaxNumbers,
                          calledCount: effectiveCalledCount,
                          disableCalling: disableCalling,
                          verticalPadding: 18,
                          fontSize: 17,
                          iconSize: 28,
                        ),
                        const SizedBox(height: 16),
                        _buildMasterBoard(calledSet, game: game),
                        const SizedBox(height: 16),
                        _buildClaimsQueue(
                          claimsStream,
                          regMap,
                          game: game,
                          activePrizes: activePrizes,
                        ),
                        const SizedBox(height: 16),
                        _buildConfirmedPlayersSidebarCard(
                          game,
                          confirmedPlayers,
                          capacity,
                          height: 280,
                        ),
                        const SizedBox(height: 12),
                        _buildWaitingPlayersSidebarCard(
                          game,
                          waitingPlayers,
                          capacity,
                          height: 200,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: isGameCompleted ? null : _handleEndGame,
                          icon: const Icon(
                            Icons.flag_outlined,
                            color: AppTheme.accentDanger,
                          ),
                          label: Text(
                            isGameCompleted
                                ? 'Game Concluded'
                                : 'End Game & Conclude Event',
                            style: TextStyle(
                              color: isGameCompleted
                                  ? Colors.grey
                                  : AppTheme.accentDanger,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: isGameCompleted
                                  ? Colors.grey
                                  : AppTheme.accentDanger,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFlashHousieHostControlCard(MptGame game) {
    final flashCfg = game.flashHousieConfig;
    if (flashCfg == null) return const SizedBox.shrink();
    final cycle = flashCfg.activeCycleSpec;
    final neuroState = flashCfg.computeNeuroWaveState(
      DateTime.now().millisecondsSinceEpoch,
    );
    final scoresAsync = ref.watch(memoryRoundScoresStreamProvider(widget.gameId));
    final allScores = scoresAsync.value ?? const <MptMemoryRoundScore>[];
    final currentCycleScores = allScores
        .where((s) => s.cycleNumber == flashCfg.currentCycle)
        .toList()
      ..sort(MptMemoryRoundScore.compareStandings);

    final claims = ref.watch(claimsStreamProvider(widget.gameId)).value ?? [];
    final isRoundPrizeWon =
        flashCfg.awardedWinners.containsKey(cycle.prizeKey) ||
        claims.any(
          (c) => c.status == 'APPROVED' && c.prizeType == cycle.prizeKey,
        );

    final secsLeft = (neuroState.remainingMsInPhase / 1000).ceil();
    final formattedDigital =
        '00:${secsLeft.clamp(0, 99).toString().padLeft(2, '0')}';

    String statusTitle;
    Color statusColor;
    switch (neuroState.phase) {
      case NeuroWavePhase.waitingToStart:
        statusTitle = '⏳ Waiting to Launch Round ${flashCfg.currentCycle} NeuroWave™';
        statusColor = AppTheme.accentWarning;
        break;
      case NeuroWavePhase.stageReadiness:
        statusTitle = '🎯 NeuroWave™ Dynamic Stage Readiness';
        statusColor = const Color(0xFF38BDF8);
        break;
      case NeuroWavePhase.columnWave:
        statusTitle =
            '🌊 NeuroWave™ Column Wave Active: Col ${(neuroState.visibleColumn ?? 0) + 1}';
        statusColor = AppTheme.secondaryColor;
        break;
      case NeuroWavePhase.memoryLockInPause:
        statusTitle = '🧠 NeuroWave™ Memory Lock-In Pause';
        statusColor = const Color(0xFFA78BFA);
        break;
      case NeuroWavePhase.callingActive:
        statusTitle = isRoundPrizeWon
            ? '🏆 Round ${flashCfg.currentCycle} Won! (${cycle.calledCount}/${cycle.drawPool.length} Balls Drawn)'
            : cycle.isCompleted
            ? '🏁 Round ${flashCfg.currentCycle} Pool Complete (${cycle.calledCount}/${cycle.drawPool.length} Balls)'
            : '🎱 Caller Active • ${cycle.calledCount} / ${cycle.drawPool.length} Balls Drawn';
        statusColor = isRoundPrizeWon
            ? AppTheme.secondaryColor
            : AppTheme.accentSuccess;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141829),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.65),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppTheme.secondaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${flashCfg.displayTitle} • Round ${flashCfg.currentCycle} of ${flashCfg.totalCycles}',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.secondaryColor),
                ),
                child: Text(
                  cycle.roundBadgeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
              if (neuroState.isRevealing) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 20, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        formattedDigital,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (currentCycleScores.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LIVE ${cycle.roundBadgeLabel} RECALL LEADERBOARD (TOP 3)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFCBD5E1),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...currentCycleScores.take(3).toList().asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final s = entry.value;
                    final medal = rank == 1 ? '🥇' : (rank == 2 ? '🥈' : '🥉');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$medal ${s.displayName}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '⭐ ${s.netScore} pts  •  ✓ ${s.correctCount}  •  ✗ ${s.wrongTapCount}${s.wrongTapCount > 0 ? " (-${s.wrongTapCount * MptMemoryRoundScore.penaltyPerWrongTap})" : ""}  •  ⚡ ${(s.cumulativeReactionMs / 1000).toStringAsFixed(1)}s',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          if ((cycle.isCompleted || isRoundPrizeWon) &&
              game.status != 'COMPLETED') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isCalling
                  ? null
                  : () => _handleAdvanceOrFinalizeFlashCycle(game),
              icon: const Icon(Icons.emoji_events_rounded, size: 18),
              label: Text(
                flashCfg.isLastCycle
                    ? '🏆 Crown Final Round & Full House Winners'
                    : isRoundPrizeWon
                    ? '🏆 ${cycle.roundBadgeLabel} Won — Launch Round ${flashCfg.currentCycle + 1}'
                    : '🏆 Crown ${cycle.roundBadgeLabel} Winner & Launch Round ${flashCfg.currentCycle + 1}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
                foregroundColor: AppTheme.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainActionButton({
    MptGame? game,
    required bool isGameCompleted,
    required bool allPrizesWon,
    required bool isMaxNumbers,
    required int calledCount,
    required bool disableCalling,
    double verticalPadding = 14,
    double fontSize = 16,
    double iconSize = 24,
  }) {
    if (isGameCompleted) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: Icon(Icons.flag_rounded, size: iconSize),
        label: Text(
          '🏁 Game Concluded',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: const Color(0xFF222639),
          disabledForegroundColor: const Color(0xFF718096),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    if (allPrizesWon || isMaxNumbers) {
      return ElevatedButton.icon(
        onPressed: _handleEndGame,
        icon: Icon(Icons.flag_rounded, size: iconSize, color: Colors.white),
        label: Text(
          allPrizesWon
              ? '🏆 All Prizes Won — End & Conclude Event'
              : (game?.isFlashHousie == true
                    ? '🏁 All Rounds Complete — End & Conclude Event'
                    : '🏁 All 90 Numbers Called — End & Conclude Event'),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentDanger,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
      );
    }

    final isCelebrating = _celebrationSecondsLeft > 0;
    final flashCfg = game?.flashHousieConfig;
    final activeFlashCycle = flashCfg?.activeCycleSpec;
    final neuroState = flashCfg?.computeNeuroWaveState(
      DateTime.now().millisecondsSinceEpoch,
    );
    final isFlashRevealing = neuroState?.isRevealing == true;
    final claimsList =
        ref.watch(claimsStreamProvider(widget.gameId)).value ?? [];
    final isFlashRoundPrizeWon = activeFlashCycle != null &&
        ((flashCfg?.awardedWinners.containsKey(activeFlashCycle.prizeKey) ==
                true) ||
            claimsList.any(
              (c) =>
                  c.status == 'APPROVED' &&
                  c.prizeType == activeFlashCycle.prizeKey,
            ));
    final isFlashRoundDone =
        (activeFlashCycle?.isCompleted == true) || isFlashRoundPrizeWon;
    final neuroSecsLeft = neuroState != null
        ? (neuroState.remainingMsInPhase / 1000).ceil()
        : 0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isAutoPilotEnabled
              ? AppTheme.secondaryColor.withValues(alpha: 0.6)
              : const Color(0xFF2E334D),
          width: _isAutoPilotEnabled ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Host Mode Selector Tabs (Compact)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isAutoPilotEnabled ? null : () => _startAutoPilot(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _isAutoPilotEnabled
                            ? AppTheme.secondaryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: _isAutoPilotEnabled
                            ? [
                                BoxShadow(
                                  color: AppTheme.secondaryColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.smart_toy_rounded,
                            size: 15,
                            color: _isAutoPilotEnabled
                                ? AppTheme.primaryDark
                                : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '🤖 Auto-Pilot Host',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isAutoPilotEnabled
                                  ? AppTheme.primaryDark
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                          if (_isAutoPilotEnabled) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: !_isAutoPilotEnabled ? null : () => _stopAutoPilot(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: !_isAutoPilotEnabled
                            ? AppTheme.primaryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_none_rounded,
                            size: 15,
                            color: !_isAutoPilotEnabled
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '🎙️ Live Master Host',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_isAutoPilotEnabled
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 2. Body based on Selected Mode
          if (_isAutoPilotEnabled) ...[
            // ----------------------------------------------------
            // AUTO-PILOT 2-COLUMN SPLIT PANEL
            // Left: Pace Preset Chips & Draw Controls
            // Right: Digital Countdown Timer Display
            // ----------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Column: Pace & Controls
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pace Chips Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.speed_rounded,
                              size: 14,
                              color: AppTheme.secondaryColor,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Pace: ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            _buildPacePresetChip('8s Fast', 8),
                            const SizedBox(width: 3),
                            _buildPacePresetChip('15s Std', 15),
                            const SizedBox(width: 3),
                            _buildPacePresetChip('20s Slow', 20),
                            const SizedBox(width: 3),
                            _buildPacePresetChip('30s', 30),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Action buttons
                      Row(
                        children: [
                          if (_isAutoPilotPaused)
                            ElevatedButton.icon(
                              onPressed: _resumeAutoPilot,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 15,
                              ),
                              label: const Text(
                                'Resume',
                                style: TextStyle(fontSize: 11.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentSuccess,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: _pauseAutoPilot,
                              icon: const Icon(Icons.pause_rounded, size: 15),
                              label: const Text(
                                'Pause',
                                style: TextStyle(fontSize: 11.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF334155),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed:
                                (disableCalling || isFlashRevealing)
                                    ? null
                                    : _handleCallNext,
                            icon: const Icon(Icons.skip_next_rounded, size: 15),
                            label: Text(
                              isFlashRoundDone
                                  ? 'Next Round'
                                  : 'Draw Now',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFlashRoundDone
                                  ? AppTheme.secondaryColor
                                  : AppTheme.primaryColor,
                              foregroundColor: isFlashRoundDone
                                  ? AppTheme.primaryDark
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Right Column: Digital Countdown Timer Box (Compact, no progress bar)
                Expanded(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCelebrating || isFlashRevealing
                            ? AppTheme.secondaryColor
                            : _isAutoPilotPaused
                            ? AppTheme.accentWarning
                            : const Color(0xFF38BDF8),
                        width: 1.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isCelebrating
                                  ? Icons.celebration_rounded
                                  : _isAutoPilotPaused
                                  ? Icons.pause_circle_outline_rounded
                                  : Icons.timer_outlined,
                              size: 16,
                              color: isCelebrating || isFlashRevealing
                                  ? AppTheme.secondaryColor
                                  : _isAutoPilotPaused
                                  ? AppTheme.accentWarning
                                  : const Color(0xFF38BDF8),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isCelebrating
                                  ? 'WINNER PAUSE'
                                  : isFlashRevealing
                                  ? 'NEUROWAVE™'
                                  : _isAutoPilotPaused
                                  ? 'PAUSED'
                                  : 'NEXT BALL IN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: isCelebrating || isFlashRevealing
                                    ? AppTheme.secondaryColor
                                    : _isAutoPilotPaused
                                    ? AppTheme.accentWarning
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isCelebrating
                              ? '00:${_celebrationSecondsLeft.clamp(0, 99).toString().padLeft(2, '0')}'
                              : isFlashRevealing
                              ? '00:${neuroSecsLeft.clamp(0, 99).toString().padLeft(2, '0')}'
                              : _isAutoPilotPaused
                              ? 'PAUSED'
                              : _isCalling
                              ? 'DRAWING...'
                              : '00:${_countdownSecondsLeft.clamp(0, 99).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5,
                            color: isCelebrating || isFlashRevealing
                                ? AppTheme.secondaryColor
                                : _isAutoPilotPaused
                                ? AppTheme.accentWarning
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // ----------------------------------------------------
            // MANUAL LIVE MASTER HOST PANEL
            // ----------------------------------------------------
            if (isCelebrating)
              ElevatedButton.icon(
                onPressed: null,
                icon: Icon(
                  Icons.celebration_rounded,
                  size: iconSize,
                  color: AppTheme.secondaryColor,
                ),
                label: Text(
                  '🎉 Celebrating Winner... (00:${_celebrationSecondsLeft.clamp(0, 99).toString().padLeft(2, '0')})',
                  style: TextStyle(
                    fontSize: fontSize + 1,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: AppTheme.secondaryColor,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF161929),
                  disabledForegroundColor: AppTheme.secondaryColor,
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                      color: AppTheme.secondaryColor,
                      width: 2.0,
                    ),
                  ),
                ),
              )
            else if (isFlashRevealing)
              ElevatedButton.icon(
                onPressed: null,
                icon: Icon(
                  Icons.timer_outlined,
                  size: iconSize + 2,
                  color: AppTheme.secondaryColor,
                ),
                label: Text(
                  '⚡ NeuroWave™ Spotlight Active • 00:${neuroSecsLeft.clamp(0, 99).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: fontSize + 2,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 0.8,
                    color: AppTheme.secondaryColor,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF161929),
                  disabledForegroundColor: AppTheme.secondaryColor,
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                      color: AppTheme.secondaryColor,
                      width: 2.0,
                    ),
                  ),
                ),
              )
            else if (isFlashRoundDone && flashCfg != null && activeFlashCycle != null)
              ElevatedButton.icon(
                onPressed: disableCalling ? null : _handleCallNext,
                icon: Icon(Icons.emoji_events_rounded, size: iconSize),
                label: _isCalling
                    ? const Text('Finalizing Round Standings...')
                    : Text(
                        flashCfg.isLastCycle
                            ? '🏁 FINAL ROUND COMPLETE — CROWN WINNERS & CONCLUDE'
                            : '🏆 ${activeFlashCycle.roundBadgeLabel} COMPLETE — CROWN WINNER & LAUNCH ROUND ${flashCfg.currentCycle + 1}',
                        style: TextStyle(
                          fontSize: fontSize - 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryColor,
                  foregroundColor: AppTheme.primaryDark,
                  disabledBackgroundColor: const Color(0xFF222639),
                  disabledForegroundColor: const Color(0xFF718096),
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: disableCalling ? null : _handleCallNext,
                icon: Icon(Icons.campaign_rounded, size: iconSize),
                label: _isCalling
                    ? const Text('Selecting Number...')
                    : Text(
                        flashCfg != null && activeFlashCycle != null
                            ? (activeFlashCycle.startedAtMs == null
                                  ? '🚀 LAUNCH ${activeFlashCycle.roundBadgeLabel} NEUROWAVE™ SPOTLIGHT'
                                  : (calledCount == 0
                                        ? 'CALL FIRST BALL (${activeFlashCycle.roundBadgeLabel})'
                                        : 'CALL NEXT BALL ($calledCount / ${activeFlashCycle.drawPool.length})'))
                            : (calledCount == 0
                                  ? 'CALL FIRST NUMBER'
                                  : 'CALL NEXT NUMBER ($calledCount / 90)'),
                        style: TextStyle(
                          fontSize: fontSize + 0.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentSuccess,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF222639),
                  disabledForegroundColor: const Color(0xFF718096),
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Switch to Auto-Pilot prompt card
            InkWell(
              onTap: () => _startAutoPilot(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.smart_toy_outlined,
                      size: 16,
                      color: AppTheme.secondaryColor,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Want hands-free calling? Switch to Auto-Pilot Host to draw numbers automatically.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Launch Auto',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPacePresetChip(String label, int seconds) {
    final isSelected = _autoCallIntervalSeconds == seconds;
    return InkWell(
      onTap: () => _updateAutoCallInterval(seconds),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondaryColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected
                ? AppTheme.secondaryColor
                : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? AppTheme.primaryDark : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildAllPrizesWonBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                color: AppTheme.secondaryColor,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'All Prizes Won! 🏆',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                        if (_autoEndSecondsLeft > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Auto-concluding in ${_autoEndSecondsLeft}s',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _autoEndSecondsLeft > 0
                          ? 'All prizes have approved winners! Auto-Pilot has stopped. Game will automatically conclude in $_autoEndSecondsLeft seconds.'
                          : 'All configured prizes have approved winners. Number calling is concluded. Tap below to finalize and publish results.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () async {
              _autoEndTimer?.cancel();
              setState(() => _autoEndSecondsLeft = 0);
              await _autoFinalizeGame();
            },
            icon: const Icon(Icons.flag_rounded, size: 18),
            label: const Text(
              'Conclude Now & Finalize',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedPlayersSidebarCard(
    MptGame? game,
    List<MptRegistration> confirmed,
    int capacity, {
    double? height,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                color: AppTheme.secondaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirmed Players (${confirmed.length}/$capacity)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (game != null)
                IconButton(
                  icon: const Icon(
                    Icons.share_rounded,
                    size: 16,
                    color: AppTheme.secondaryColor,
                  ),
                  tooltip: 'Share Invite',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleShareInvite(game),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2E334D), height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: confirmed.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 32,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No players joined yet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Share your invite code or link with players.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (game != null)
                            ElevatedButton.icon(
                              onPressed: () => _handleShareInvite(game),
                              icon: const Icon(Icons.share_rounded, size: 13),
                              label: const Text('Share Invite'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.secondaryColor,
                                foregroundColor: AppTheme.primaryDark,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 6),
                      children: confirmed
                          .map((r) => _buildPlayerTile(r, isConfirmed: true))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingPlayersSidebarCard(
    MptGame? game,
    List<MptRegistration> waiting,
    int capacity, {
    double? height,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: waiting.isNotEmpty
              ? AppTheme.accentWarning.withValues(alpha: 0.6)
              : const Color(0xFF2E334D),
          width: waiting.isNotEmpty ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                color: AppTheme.accentWarning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting Room (${waiting.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.upgrade_rounded,
                  size: 18,
                  color: AppTheme.secondaryColor,
                ),
                tooltip: 'Switch Plan / Add Seats',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(),
                onPressed: () =>
                    _showCapacityUpgradeDialog(context, game, waiting.length),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2E334D), height: 1),
          const SizedBox(height: 8),
          if (waiting.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentWarning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.accentWarning.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppTheme.accentWarning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${waiting.length} player(s) waiting over $capacity limit.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFDE68A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showCapacityUpgradeDialog(
                      context,
                      game,
                      waiting.length,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentWarning,
                      foregroundColor: AppTheme.primaryDark,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: const Text(
                      'Add Seats',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: waiting.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 28,
                            color: AppTheme.accentSuccess.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Lobby queue is clear',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'All joined players currently have confirmed tickets.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 6),
                      children: waiting
                          .map((r) => _buildPlayerTile(r, isConfirmed: false))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameHeaderAndInviteCard(
    MptGame? game,
    List<MptRegistration> registrations,
    bool isGameCompleted,
  ) {
    final capacity = game?.fundedCapacity ?? 5;
    final isFreeTier = capacity <= 5;
    final inviteCode = game?.inviteCode ?? '---';
    final confirmedCount = registrations.where((r) => r.isConfirmed).length;
    final waitingCount = registrations.where((r) => r.isWaiting).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E334D)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.15),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Capacity Tier & Number of Players Joined (+ Add Seats)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Capacity Tier Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isFreeTier ? '5-Player (Free)' : '$capacity-Member Game',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '👥 $confirmedCount/$capacity Joined',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Switch Plan / Add Seats Chip
                  InkWell(
                    onTap: () =>
                        _showCapacityUpgradeDialog(context, game, waitingCount),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.secondaryColor,
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upgrade_rounded,
                            size: 13,
                            color: AppTheme.secondaryColor,
                          ),
                          SizedBox(width: 2),
                          Text(
                            '+ Seats',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Message when no players have joined yet
          if (registrations.isEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF60A5FA), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No players have joined yet. Share your 6-digit room code or join link with your players so they can enter and receive tickets before you call numbers.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Bottom Bar: Invite Code Box + Action Buttons
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                // Invite Code Box with Copy
                InkWell(
                  onTap: () => _handleCopyCode(inviteCode),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ROOM INVITE CODE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              inviteCode,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.secondaryColor,
                                letterSpacing: 1.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: AppTheme.secondaryColor,
                        ),
                      ],
                    ),
                  ),
                ),

                // Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showCapacityUpgradeDialog(
                        context,
                        game,
                        waitingCount,
                      ),
                      icon: const Icon(Icons.upgrade_rounded, size: 16),
                      label: const Text('Switch Plan / Add Seats'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: game != null
                          ? () => _handleShareInvite(game)
                          : null,
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share Invite'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: AppTheme.primaryDark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _handleCopyLink(inviteCode),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy Link'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/admin-lobby/${widget.gameId}'),
                      icon: const Icon(Icons.meeting_room_outlined, size: 16),
                      label: const Text('Lobby View'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreGameBanner(MptGame? game, int confirmedCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentSuccess.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentSuccess.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.campaign_outlined,
            color: AppTheme.accentSuccess,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Game is Ready to Start! 🎲',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentSuccess,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  confirmedCount > 0
                      ? '$confirmedCount players are in the game. When everyone is ready with their tickets, tap "CALL FIRST NUMBER" below to begin!'
                      : 'Invite your players first. When they have joined, tap "CALL FIRST NUMBER" below to begin drawing balls.',
                  style: const TextStyle(
                    fontSize: 11.5,
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

  Widget _buildCelebrationPauseBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.celebration_rounded,
            color: AppTheme.secondaryColor,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Celebration Pause (${_celebrationSecondsLeft}s)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_celebrationSecondsLeft}s',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_celebrationMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _celebrationMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              _celebrationTimer?.cancel();
              setState(() => _celebrationSecondsLeft = 0);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Skip Pause', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCallerHeader(
    MptGame? game,
    int? latest,
    int totalCalled, [
    List<MptCalledNumber>? calledNumbers,
    bool isGameCompleted = false,
  ]) {
    final isFlash =
        game?.isFlashHousie == true && game?.flashHousieConfig != null;
    final activeFlashCycle = game?.flashHousieConfig?.activeCycleSpec;
    final flashCalledInts = activeFlashCycle?.calledNumbers ?? const <int>[];
    final recentInts = isFlash
        ? flashCalledInts.reversed.toList()
        : ((calledNumbers != null && calledNumbers.isNotEmpty)
              ? calledNumbers.reversed.skip(1).take(6).map((e) => e.number).toList()
              : <int>[]);
    final maxPoolCount = isFlash
        ? (activeFlashCycle?.drawPool.length ?? 8)
        : 90;
    final countLabel = isFlash
        ? '${activeFlashCycle?.roundBadgeLabel ?? "Round"} Pool Called'
        : 'Total Called';
    final capacity = game?.fundedCapacity ?? 5;
    final isFreeTier = capacity <= 5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Event Title & Badges Bar (Prominent in Middle Header)
          if (game != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.celebration,
                  size: 20,
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    game.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit,
                    size: 16,
                    color: AppTheme.primaryLight,
                  ),
                  tooltip: 'Edit Event Name',
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                  onPressed: () => _showEditGameNameDialog(game.name),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isGameCompleted
                        ? const Color(0xFF718096).withValues(alpha: 0.2)
                        : AppTheme.accentSuccess.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isGameCompleted ? 'COMPLETED' : '🟢 LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isGameCompleted
                          ? const Color(0xFFA0AEC0)
                          : AppTheme.accentSuccess,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    isFreeTier ? '5-Player (Free)' : '$capacity-Member Game',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LATEST NUMBER',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    latest != null ? '$latest' : '---',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.secondaryColor,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$totalCalled / $maxPoolCount',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    countLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (recentInts.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  isFlash ? 'ROUND BALLS: ' : 'LAST 6: ',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.secondaryColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: recentInts.asMap().entries.map((entry) {
                        final isLatestChip = isFlash && entry.key == 0;
                        final ballNum = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(right: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isLatestChip
                                ? AppTheme.secondaryColor
                                : AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: isLatestChip
                                  ? AppTheme.secondaryColor
                                  : const Color(0xFF3B4163),
                            ),
                          ),
                          child: Text(
                            '$ballNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isLatestChip
                                  ? AppTheme.primaryDark
                                  : Colors.white,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMasterBoard(Set<int> calledSet, {MptGame? game}) {
    final isFlash =
        game?.isFlashHousie == true && game?.flashHousieConfig != null;
    final activeFlashCycle = game?.flashHousieConfig?.activeCycleSpec;
    final maxPool = isFlash ? (activeFlashCycle?.drawPool.length ?? 8) : 90;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isFlash
                      ? 'Master Board (1–90) • ${activeFlashCycle?.roundBadgeLabel ?? "Round"}'
                      : 'Master Board (1–90)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${calledSet.length}/$maxPool Called',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.secondaryColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 90,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1.42,
                crossAxisSpacing: 2.5,
                mainAxisSpacing: 2.5,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled
                        ? AppTheme.accentSuccess
                        : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isCalled
                          ? AppTheme.accentSuccess
                          : const Color(0xFF2E334D),
                      width: 0.9,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isCalled
                            ? Colors.white
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _formatPrizeGiftDetail(MptGame? game, String prizeKey) {
    if (game == null) return null;
    final raw = game.prizeGiftsConfig[prizeKey];
    if (raw is! Map) return null;
    final title = (raw['title'] ?? raw['brand_name'] ?? '').toString().trim();
    final val = (raw['prize_value'] as num?)?.toDouble() ?? 0.0;
    final sym =
        (raw['currency_symbol'] ?? game.prizeGiftsConfig['_currency_symbol'] ?? '₹')
            .toString()
            .trim();
    final valStr = val > 0
        ? '$sym${val == val.roundToDouble() ? val.toInt() : val.toStringAsFixed(2)}'
        : '';
    if (title.isNotEmpty && valStr.isNotEmpty) {
      return '🎁 $title ($valStr)';
    }
    if (title.isNotEmpty) return '🎁 $title';
    if (valStr.isNotEmpty) return '🎁 Prize Value: $valStr';
    return null;
  }

  Widget _buildClaimsQueue(
    AsyncValue<List<MptClaim>> claimsStream,
    Map<String, MptRegistration> regMap, {
    MptGame? game,
    List<String> activePrizes = const [],
  }) {
    final hostRewardsAsync = ref.watch(hostGameRewardsProvider(widget.gameId));
    final hostRewards = hostRewardsAsync.value ?? [];
    final flashCfg = game?.flashHousieConfig;
    final prizeList = activePrizes.isNotEmpty
        ? activePrizes
        : (game?.prizesConfig ??
              const [
                'EARLY_FIVE',
                'TOP_LINE',
                'MIDDLE_LINE',
                'BOTTOM_LINE',
                'FOUR_CORNERS',
                'FULL_HOUSE',
              ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        claimsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (claims) {
            final approvedClaims = claims
                .where((c) => c.status == 'APPROVED')
                .toList();

            final hasUnclaimed = approvedClaims.any((c) {
              final r = hostRewards
                  .where(
                    (rw) =>
                        rw.claimId == c.id ||
                        (rw.prizeType == c.prizeType && rw.userId == c.userId),
                  )
                  .firstOrNull;
              return r == null || r.isAvailable;
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Prizes & Winners',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    if (approvedClaims.isNotEmpty && hasUnclaimed)
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await ref
                                .read(rewardsRepositoryProvider)
                                .closeGameClaim(
                                  gameId: widget.gameId,
                                  closeAll: true,
                                );
                            ref.invalidate(
                              hostGameRewardsProvider(widget.gameId),
                            );
                            ref.invalidate(myRewardsProvider);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'All prize claims marked as Claimed!',
                                ),
                                backgroundColor: AppTheme.accentSuccess,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to close claims: $e'),
                                backgroundColor: AppTheme.accentDanger,
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.done_all_rounded,
                          size: 16,
                          color: AppTheme.secondaryColor,
                        ),
                        label: const Text(
                          'Close All Claims',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: prizeList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final prizeKey = prizeList[idx];
                    final claim = approvedClaims
                        .where((c) => c.prizeType == prizeKey)
                        .firstOrNull;
                    final flashWinnerUserId =
                        flashCfg?.awardedWinners[prizeKey];
                    final flashWinnerName =
                        flashCfg?.awardedWinnerNames[prizeKey];
                    String? flashScoreSummary =
                        flashCfg?.awardedWinnerScoreSummaries[prizeKey];
                    if ((flashScoreSummary == null ||
                            flashScoreSummary.isEmpty) &&
                        claim?.rejectionReason != null &&
                        claim!.rejectionReason!.trim().startsWith('✓')) {
                      flashScoreSummary = claim.rejectionReason!.trim();
                    }
                    if (flashScoreSummary == null &&
                        prizeKey.startsWith('ROUND_') &&
                        flashCfg != null) {
                      final rNum = int.tryParse(prizeKey.substring(6));
                      final cSpec = flashCfg.cycles
                          .where((c) => c.cycleIndex == rNum)
                          .firstOrNull;
                      if (cSpec?.winnerCorrectCount != null) {
                        final reactSec = ((cSpec?.winnerReactionMs ?? 0) / 1000)
                            .toStringAsFixed(1);
                        flashScoreSummary =
                            '✓ ${cSpec!.winnerCorrectCount}/${flashCfg.cellsPerQuadrant} Recalled  •  ⚡ ${reactSec}s';
                      }
                    }

                    final isWon =
                        claim != null ||
                        (flashWinnerUserId != null &&
                            flashWinnerUserId.isNotEmpty);
                    final giftDetail = _formatPrizeGiftDetail(game, prizeKey);

                    if (isWon) {
                      final winnerUserId =
                          claim?.userId ?? flashWinnerUserId ?? '';
                      final playerReg = regMap[winnerUserId];
                      final displayName =
                          (playerReg?.displayName.isNotEmpty == true)
                          ? playerReg!.displayName
                          : (flashWinnerName != null &&
                                flashWinnerName.isNotEmpty)
                          ? flashWinnerName
                          : (claim?.userName != null &&
                                claim!.userName != 'Player')
                          ? claim.userName!
                          : 'Player';
                      final avatar =
                          playerReg?.avatar ?? claim?.userAvatar ?? 'avatar_1';
                      final matchedReward = hostRewards
                          .where(
                            (rw) =>
                                (claim != null && rw.claimId == claim.id) ||
                                (rw.prizeType == prizeKey &&
                                    rw.userId == winnerUserId),
                          )
                          .firstOrNull;
                      final isClaimed = matchedReward?.isClaimed ?? false;

                      return Card(
                        color: AppTheme.accentSuccess.withValues(alpha: 0.14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isClaimed
                                ? const Color(0xFF2E334D)
                                : AppTheme.accentSuccess,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryColor.withValues(
                                    alpha: 0.2,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.secondaryColor,
                                    width: 1.4,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  Formatters.getAvatarEmoji(avatar),
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🏆 ${Formatters.formatPrizeName(prizeKey, cellsPerQuadrant: flashCfg?.cellsPerQuadrant)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (giftDetail != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        giftDetail,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.secondaryColor,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Won by: $displayName',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.accentSuccess,
                                      ),
                                    ),
                                    if (flashScoreSummary != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        flashScoreSummary,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.secondaryColor,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      matchedReward != null
                                          ? 'Ref: ${matchedReward.claimReference}'
                                          : (claim != null
                                                ? 'Verified • ${Formatters.formatShortDate(claim.submittedAt)}'
                                                : 'Verified FlashHousie™ Standings'),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (claim != null) ...[
                                const SizedBox(width: 8),
                                isClaimed
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: const Text(
                                          '✓ CLAIMED',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(rewardsRepositoryProvider)
                                                .closeGameClaim(
                                                  gameId: widget.gameId,
                                                  rewardId: matchedReward?.id,
                                                  claimId: claim.id,
                                                );
                                            ref.invalidate(
                                              hostGameRewardsProvider(
                                                widget.gameId,
                                              ),
                                            );
                                            ref.invalidate(myRewardsProvider);
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Marked ${Formatters.formatPrizeName(prizeKey, cellsPerQuadrant: flashCfg?.cellsPerQuadrant)} ($displayName) as Claimed!',
                                                ),
                                                backgroundColor:
                                                    AppTheme.accentSuccess,
                                              ),
                                            );
                                          } catch (e) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Failed to close claim: $e',
                                                ),
                                                backgroundColor:
                                                    AppTheme.accentDanger,
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 15,
                                        ),
                                        label: const Text('Close Claim'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.accentSuccess,
                                          foregroundColor: Colors.white,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    // Prize not yet won — show rich open prize card with larger font
                    String openStatusText = '🟢 Open for Claims';
                    Color openStatusColor = const Color(0xFF38BDF8);
                    if (flashCfg != null) {
                      if (prizeKey.startsWith('ROUND_')) {
                        final rNum = int.tryParse(prizeKey.substring(6)) ?? 1;
                        if (rNum == flashCfg.currentCycle &&
                            game?.status != 'COMPLETED') {
                          openStatusText =
                              '⚡ Round $rNum Live Now — Top Recall Accuracy + Speed Wins';
                          openStatusColor = AppTheme.secondaryColor;
                        } else if (rNum > flashCfg.currentCycle) {
                          openStatusText = '⏳ Upcoming Round $rNum Prize';
                          openStatusColor = const Color(0xFF94A3B8);
                        } else {
                          openStatusText = '🏁 Round $rNum Concluded';
                          openStatusColor = const Color(0xFF94A3B8);
                        }
                      } else if (prizeKey == 'FULL_HOUSE' ||
                          prizeKey == 'SECOND_FULL_HOUSE') {
                        openStatusText =
                            '🏆 Crowned after Round ${flashCfg.totalCycles} (Cumulative Recall + Speed)';
                        openStatusColor = AppTheme.secondaryColor;
                      }
                    }

                    return Card(
                      color: AppTheme.darkSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFF2E334D)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.22,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryLight.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.emoji_events_outlined,
                                color: AppTheme.secondaryColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Formatters.formatPrizeName(
                                      prizeKey,
                                      cellsPerQuadrant:
                                          flashCfg?.cellsPerQuadrant,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (giftDetail != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      giftDetail,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.secondaryColor,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    openStatusText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: openStatusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
