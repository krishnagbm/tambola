import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
import '../../../providers/app_providers.dart';
import '../../game_setup/widgets/schedule_game_dialog.dart';
import '../widgets/player_lobby_showcase_player.dart';

class RegistrationStatusScreen extends ConsumerWidget {
  final String gameId;

  const RegistrationStatusScreen({super.key, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameStream = ref.watch(gameStreamProvider(gameId));
    final regStream = ref.watch(registrationsStreamProvider(gameId));
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Status',
        showBackButton: true,
        onRefresh: () {
          ref.invalidate(gameStreamProvider(gameId));
          ref.invalidate(registrationsStreamProvider(gameId));
        },
      ),
      body: gameStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading game: $err')),
        data: (game) {
          // If game has started, automatically direct to player ticket
          if (game.isInProgress) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.go('/play/$gameId');
              }
            });
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: regStream.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading registration: $err')),
                data: (registrations) {
                  final myReg = registrations.where((r) => r.userId == user?.id).firstOrNull;

                  if (game.isCancelled) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            game.name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Invite Code: ${game.inviteCode}',
                            style: const TextStyle(fontSize: 14, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          _buildCancelledCard(context, myReg, game),
                          const SizedBox(height: 20),
                          _buildAdBannerSlot(isCancelled: true),
                        ],
                      ),
                    );
                  }

                  if (myReg == null) {
                    return _buildNotRegisteredState(context);
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Game Info
                        Text(
                          game.name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Invite Code: ${game.inviteCode}',
                          style: const TextStyle(fontSize: 14, color: AppTheme.secondaryColor, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        if (game.effectiveScheduledAt != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.access_time, size: 16, color: AppTheme.primaryLight),
                                const SizedBox(width: 6),
                                Text(
                                  'Scheduled: ${Formatters.formatShortDate(game.effectiveScheduledAt!)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryLight),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Unambiguous Status Card (Cancelled vs Concluded vs Confirmed vs Waiting)
                        if (game.isCancelled) ...[
                          _buildCancelledCard(context, myReg, game),
                        ] else if (game.isCompleted || game.status == 'COMPLETED') ...[
                          _buildConcludedCard(context, myReg, game),
                        ] else if (myReg.isConfirmed) ...[
                          _buildConfirmedCard(context, ref, myReg, game, registrations),
                        ] else ...[
                          _buildWaitingCard(context, ref, myReg, game, registrations),
                        ],

                        const SizedBox(height: 20),

                        // Interactive Lobby Showcase Player ("How to Play" + "How to Host") while waiting
                        if (!game.isCompleted &&
                            game.status != 'COMPLETED' &&
                            !game.isCancelled) ...[
                          const PlayerLobbyShowcasePlayer(),
                          const SizedBox(height: 20),
                        ],

                        // Sponsor / Ad Banner Slot (Item 3)
                        _buildAdBannerSlot(
                          isCompleted: game.isCompleted || game.status == 'COMPLETED',
                          isCancelled: game.isCancelled,
                        ),
                        const SizedBox(height: 20),

                        // Live Event Capacity Stats Card
                        _buildCapacitySummary(game, registrations),

                        const SizedBox(height: 20),

                        // Live Projector/Display Link
                        OutlinedButton.icon(
                          onPressed: () => LiveDisplayHelper.openInNewWindow(context, gameId),
                          icon: const Icon(Icons.tv),
                          label: Text(game.isCompleted ? 'View Final Board & Winners ↗' : 'Open Live Display / Caller Screen ↗'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdBannerSlot({bool isCompleted = false, bool isCancelled = false}) {
    if (isCancelled || isCompleted) {
      return const SizedBox.shrink();
    }
    return const AdBannerSlot(
      slotType: AdSlotType.videoReward,
      title: 'Sponsored Event Promo',
      subtitle: 'Host your next family reunion or kitty party on DabHousie!',
    );
  }

  Widget _buildCancelledCard(BuildContext context, MptRegistration? reg, MptGame game) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentDanger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentDanger, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentDanger.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cancel_outlined, size: 54, color: AppTheme.accentDanger),
          ),
          const SizedBox(height: 16),
          const Text(
            'EVENT CANCELLED 🚫',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.accentDanger, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This game event ("${game.name}") has been cancelled by the Organizer.\nNo tickets will be issued for this room.',
            style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1), height: 1.4),
            textAlign: TextAlign.center,
          ),
          if (reg != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: Text(
                'Registration #${reg.registrationSeq} Voided',
                style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('Back to Home'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConcludedCard(BuildContext context, MptRegistration reg, MptGame game) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3B4163), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events, size: 54, color: AppTheme.secondaryColor),
          ),
          const SizedBox(height: 16),
          const Text(
            'GAME SESSION CONCLUDED 🏁',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This game was completed on ${game.completedAt != null ? Formatters.formatShortDate(game.completedAt!) : "earlier"}.\nRegistration #${reg.registrationSeq}',
            style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1), height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/play/${game.id}'),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: const Text('View Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/rewards'),
                  icon: const Icon(Icons.wallet_giftcard, size: 18),
                  label: const Text('My Rewards'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleLeaveGame(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: AppTheme.accentDanger),
            SizedBox(width: 8),
            Text('Leave Game Room?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to leave this game room?\n\nYour seat reservation will be released and you will be removed from the organizer\'s player roster.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay in Room'),
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

    if (confirm != true) return;

    try {
      await ref.read(gameRepositoryProvider).leaveGame(gameId);
      ref.invalidate(registrationsStreamProvider(gameId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have left the game room.')),
      );
      context.go('/');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error leaving game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  Future<void> _handleHostStartAnyway(BuildContext context, WidgetRef ref, MptGame game) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.play_circle_fill_rounded, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Start Game Now?'),
          ],
        ),
        content: const Text(
          'Start the live game session immediately with the currently joined players?',
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
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: AppTheme.primaryDark,
            ),
            child: const Text('Start Now'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(gameplayRepositoryProvider).startGame(game.id);
      ref.invalidate(gameStreamProvider(game.id));
      if (!context.mounted) return;
      context.go('/play/${game.id}');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  Future<void> _handleHostCancel(BuildContext context, WidgetRef ref, MptGame game) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppTheme.accentDanger),
            SizedBox(width: 8),
            Text('Cancel Game Event?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this scheduled game?\n\nAll participant registrations will be voided and any locked party credits will be refunded.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Waiting'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Event'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(gameRepositoryProvider).cancelGame(game.id);
      ref.invalidate(gameStreamProvider(game.id));
      ref.invalidate(registrationsStreamProvider(game.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game event has been cancelled.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel game: $e'), backgroundColor: AppTheme.accentDanger),
      );
    }
  }

  Widget _buildConfirmedCard(
    BuildContext context,
    WidgetRef ref,
    MptRegistration reg,
    MptGame game,
    List<MptRegistration> registrations,
  ) {
    final user = ref.watch(currentUserProvider).value;
    final isHost = user?.id != null && user!.id == game.adminUserId;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentSuccess.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentSuccess, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentSuccess.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, size: 54, color: AppTheme.accentSuccess),
          ),
          const SizedBox(height: 16),
          const Text(
            'SEAT CONFIRMED! 🎉',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.accentSuccess, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isHost
                ? 'You are joined as Player & Party Host.\nRegistration #${reg.registrationSeq}'
                : 'You are confirmed for this game.\nRegistration #${reg.registrationSeq}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (game.effectiveScheduledAt != null) ...[
            ScheduledCountdownSection(
              game: game,
              registrations: registrations,
              isHost: isHost,
              onHostStartAnyway: () => _handleHostStartAnyway(context, ref, game),
              onHostCancel: () => _handleHostCancel(context, ref, game),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Waiting for Organizer to start...',
                    style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/play/${game.id}'),
            icon: const Icon(Icons.confirmation_number_outlined, size: 16),
            label: const Text('Preview My Ticket Numbers'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryLight,
              side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _handleLeaveGame(context, ref),
            icon: const Icon(Icons.exit_to_app_rounded, size: 16, color: Color(0xFFEF4444)),
            label: const Text('Leave / Quit Game Room', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingCard(
    BuildContext context,
    WidgetRef ref,
    MptRegistration reg,
    MptGame game,
    List<MptRegistration> registrations,
  ) {
    final user = ref.watch(currentUserProvider).value;
    final isHost = user?.id != null && user!.id == game.adminUserId;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentWarning, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentWarning.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded, size: 54, color: AppTheme.accentWarning),
          ),
          const SizedBox(height: 16),
          const Text(
            'WAITING FOR ORGANIZER CONFIRMATION',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.accentWarning, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'You are registered successfully.\nYour seat is currently waiting for additional capacity.',
            style: TextStyle(fontSize: 14, color: Color(0xFFE2E8F0), height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Text(
              'Your Queue Position: #${reg.registrationSeq}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondaryColor, fontSize: 13),
            ),
          ),
          if (game.effectiveScheduledAt != null) ...[
            const SizedBox(height: 16),
            ScheduledCountdownSection(
              game: game,
              registrations: registrations,
              isHost: isHost,
              onHostStartAnyway: () => _handleHostStartAnyway(context, ref, game),
              onHostCancel: () => _handleHostCancel(context, ref, game),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'You will be notified automatically if the Organizer adds capacity before the game starts.',
            style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => _handleLeaveGame(context, ref),
            icon: const Icon(Icons.exit_to_app_rounded, size: 16, color: Color(0xFFEF4444)),
            label: const Text('Leave / Cancel Waiting Position', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacitySummary(MptGame game, List<MptRegistration> registrations) {
    final confirmedCount = registrations.where((r) => r.isConfirmed).length;
    final waitingCount = registrations.where((r) => r.isWaiting).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live Room Capacity',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Funded Seats', '${game.fundedCapacity}', AppTheme.primaryLight),
                _buildStatItem('Confirmed', '$confirmedCount', AppTheme.accentSuccess),
                _buildStatItem('Waiting', '$waitingCount', AppTheme.accentWarning),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
      ],
    );
  }

  Widget _buildNotRegisteredState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_off_outlined, size: 48, color: Color(0xFFA0AEC0)),
          const SizedBox(height: 12),
          const Text('You are not yet registered for this game.'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/join'),
            child: const Text('Join Game'),
          ),
        ],
      ),
    );
  }
}

class ScheduledCountdownSection extends ConsumerStatefulWidget {
  final MptGame? game;
  final List<MptRegistration> registrations;
  final bool isHost;
  final VoidCallback? onHostStartAnyway;
  final VoidCallback? onHostCancel;

  // Fallback properties for direct parameter instantiation
  final DateTime? scheduledAt;
  final DabbyScheduleConfig? dabbyConfig;

  const ScheduledCountdownSection({
    super.key,
    this.game,
    this.registrations = const [],
    this.isHost = false,
    this.onHostStartAnyway,
    this.onHostCancel,
    this.scheduledAt,
    this.dabbyConfig,
  });

  @override
  ConsumerState<ScheduledCountdownSection> createState() => _ScheduledCountdownSectionState();
}

class _ScheduledCountdownSectionState extends ConsumerState<ScheduledCountdownSection> {
  Timer? _timer;
  bool _decisionEmailDispatched = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tryDispatchDecisionEmail(String gameId, int confirmedCount, int quorumCount, int graceMinutes) {
    if (_decisionEmailDispatched) return;
    _decisionEmailDispatched = true;
    ref.read(gameRepositoryProvider).sendScheduledGameDecisionEmail(
      gameId: gameId,
      confirmedCount: confirmedCount,
      quorumCount: quorumCount,
      gracePeriodMinutes: graceMinutes,
    ).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final scheduledAt = widget.game?.effectiveScheduledAt ??
        widget.scheduledAt ??
        DateTime.now();
    final dabbyConfig = widget.game?.dabbyScheduleConfig ?? widget.dabbyConfig;

    final capacity = widget.game?.fundedCapacity ?? 10;
    final confirmedCount = widget.registrations.where((r) => r.isConfirmed).length;
    final quorumCount = math.max(1, dabbyConfig?.getQuorumCount(capacity) ?? (capacity * 0.67).ceil());
    final graceMinutes = dabbyConfig?.gracePeriodMinutes ?? 5;

    final now = DateTime.now();
    final difference = scheduledAt.difference(now);
    final isPassed = difference.isNegative;
    final isLowQuorum = confirmedCount < quorumCount || confirmedCount < 1;

    final elapsedSeconds = isPassed ? now.difference(scheduledAt).inSeconds : 0;
    final elapsedMinutes = (elapsedSeconds / 60).floor();
    final isGracePassed = isPassed && elapsedMinutes >= graceMinutes;
    final remainingGraceSeconds = isPassed
        ? ((graceMinutes * 60) - elapsedSeconds).clamp(0, graceMinutes * 60)
        : graceMinutes * 60;
    final remainingGraceMinutes = (remainingGraceSeconds / 60).ceil();

    // Auto-dispatch decision email if host is present at kickoff with low quorum
    if (widget.isHost && isPassed && isLowQuorum && widget.game != null) {
      _tryDispatchDecisionEmail(widget.game!.id, confirmedCount, quorumCount, graceMinutes);
    }

    String countdownText;
    Color timerColor;
    if (!isPassed) {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      final seconds = difference.inSeconds % 60;
      if (hours > 0) {
        countdownText = 'Starts in ${hours}h ${minutes}m ${seconds}s';
      } else {
        countdownText = 'Starts in ${minutes}m ${seconds}s';
      }
      timerColor = AppTheme.secondaryColor;
    } else if (!isLowQuorum) {
      countdownText = '🚀 Quorum Reached ($confirmedCount/$quorumCount) • Launching...';
      timerColor = AppTheme.accentSuccess;
    } else if (!isGracePassed) {
      countdownText = '⏳ Grace Buffer Active • ${remainingGraceMinutes}m remaining';
      timerColor = AppTheme.accentWarning;
    } else {
      countdownText = '⚠️ Quorum Buffer Expired • Awaiting Host Decision';
      timerColor = AppTheme.accentDanger;
    }

    final quorumPercent = quorumCount > 0 ? (confirmedCount / quorumCount).clamp(0.0, 1.0) : 1.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.secondaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPassed && isLowQuorum
              ? AppTheme.accentWarning.withValues(alpha: 0.7)
              : AppTheme.secondaryColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Kickoff Time Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.alarm_on_rounded, size: 18, color: AppTheme.secondaryColor),
              const SizedBox(width: 8),
              Text(
                'SCHEDULED: ${Formatters.formatShortDate(scheduledAt)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Attendance & Quorum Progress
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E334D)),
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
                          Icons.groups_rounded,
                          size: 15,
                          color: isLowQuorum ? AppTheme.accentWarning : AppTheme.accentSuccess,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Attendance: $confirmedCount / $quorumCount Players',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLowQuorum
                            ? AppTheme.accentWarning.withValues(alpha: 0.15)
                            : AppTheme.accentSuccess.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLowQuorum ? 'Need ${quorumCount - confirmedCount} more' : 'Quorum Met ✅',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isLowQuorum ? AppTheme.accentWarning : AppTheme.accentSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: quorumPercent,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isLowQuorum ? AppTheme.accentWarning : AppTheme.accentSuccess,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Countdown / State Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: timerColor),
            ),
            child: Text(
              countdownText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: timerColor,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 4. Subtext / Policy Info
          if (isPassed && isLowQuorum && !widget.isHost) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentWarning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⏳ Quorum not reached yet ($confirmedCount of $quorumCount players joined).\nDabby grace buffer is active. Waiting for latecomers or host kickoff.',
                style: const TextStyle(fontSize: 11, color: Color(0xFFFDE68A), height: 1.3),
                textAlign: TextAlign.center,
              ),
            ),
          ] else ...[
            Text(
              dabbyConfig?.isAutonomousHostEnabled == true
                  ? '🤖 Dabby Autonomous Host is active. When countdown completes and quorum is met, the room launches automatically!'
                  : 'The Organizer will launch the game room on or before the scheduled time. When started, you will automatically transition to your live ticket!',
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.35),
              textAlign: TextAlign.center,
            ),
          ],

          // 5. Host Action Controls (If viewer is the organizer)
          if (widget.isHost && widget.game != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded, color: AppTheme.secondaryColor, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Organizer Controls (You are the Host)',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPassed && isLowQuorum
                        ? 'Kickoff time reached with $confirmedCount of $quorumCount players. You can start now with current players, manage via Admin Lobby, or cancel.'
                        : 'Quick actions to manage your scheduled game room:',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isPassed && widget.onHostStartAnyway != null)
                        ElevatedButton.icon(
                          onPressed: widget.onHostStartAnyway,
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('Start Game Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentSuccess,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/admin-lobby/${widget.game!.id}'),
                        icon: const Icon(Icons.dashboard_rounded, size: 15),
                        label: const Text('Admin Lobby'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.secondaryColor,
                          side: const BorderSide(color: AppTheme.secondaryColor),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (widget.onHostCancel != null)
                        TextButton.icon(
                          onPressed: widget.onHostCancel,
                          icon: const Icon(Icons.cancel_outlined, size: 15, color: AppTheme.accentDanger),
                          label: const Text('Cancel Game', style: TextStyle(color: AppTheme.accentDanger, fontSize: 11.5)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

