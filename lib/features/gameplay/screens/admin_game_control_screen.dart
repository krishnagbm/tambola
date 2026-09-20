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
  ConsumerState<AdminGameControlScreen> createState() => _AdminGameControlScreenState();
}

class _AdminGameControlScreenState extends ConsumerState<AdminGameControlScreen> {
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

  @override
  void initState() {
    super.initState();
    _isMuted = TambolaAudioCaller().isMuted;
    if (widget.autoPilot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAutoPilot();
      });
    }
  }

  @override
  void dispose() {
    _autoCallTimer?.cancel();
    _celebrationTimer?.cancel();
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
      if (!_isAutoPilotEnabled) {
        timer.cancel();
        return;
      }
      // If celebrating a winner or currently making an async call or paused, hold the countdown
      if (_celebrationSecondsLeft > 0 || _isCalling || _isAutoPilotPaused) {
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
    final text = '🎉 You are invited to play DabHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to join directly on web or in app:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  Future<void> _handleCallNext() async {
    setState(() {
      _isCalling = true;
      _countdownSecondsLeft = _autoCallIntervalSeconds;
    });
    try {
      final num = await ref.read(gameplayRepositoryProvider).callNextNumber(widget.gameId);
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
          const SnackBar(content: Text('All 90 numbers have been called! Game completed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calling number: $e'), backgroundColor: AppTheme.accentDanger),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game concluded successfully! Final results published.')),
      );
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to end game: $e'), backgroundColor: AppTheme.accentDanger),
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
        title: const Text('Edit Event Name', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  await ref.read(gameRepositoryProvider).updateGameName(widget.gameId, newName);
                  ref.invalidate(gameStreamProvider(widget.gameId));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Event name updated successfully!')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update event name: $e'), backgroundColor: AppTheme.accentDanger),
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
      await ref.read(gameRepositoryProvider).increaseCapacity(
            gameId: widget.gameId,
            additionalCapacity: extraCapacity,
          );
      ref.invalidate(gameStreamProvider(widget.gameId));
      ref.invalidate(registrationsStreamProvider(widget.gameId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room capacity expanded by +$extraCapacity seats! Waiting players promoted automatically. 🚀'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error expanding capacity: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  void _showCapacityUpgradeDialog(BuildContext context, MptGame? game, int waitingCount) {
    final currentCap = game?.fundedCapacity ?? 5;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.upgrade_rounded, color: AppTheme.secondaryColor, size: 28),
            SizedBox(width: 8),
            Text('Switch Plan / Add Seats', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Room Capacity: $currentCap Seats',
              style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1), fontWeight: FontWeight.bold),
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
                    const Icon(Icons.info_outline, size: 18, color: AppTheme.accentWarning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$waitingCount player${waitingCount > 1 ? "s are" : " is"} waiting in the overflow queue and will be promoted immediately upon adding seats.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFFDE68A)),
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
                _buildCapacityOptionButton(ctx, '+5 Seats', 5, isRecommended: waitingCount > 0 && waitingCount <= 5),
                _buildCapacityOptionButton(ctx, '+10 Seats', 10, isRecommended: waitingCount > 5 && waitingCount <= 10),
                _buildCapacityOptionButton(ctx, '+15 Seats', 15, isRecommended: waitingCount > 10 && waitingCount <= 15),
                _buildCapacityOptionButton(ctx, '+25 Seats', 25, isRecommended: waitingCount > 15 && waitingCount <= 25),
                _buildCapacityOptionButton(ctx, '+50 Seats', 50, isRecommended: waitingCount > 25),
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

  Widget _buildCapacityOptionButton(BuildContext ctx, String label, int seats, {bool isRecommended = false}) {
    return ElevatedButton(
      onPressed: () {
        Navigator.pop(ctx);
        _handleExpandCapacity(seats);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isRecommended ? AppTheme.secondaryColor : AppTheme.darkSurface,
        foregroundColor: isRecommended ? AppTheme.primaryDark : Colors.white,
        side: BorderSide(color: isRecommended ? AppTheme.secondaryColor : const Color(0xFF3B4163)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isRecommended ? AppTheme.primaryDark : Colors.white),
      ),
    );
  }

  void _showPlayersModal(BuildContext context, List<MptRegistration> registrations, MptGame? game) {
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
                      const Icon(Icons.groups_rounded, color: AppTheme.secondaryColor, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Joined Players (${confirmed.length} / $capacity)',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                          const Icon(Icons.info_outline, color: AppTheme.accentWarning, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${waiting.length} player(s) in lobby over $capacity limit.',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFFDE68A)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showCapacityUpgradeDialog(context, game, waiting.length);
                            },
                            icon: const Icon(Icons.upgrade_rounded, size: 14),
                            label: const Text('Upgrade Plan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentWarning,
                              foregroundColor: AppTheme.primaryDark,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (game != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                const Text('INVITE CODE', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                                Text(
                                  game.inviteCode,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppTheme.secondaryColor),
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
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                const Icon(Icons.person_outline, size: 48, color: Color(0xFF64748B)),
                                const SizedBox(height: 12),
                                const Text(
                                  'No players have joined yet',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Share the invite code or direct link with your players so they can get their tickets.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                ),
                                const SizedBox(height: 16),
                                if (game != null)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _handleShareInvite(game);
                                    },
                                    icon: const Icon(Icons.share_rounded, size: 18),
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
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess, letterSpacing: 0.8),
                                ),
                                const SizedBox(height: 8),
                                ...confirmed.map((r) => _buildPlayerTile(r, isConfirmed: true)),
                                const SizedBox(height: 16),
                              ],
                              if (waiting.isNotEmpty) ...[
                                Text(
                                  'WAITING ROOM PLAYERS (${waiting.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentWarning, letterSpacing: 0.8),
                                ),
                                const SizedBox(height: 8),
                                ...waiting.map((r) => _buildPlayerTile(r, isConfirmed: false)),
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
        border: Border.all(color: isConfirmed ? const Color(0xFF2E334D) : AppTheme.accentWarning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isConfirmed ? AppTheme.primaryColor.withValues(alpha: 0.3) : AppTheme.accentWarning.withValues(alpha: 0.2),
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
                    color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.darkSurface, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.6),
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
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Ticket #${r.registrationSeq}',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${isConfirmed ? "Live" : "Waiting"}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
              color: isConfirmed ? AppTheme.accentSuccess.withValues(alpha: 0.2) : AppTheme.accentWarning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isConfirmed ? 'CONFIRMED' : 'WAITING',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isConfirmed ? AppTheme.accentSuccess : AppTheme.accentWarning,
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
    final activePrizes = game?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'];
    final claims = claimsStream.value ?? [];
    final approvedClaimsList = claims.where((c) => c.status == 'APPROVED').toList();
    final approvedClaimPrizes = approvedClaimsList.map((c) => c.prizeType).toSet();
    final allPrizesWon = activePrizes.isNotEmpty && activePrizes.every((p) => approvedClaimPrizes.contains(p));

    if (_knownApprovedCount == -1) {
      _knownApprovedCount = approvedClaimsList.length;
    } else if (approvedClaimsList.length > _knownApprovedCount) {
      final latestClaim = approvedClaimsList.first;
      _knownApprovedCount = approvedClaimsList.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _triggerCelebrationPause('Player "${latestClaim.userName ?? 'Player'}" won ${Formatters.formatPrizeName(latestClaim.prizeType)}!');
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
        title: const Text('Organizer Game Control'),
        actions: [
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: _isMuted ? Colors.grey : AppTheme.secondaryColor),
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
              icon: const Icon(Icons.share_rounded, color: AppTheme.secondaryColor),
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
            onPressed: () => LiveDisplayHelper.showDisplayOnTvDialog(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(calledNumbersStreamProvider(widget.gameId));
              ref.invalidate(claimsStreamProvider(widget.gameId));
              ref.invalidate(gameStreamProvider(widget.gameId));
              ref.invalidate(registrationsStreamProvider(widget.gameId));
            },
          ),
        ],
      ),
      body: calledStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (calledNumbers) {
          final latest = calledNumbers.isNotEmpty ? calledNumbers.last.number : null;
          final calledSet = calledNumbers.map((e) => e.number).toSet();
          final isMaxNumbers = calledNumbers.length >= 90;
          final disableCalling = _isCalling || isMaxNumbers || allPrizesWon || isGameCompleted || (_celebrationSecondsLeft > 0);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final is3Column = constraints.maxWidth >= 1080;
                    final is2Column = constraints.maxWidth >= 750 && constraints.maxWidth < 1080;

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
                                if (calledNumbers.isEmpty && !isGameCompleted) ...[
                                  _buildPreGameBanner(game, confirmedPlayers.length),
                                  const SizedBox(height: 10),
                                ],
                                if (allPrizesWon && !isGameCompleted) ...[
                                  _buildAllPrizesWonBanner(),
                                  const SizedBox(height: 10),
                                ],
                                _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                                const SizedBox(height: 12),
                                _buildClaimsQueue(claimsStream),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: isGameCompleted ? null : _handleEndGame,
                                  icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                                  label: Text(
                                    isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                                    style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                                _buildCallerHeader(latest, calledNumbers.length, calledNumbers),
                                const SizedBox(height: 8),
                                _buildMainActionButton(
                                  isGameCompleted: isGameCompleted,
                                  allPrizesWon: allPrizesWon,
                                  isMaxNumbers: isMaxNumbers,
                                  calledCount: calledNumbers.length,
                                  disableCalling: disableCalling,
                                  verticalPadding: 13,
                                  fontSize: 15,
                                  iconSize: 24,
                                ),
                                const SizedBox(height: 8),
                                _buildMasterBoard(calledSet),
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
                                    child: _buildConfirmedPlayersSidebarCard(game, confirmedPlayers, capacity),
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    flex: 2,
                                    child: _buildWaitingPlayersSidebarCard(game, waitingPlayers, capacity),
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
                          _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                          const SizedBox(height: 12),
                          if (allPrizesWon && !isGameCompleted) ...[
                            _buildAllPrizesWonBanner(),
                            const SizedBox(height: 14),
                          ],
                          if (calledNumbers.isEmpty && !isGameCompleted) ...[
                            _buildPreGameBanner(game, confirmedPlayers.length),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (_celebrationSecondsLeft > 0)
                                      _buildCelebrationPauseBanner(),
                                    _buildCallerHeader(latest, calledNumbers.length, calledNumbers),
                                    const SizedBox(height: 14),
                                    _buildMainActionButton(
                                      isGameCompleted: isGameCompleted,
                                      allPrizesWon: allPrizesWon,
                                      isMaxNumbers: isMaxNumbers,
                                      calledCount: calledNumbers.length,
                                      disableCalling: disableCalling,
                                      verticalPadding: 18,
                                      fontSize: 17,
                                      iconSize: 28,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildMasterBoard(calledSet),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: isGameCompleted ? null : _handleEndGame,
                                      icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                                      label: Text(
                                        isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                                        style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildClaimsQueue(claimsStream),
                                    const SizedBox(height: 16),
                                    _buildConfirmedPlayersSidebarCard(game, confirmedPlayers, capacity, height: 280),
                                    const SizedBox(height: 12),
                                    _buildWaitingPlayersSidebarCard(game, waitingPlayers, capacity, height: 200),
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
                        _buildGameHeaderAndInviteCard(game, registrations, isGameCompleted),
                        const SizedBox(height: 12),
                        if (allPrizesWon && !isGameCompleted) ...[
                          _buildAllPrizesWonBanner(),
                          const SizedBox(height: 14),
                        ],
                        if (calledNumbers.isEmpty && !isGameCompleted) ...[
                          _buildPreGameBanner(game, confirmedPlayers.length),
                          const SizedBox(height: 14),
                        ],
                        if (_celebrationSecondsLeft > 0)
                          _buildCelebrationPauseBanner(),
                        _buildCallerHeader(latest, calledNumbers.length, calledNumbers),
                        const SizedBox(height: 14),
                        _buildMainActionButton(
                          isGameCompleted: isGameCompleted,
                          allPrizesWon: allPrizesWon,
                          isMaxNumbers: isMaxNumbers,
                          calledCount: calledNumbers.length,
                          disableCalling: disableCalling,
                          verticalPadding: 18,
                          fontSize: 17,
                          iconSize: 28,
                        ),
                        const SizedBox(height: 16),
                        _buildMasterBoard(calledSet),
                        const SizedBox(height: 16),
                        _buildClaimsQueue(claimsStream),
                        const SizedBox(height: 16),
                        _buildConfirmedPlayersSidebarCard(game, confirmedPlayers, capacity, height: 280),
                        const SizedBox(height: 12),
                        _buildWaitingPlayersSidebarCard(game, waitingPlayers, capacity, height: 200),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: isGameCompleted ? null : _handleEndGame,
                          icon: const Icon(Icons.flag_outlined, color: AppTheme.accentDanger),
                          label: Text(
                            isGameCompleted ? 'Game Concluded' : 'End Game & Conclude Event',
                            style: TextStyle(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isGameCompleted ? Colors.grey : AppTheme.accentDanger),
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

  Widget _buildMainActionButton({
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
        label: Text('🏁 Game Concluded', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: const Color(0xFF222639),
          disabledForegroundColor: const Color(0xFF718096),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              : '🏁 All 90 Numbers Called — End & Conclude Event',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentDanger,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
      );
    }

    final isCelebrating = _celebrationSecondsLeft > 0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isAutoPilotEnabled ? AppTheme.secondaryColor.withValues(alpha: 0.6) : const Color(0xFF2E334D),
          width: _isAutoPilotEnabled ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Host Mode Selector Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isAutoPilotEnabled ? null : () => _startAutoPilot(),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isAutoPilotEnabled ? AppTheme.secondaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: _isAutoPilotEnabled
                            ? [
                                BoxShadow(
                                  color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.smart_toy_rounded,
                            size: 17,
                            color: _isAutoPilotEnabled ? AppTheme.primaryDark : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '🤖 Auto-Pilot Host',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isAutoPilotEnabled ? AppTheme.primaryDark : const Color(0xFF94A3B8),
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
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isAutoPilotEnabled ? AppTheme.primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_none_rounded,
                            size: 17,
                            color: !_isAutoPilotEnabled ? Colors.white : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '🎙️ Live Master Host',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: !_isAutoPilotEnabled ? Colors.white : const Color(0xFF94A3B8),
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
          const SizedBox(height: 12),

          // 2. Body based on Selected Mode
          if (_isAutoPilotEnabled) ...[
            // ----------------------------------------------------
            // AUTO-PILOT ACTIVE PANEL
            // ----------------------------------------------------
            // Pace Selector & Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, size: 16, color: AppTheme.secondaryColor),
                    const SizedBox(width: 6),
                    Text(
                      'Calling Pace: ${_autoCallIntervalSeconds}s / ball',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildPacePresetChip('8s Fast', 8),
                    const SizedBox(width: 4),
                    _buildPacePresetChip('15s Std', 15),
                    const SizedBox(width: 4),
                    _buildPacePresetChip('20s Slow', 20),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.secondaryColor,
                inactiveTrackColor: const Color(0xFF1E293B),
                thumbColor: AppTheme.secondaryColor,
                overlayColor: AppTheme.secondaryColor.withValues(alpha: 0.2),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _autoCallIntervalSeconds.toDouble(),
                min: 5,
                max: 30,
                divisions: 25,
                label: '${_autoCallIntervalSeconds}s',
                onChanged: (val) => _updateAutoCallInterval(val.round()),
              ),
            ),
            const SizedBox(height: 4),

            // Live Countdown Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCelebrating
                      ? AppTheme.secondaryColor.withValues(alpha: 0.5)
                      : _isAutoPilotPaused
                          ? AppTheme.accentWarning.withValues(alpha: 0.5)
                          : const Color(0xFF1E293B),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCelebrating
                                ? Icons.celebration_rounded
                                : _isAutoPilotPaused
                                    ? Icons.pause_circle_outline_rounded
                                    : _isCalling
                                        ? Icons.autorenew_rounded
                                        : Icons.timer_outlined,
                            size: 16,
                            color: isCelebrating
                                ? AppTheme.secondaryColor
                                : _isAutoPilotPaused
                                    ? AppTheme.accentWarning
                                    : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isCelebrating
                                ? '🎉 Winner Spotlight Pause (${_celebrationSecondsLeft}s)'
                                : _isAutoPilotPaused
                                    ? '⏸️ Auto-Pilot Paused'
                                    : _isCalling
                                        ? '⚡ Selecting & Announcing Number...'
                                        : '⚡ Next number in ${_countdownSecondsLeft}s',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isCelebrating
                                  ? AppTheme.secondaryColor
                                  : _isAutoPilotPaused
                                      ? AppTheme.accentWarning
                                      : Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        isCelebrating
                            ? '${_celebrationSecondsLeft}s'
                            : _isAutoPilotPaused
                                ? 'PAUSED'
                                : '${_countdownSecondsLeft}s',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCelebrating
                              ? AppTheme.secondaryColor
                              : _isAutoPilotPaused
                                  ? AppTheme.accentWarning
                                  : const Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isCelebrating
                          ? (_celebrationSecondsLeft / 10.0).clamp(0.0, 1.0)
                          : _isAutoPilotPaused
                              ? 1.0
                              : ((_autoCallIntervalSeconds - _countdownSecondsLeft) / _autoCallIntervalSeconds).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFF1E293B),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCelebrating
                            ? AppTheme.secondaryColor
                            : _isAutoPilotPaused
                                ? AppTheme.accentWarning
                                : const Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Action Buttons Bar
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isAutoPilotPaused)
                      ElevatedButton.icon(
                        onPressed: _resumeAutoPilot,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Resume Auto-Pilot'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSuccess,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _pauseAutoPilot,
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: const Text('Pause Auto-Pilot'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: disableCalling ? null : _handleCallNext,
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('Draw Ball Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _stopAutoPilot,
                  icon: const Icon(Icons.mic_none_rounded, size: 16),
                  label: const Text('Manual Mode'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF94A3B8),
                    visualDensity: VisualDensity.compact,
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
                icon: Icon(Icons.celebration_rounded, size: iconSize, color: AppTheme.secondaryColor),
                label: Text(
                  '🎉 Celebrating Winner... (${_celebrationSecondsLeft}s)',
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                ),
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFF222639),
                  disabledForegroundColor: AppTheme.secondaryColor,
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.secondaryColor, width: 1.5),
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
                        calledCount == 0 ? 'CALL FIRST NUMBER' : 'CALL NEXT NUMBER',
                        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentSuccess,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF222639),
                  disabledForegroundColor: const Color(0xFF718096),
                  padding: EdgeInsets.symmetric(vertical: verticalPadding),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            const SizedBox(height: 10),
            // Switch to Auto-Pilot prompt card
            InkWell(
              onTap: () => _startAutoPilot(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 18, color: AppTheme.secondaryColor),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Want hands-free calling? Switch to Auto-Pilot Host to draw numbers automatically every 15s.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Launch Auto',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
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
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondaryColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? AppTheme.secondaryColor : const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppTheme.primaryDark : const Color(0xFF94A3B8),
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
          const Row(
            children: [
              Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Prizes Won! 🏆',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.secondaryColor),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'All configured prizes have approved winners. Number calling is concluded. Tap below to finalize and publish results.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _handleEndGame,
            icon: const Icon(Icons.flag_rounded, size: 18),
            label: const Text('End Game & Conclude Event', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedPlayersSidebarCard(MptGame? game, List<MptRegistration> confirmed, int capacity, {double? height}) {
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
              const Icon(Icons.groups_rounded, color: AppTheme.secondaryColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirmed Players (${confirmed.length}/$capacity)',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (game != null)
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 16, color: AppTheme.secondaryColor),
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
                          const Icon(Icons.person_add_alt_1_rounded, size: 32, color: Color(0xFF64748B)),
                          const SizedBox(height: 8),
                          const Text(
                            'No players joined yet',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Share your invite code or link with players.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      children: confirmed.map((r) => _buildPlayerTile(r, isConfirmed: true)).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingPlayersSidebarCard(MptGame? game, List<MptRegistration> waiting, int capacity, {double? height}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: waiting.isNotEmpty ? AppTheme.accentWarning.withValues(alpha: 0.6) : const Color(0xFF2E334D),
          width: waiting.isNotEmpty ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: AppTheme.accentWarning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting Room (${waiting.length})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.upgrade_rounded, size: 18, color: AppTheme.secondaryColor),
                tooltip: 'Switch Plan / Add Seats',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(),
                onPressed: () => _showCapacityUpgradeDialog(context, game, waiting.length),
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
                border: Border.all(color: AppTheme.accentWarning.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.accentWarning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${waiting.length} player(s) waiting over $capacity limit.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFFDE68A), fontWeight: FontWeight.w600),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _showCapacityUpgradeDialog(context, game, waiting.length),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentWarning,
                      foregroundColor: AppTheme.primaryDark,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: const Text('Add Seats', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                          Icon(Icons.check_circle_outline_rounded, size: 28, color: AppTheme.accentSuccess.withValues(alpha: 0.7)),
                          const SizedBox(height: 6),
                          const Text(
                            'Lobby queue is clear',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'All joined players currently have confirmed tickets.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 6),
                      children: waiting.map((r) => _buildPlayerTile(r, isConfirmed: false)).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameHeaderAndInviteCard(MptGame? game, List<MptRegistration> registrations, bool isGameCompleted) {
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
          // Top Row: Title, Edit, Status & Tier badges + Players joined (x/y)
          Row(
            children: [
              const Icon(Icons.celebration, size: 22, color: AppTheme.secondaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  game?.name ?? 'DabHousie Event',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryLight),
                tooltip: 'Edit Event Name',
                padding: const EdgeInsets.symmetric(horizontal: 6),
                constraints: const BoxConstraints(),
                onPressed: () => _showEditGameNameDialog(game?.name ?? ''),
              ),
              const SizedBox(width: 6),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isGameCompleted ? const Color(0xFF718096).withValues(alpha: 0.2) : AppTheme.accentSuccess.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isGameCompleted ? 'COMPLETED' : '🟢 LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isGameCompleted ? const Color(0xFFA0AEC0) : AppTheme.accentSuccess,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Capacity Tier Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5), width: 0.8),
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
              const SizedBox(width: 6),
              // Number of Players Joined Badge (x/y)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  '👥 $confirmedCount/$capacity Joined',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Switch Plan / Add Seats Chip
              InkWell(
                onTap: () => _showCapacityUpgradeDialog(context, game, waitingCount),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.secondaryColor, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upgrade_rounded, size: 13, color: AppTheme.secondaryColor),
                      SizedBox(width: 2),
                      Text(
                        '+ Seats',
                        style: TextStyle(
                          fontSize: 10,
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
          const SizedBox(height: 14),

          // Message when no players have joined yet
          if (registrations.isEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ROOM INVITE CODE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
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
                        const Icon(Icons.copy_rounded, size: 16, color: AppTheme.secondaryColor),
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
                      onPressed: () => _showCapacityUpgradeDialog(context, game, waitingCount),
                      icon: const Icon(Icons.upgrade_rounded, size: 16),
                      label: const Text('Switch Plan / Add Seats'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: game != null ? () => _handleShareInvite(game) : null,
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share Invite'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: AppTheme.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _handleCopyLink(inviteCode),
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy Link'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF475569)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/admin-lobby/${widget.gameId}'),
                      icon: const Icon(Icons.meeting_room_outlined, size: 16),
                      label: const Text('Lobby View'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_outlined, color: AppTheme.accentSuccess, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Game is Ready to Start! 🎲',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess),
                ),
                const SizedBox(height: 2),
                Text(
                  confirmedCount > 0
                      ? '$confirmedCount players are in the game. When everyone is ready with their tickets, tap "CALL FIRST NUMBER" below to begin!'
                      : 'Invite your players first. When they have joined, tap "CALL FIRST NUMBER" below to begin drawing balls.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
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
          const Icon(Icons.celebration_rounded, color: AppTheme.secondaryColor, size: 24),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  Widget _buildCallerHeader(int? latest, int totalCalled, [List<MptCalledNumber>? calledNumbers]) {
    final recent = (calledNumbers != null && calledNumbers.isNotEmpty)
        ? calledNumbers.reversed.skip(1).take(6).toList()
        : <MptCalledNumber>[];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LATEST NUMBER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                  Text(
                    latest != null ? '$latest' : '---',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor, height: 1.1),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$totalCalled / 90', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text('Total Called', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'LAST 6: ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.secondaryColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: recent.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF3B4163)),
                          ),
                          child: Text(
                            '${item.number}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

  Widget _buildMasterBoard(Set<int> calledSet) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Master Board (1–90)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  '${calledSet.length} Called',
                  style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
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
                childAspectRatio: 1.18,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (ctx, idx) {
                final num = idx + 1;
                final isCalled = calledSet.contains(num);
                return Container(
                  decoration: BoxDecoration(
                    color: isCalled ? AppTheme.accentSuccess : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isCalled ? AppTheme.accentSuccess : const Color(0xFF2E334D), width: 0.8),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCalled ? Colors.white : const Color(0xFFA0AEC0),
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

  Widget _buildClaimsQueue(AsyncValue<List<MptClaim>> claimsStream) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prize Claims & Winners', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        claimsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (claims) {
            final approvedClaims = claims.where((c) => c.status == 'APPROVED').toList();

            if (approvedClaims.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('No approved winners yet. Announce prizes to your players!')),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: approvedClaims.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final claim = approvedClaims[idx];
                return Card(
                  color: AppTheme.accentSuccess.withOpacity(0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.accentSuccess, width: 1.2),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.secondaryColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        Formatters.getAvatarEmoji(claim.userAvatar),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    title: Text(
                      '🏆 ${Formatters.formatPrizeName(claim.prizeType)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          'Won by: ${claim.userName ?? "Player"}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentSuccess),
                        ),
                        Text(
                          'Verified • ${Formatters.formatShortDate(claim.submittedAt)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSuccess.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('APPROVED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.accentSuccess)),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
