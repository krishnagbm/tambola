import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/utils/tambola_audio_caller.dart';
import '../../../core/utils/tambola_ticket.dart';
import '../../../core/utils/wake_lock_helper.dart';
import '../../../core/widgets/celebration_overlay.dart';
import '../../../models/mpt_called_number.dart';
import '../../../models/mpt_claim.dart';
import '../../../models/mpt_game.dart';
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
  bool _voiceEnabled = false;
  int _lastAnnouncedSeq = 0;
  bool _showCelebration = false;

  @override
  void initState() {
    super.initState();
    WakeLockHelper.keepScreenOn();
    _loadSavedMarks();
  }

  @override
  void dispose() {
    WakeLockHelper.release();
    super.dispose();
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
    final uncalled = _markedNumbers.where((n) => !calledSet.contains(n)).toList();
    if (uncalled.isNotEmpty) {
      _showBogeyDialog('Invalid Claim: You have marked numbers that have not been called yet: ${uncalled.join(', ')}');
      return;
    }

    // 2. Strict validation: check pattern is complete (Item 15)
    final isPatternValid = TambolaTicketHelper.validatePrizePattern(ticket.matrix, _markedNumbers, prizeType);
    if (!isPatternValid) {
      _showIncompletePatternDialog(prizeType);
      return;
    }

    setState(() => _isClaiming = true);
    try {
      final res = await ref.read(gameplayRepositoryProvider).submitClaim(
            gameId: widget.gameId,
            prizeType: prizeType,
            markedNumbers: _markedNumbers.toList(),
          );

      if (!mounted) return;
      final status = res['status'] as String? ?? 'UNKNOWN';

      if (status == 'APPROVED') {
        final refCode = res['claim_reference'] as String? ?? 'N/A';
        _showWinnerDialog(prizeType, refCode);
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
        SnackBar(content: Text('Claim error: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  void _showWinnerDialog(String prizeType, String claimRef) {
    setState(() => _showCelebration = true);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showCelebration = false);
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 28),
            SizedBox(width: 8),
            Text('WINNER! 🏆', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Congratulations! Your claim for "${Formatters.formatPrizeName(prizeType)}" is APPROVED.',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('Voucher Claim Reference Code:', style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.secondaryColor),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppTheme.secondaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prizes must be claimed directly from your game organizer by presenting this voucher reference or QR code. DabHousie is a gameplay platform and does not distribute prizes.',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade200, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentSuccess,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue Playing (Stay on Game)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/rewards');
            },
            child: const Text('View in Rewards'),
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
            Text('Pattern Incomplete', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Your marked numbers do not yet complete "${Formatters.formatPrizeName(prizeType)}".\nPlease ensure all required numbers for this pattern have been called and marked on your ticket.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
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
            Text('Bogey Claim ⚠️', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          reason,
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveGame() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger, size: 28),
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
        SnackBar(content: Text('Error leaving game: $e'), backgroundColor: AppTheme.accentDanger),
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
    final currentUserId = ref.watch(currentUserProvider).value?.id;

    // Announce number if voice enabled
    if (_voiceEnabled) {
      calledStream.whenData((calledNumbers) {
        if (calledNumbers.isNotEmpty && calledNumbers.length > _lastAnnouncedSeq) {
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
              Text(
                'Code: ${gameStream.value!.inviteCode}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.secondaryColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off, color: _voiceEnabled ? AppTheme.secondaryColor : Colors.grey),
            tooltip: _voiceEnabled ? 'Voice Calling ON' : 'Voice Calling OFF',
            onPressed: () {
              setState(() => _voiceEnabled = !_voiceEnabled);
            },
          ),
          IconButton(
            icon: const Icon(Icons.tv, color: AppTheme.secondaryColor),
            tooltip: 'Live Board (Open in New Tab / Window)',
            onPressed: () => LiveDisplayHelper.openInNewWindow(context, widget.gameId),
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: 'My Rewards',
            onPressed: () => context.push('/rewards'),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger),
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
                const Icon(Icons.error_outline_rounded, color: AppTheme.accentDanger, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load your ticket',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please tap retry to fetch your assigned ticket for this room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.refresh(playerTicketProvider(widget.gameId)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
              final latestCalled = calledNumbers.isNotEmpty ? calledNumbers.last.number : null;
              final calledSet = calledNumbers.map((e) => e.number).toSet();
              final currentGame = gameStream.value;
              final isGameEnded = currentGame?.status == 'COMPLETED' || calledNumbers.length >= 90;
              final activePrizes = currentGame?.prizesConfig ?? ['EARLY_FIVE', 'TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE', 'FOUR_CORNERS', 'FULL_HOUSE'];
              final currentUser = ref.watch(currentUserProvider).value;

              return CelebrationOverlay(
                isCelebrating: _showCelebration,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final orientation = MediaQuery.of(ctx).orientation;
                    final isLandscape = orientation == Orientation.landscape && constraints.maxWidth > 560;

                    if (isLandscape) {
                      // ========================================================
                      // MOBILE LANDSCAPE 2-COLUMN LAYOUT
                      // Left: Player Banner, Latest Call/Ended, Expanded Ticket Matrix
                      // Right: Recent Calls, Prize Claims Panel, Quit Game
                      // ========================================================
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column (Ticket & Current Ball)
                            Expanded(
                              flex: 5,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildPlayerIdentityBanner(currentUser, ticket, game: currentGame, isCompact: true),
                                    const SizedBox(height: 8),
                                    _buildLatestNumberBanner(latestCalled, calledNumbers.length, isGameEnded: isGameEnded, context: context, isCompact: true),
                                    const SizedBox(height: 8),
                                    _buildTicketMatrix(ticket, calledSet, isGameEnded: isGameEnded, cellHeight: 52),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Right Column (Recent Numbers & Prize Claims)
                            Expanded(
                              flex: 4,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (calledNumbers.isNotEmpty) ...[
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
                                      ),
                                      error: (_, __) => _buildPrizeClaimsSection(
                                        activePrizes,
                                        {},
                                        currentUserId,
                                        ticket,
                                        calledSet,
                                        isGameEnded: isGameEnded,
                                        isCompact: true,
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
                                          isCompact: true,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    OutlinedButton.icon(
                                      onPressed: _handleLeaveGame,
                                      icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger, size: 16),
                                      label: const Text('Leave Game Room', style: TextStyle(color: AppTheme.accentDanger, fontSize: 12)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Player Identity & Ticket Number Card
                          _buildPlayerIdentityBanner(currentUser, ticket, game: currentGame),
                          const SizedBox(height: 10),

                          // Latest Called Ball / Game Concluded Banner
                          _buildLatestNumberBanner(latestCalled, calledNumbers.length, isGameEnded: isGameEnded, context: context),
                          const SizedBox(height: 12),

                          // Recent Calls List
                          if (calledNumbers.isNotEmpty && !isGameEnded) ...[
                            _buildRecentCallsBar(calledNumbers),
                            const SizedBox(height: 14),
                          ],

                          // Interactive 3x9 Ticket (Manual marking, no auto-yellow)
                          _buildTicketMatrix(ticket, calledSet, isGameEnded: isGameEnded),
                          const SizedBox(height: 20),

                          // Prize Claims Section
                          claimsStream.when(
                            loading: () => _buildPrizeClaimsSection(
                              activePrizes,
                              {},
                              currentUserId,
                              ticket,
                              calledSet,
                              isGameEnded: isGameEnded,
                            ),
                            error: (_, __) => _buildPrizeClaimsSection(
                              activePrizes,
                              {},
                              currentUserId,
                              ticket,
                              calledSet,
                              isGameEnded: isGameEnded,
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
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: _handleLeaveGame,
                              icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger, size: 18),
                              label: const Text(
                                'Quit / Leave Game Room',
                                style: TextStyle(color: AppTheme.accentDanger, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
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

  Widget _buildPlayerIdentityBanner(MptUser? user, MptTicket ticket, {MptGame? game, bool isCompact = false}) {
    final emoji = Formatters.getAvatarEmoji(user?.avatar);
    final name = (user?.displayName != null && user!.displayName.trim().isNotEmpty)
        ? user.displayName
        : 'Player';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 14, vertical: isCompact ? 6 : 10),
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
                  game != null ? '${game.name} • Code: ${game.inviteCode}' : 'Playing Live Game',
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
              border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.6)),
            ),
            child: Text(
              'Ticket #${ticket.ticketNumber}',
              style: TextStyle(
                fontSize: isCompact ? 11 : 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger, size: 20),
            tooltip: 'Quit Game Room',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _handleLeaveGame,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestNumberBanner(
    int? latestNumber,
    int totalCalled, {
    bool isGameEnded = false,
    BuildContext? context,
    bool isCompact = false,
  }) {
    if (isGameEnded) {
      return Container(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4338CA), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.secondaryColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: AppTheme.secondaryColor.withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.celebration, color: AppTheme.secondaryColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  'GAME CONCLUDED 🎉',
                  style: TextStyle(fontSize: isCompact ? 15 : 18, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor, letterSpacing: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              totalCalled >= 90
                  ? 'All 90 numbers called! Prize claiming is now finalized.'
                  : 'Game concluded! Check your rewards below.',
              style: TextStyle(fontSize: isCompact ? 11.5 : 13, color: Colors.white, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (context != null)
                  ElevatedButton.icon(
                    onPressed: () => context.push('/rewards'),
                    icon: const Icon(Icons.emoji_events, size: 16),
                    label: const Text('View My Rewards 🏆'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: AppTheme.primaryDark,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20, vertical: isCompact ? 10 : 16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppTheme.primaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CURRENT CALL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white70)),
              const SizedBox(height: 2),
              Text(
                latestNumber != null ? '$latestNumber' : 'READY',
                style: TextStyle(fontSize: isCompact ? 32 : 42, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1),
              ),
            ],
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 14, vertical: isCompact ? 6 : 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$totalCalled / 90', style: TextStyle(fontSize: isCompact ? 14 : 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text('Called', style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
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
                fontSize: 15,
                color: idx == 0 ? Colors.black : Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTicketMatrix(MptTicket ticket, Set<int> calledSet, {bool isGameEnded = false, double cellHeight = 48}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.primaryLight, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DABHOUSIE TICKET #${ticket.ticketNumber}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
                Text(
                  isGameEnded ? '${_markedNumbers.length} / 15 Marked (Final)' : '${_markedNumbers.length} / 15 Marked',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 14),
            for (int r = 0; r < 3; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    for (int c = 0; c < 9; c++)
                      Expanded(
                        child: _buildTicketCell(ticket.matrix[r][c], calledSet, isGameEnded: isGameEnded, height: cellHeight),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCell(int numVal, Set<int> calledSet, {bool isGameEnded = false, double height = 48}) {
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
                color: isMarked ? AppTheme.accentSuccess : const Color(0xFF3B4163),
                width: isMarked ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$numVal',
                style: TextStyle(
                  fontSize: height >= 52 ? 18 : 16,
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

  Widget _buildPrizeClaimsSection(
    List<String> activePrizes,
    Map<String, MptClaim> approvedClaims,
    String? currentUserId,
    MptTicket ticket,
    Set<int> calledSet, {
    bool isGameEnded = false,
    bool isCompact = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Claim Winning Prize',
              style: TextStyle(fontSize: isCompact ? 14 : 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (isGameEnded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3B4163)),
                ),
                child: const Text(
                  'CONCLUDED',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFA0AEC0)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isGameEnded
              ? 'Game is over. Prize claiming is closed.'
              : 'Tap when completed. Server will validate your ticket.',
          style: TextStyle(fontSize: isCompact ? 11 : 12, color: const Color(0xFFA0AEC0)),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: isCompact ? 2 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: isCompact ? 2.2 : 2.3,
          children: activePrizes.map((prize) {
            final approvedClaim = approvedClaims[prize];
            final isApproved = approvedClaim != null;
            final isWonByMe = isApproved && approvedClaim.userId == currentUserId;

            if (isApproved) {
              return ElevatedButton(
                onPressed: null, // Disabled
                style: ElevatedButton.styleFrom(
                  backgroundColor: isWonByMe ? AppTheme.accentSuccess.withOpacity(0.2) : Colors.black26,
                  disabledBackgroundColor: isWonByMe ? AppTheme.accentSuccess.withOpacity(0.25) : const Color(0xFF222639),
                  disabledForegroundColor: isWonByMe ? AppTheme.accentSuccess : const Color(0xFF718096),
                  side: BorderSide(color: isWonByMe ? AppTheme.accentSuccess : const Color(0xFF2E334D)),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: TextStyle(fontSize: isCompact ? 11 : 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      isWonByMe ? '🏆 Won by You!' : '✓ Won by ${approvedClaim.userName ?? "Player"}',
                      style: TextStyle(fontSize: isCompact ? 9 : 10, fontWeight: FontWeight.bold, color: isWonByMe ? AppTheme.accentSuccess : const Color(0xFFA0AEC0)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  disabledForegroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFF2E334D)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      Formatters.formatPrizeName(prize),
                      style: TextStyle(fontSize: isCompact ? 11 : 12, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Unclaimed (Game Over)',
                      style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
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
                side: const BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              child: Text(
                Formatters.formatPrizeName(prize),
                style: TextStyle(fontSize: isCompact ? 12 : 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
