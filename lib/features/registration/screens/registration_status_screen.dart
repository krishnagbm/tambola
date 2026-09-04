import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_registration.dart';
import '../../../providers/app_providers.dart';

class RegistrationStatusScreen extends ConsumerWidget {
  final String gameId;

  const RegistrationStatusScreen({super.key, required this.gameId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameStream = ref.watch(gameStreamProvider(gameId));
    final regStream = ref.watch(registrationsStreamProvider(gameId));
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/'),
        ),
        title: const Text('Registration Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: () {
              ref.invalidate(gameStreamProvider(gameId));
              ref.invalidate(registrationsStreamProvider(gameId));
            },
          ),
        ],
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

          return regStream.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading registration: $err')),
            data: (registrations) {
              final myReg = registrations.where((r) => r.userId == user?.id).firstOrNull;

              if (myReg == null) {
                return _buildNotRegisteredState(context);
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                    if (game.scheduledAt != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primaryLight.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, size: 16, color: AppTheme.primaryLight),
                            const SizedBox(width: 6),
                            Text(
                              'Scheduled: ${Formatters.formatShortDate(game.scheduledAt!)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryLight),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Unambiguous Status Card (Confirmed vs Waiting)
                    if (myReg.isConfirmed) ...[
                      _buildConfirmedCard(context, myReg, game),
                    ] else ...[
                      _buildWaitingCard(context, myReg, game),
                    ],

                    const SizedBox(height: 20),

                    // Sponsor / Ad Banner Slot (Item 3)
                    _buildAdBannerSlot(),
                    const SizedBox(height: 20),

                    // Live Event Capacity Stats Card
                    _buildCapacitySummary(game, registrations),

                    const SizedBox(height: 20),

                    // Live Projector/Display Link
                    OutlinedButton.icon(
                      onPressed: () => context.push('/live-display/$gameId'),
                      icon: const Icon(Icons.tv),
                      label: const Text('Open Live Display / Caller Screen'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAdBannerSlot() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withOpacity(0.1),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.campaign_outlined, color: AppTheme.secondaryColor, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event Sponsor / Game Tip',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                ),
                SizedBox(height: 2),
                Text(
                  'Stay on this screen! Your game ticket will automatically appear the moment the Organizer starts.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedCard(BuildContext context, MptRegistration reg, MptGame game) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentSuccess.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentSuccess, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentSuccess.withOpacity(0.2),
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
            'You are confirmed for this game.\nRegistration #${reg.registrationSeq}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _buildWaitingCard(BuildContext context, MptRegistration reg, MptGame game) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.accentWarning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentWarning, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentWarning.withOpacity(0.2),
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
          const SizedBox(height: 14),
          const Text(
            'You will be notified automatically if the Organizer adds capacity before the game starts.',
            style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            textAlign: TextAlign.center,
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
