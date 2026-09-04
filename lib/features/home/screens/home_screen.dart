import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import '../../auth/widgets/profile_edit_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final hostedGamesState = ref.watch(myHostedGamesProvider);
    final joinedGamesState = ref.watch(myJoinedGamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.casino, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Tambola Multiplayer', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Dashboard',
            onPressed: () {
              ref.invalidate(currentUserProvider);
              ref.invalidate(walletProvider);
              ref.invalidate(myHostedGamesProvider);
              ref.invalidate(myJoinedGamesProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined, color: AppTheme.secondaryColor),
            tooltip: 'My Rewards',
            onPressed: () => context.push('/rewards'),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Organizer Wallet',
            onPressed: () => context.push('/wallet'),
          ),
        ],
      ),
      body: userState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (user) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentUserProvider);
            ref.invalidate(walletProvider);
            ref.invalidate(myHostedGamesProvider);
            ref.invalidate(myJoinedGamesProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // User Profile Banner
                _buildUserProfileCard(context, ref, user),
                const SizedBox(height: 20),

                // Main Action Buttons
                _buildActionCard(
                  context: context,
                  title: 'Join a Game',
                  subtitle: 'Enter an invite code or link to get your ticket and play.',
                  icon: Icons.login_rounded,
                  color: AppTheme.primaryColor,
                  onTap: () => context.push('/join'),
                ),
                const SizedBox(height: 14),

                _buildActionCard(
                  context: context,
                  title: 'Create a Game',
                  subtitle: 'Host an event, invite friends, and manage game capacity.',
                  icon: Icons.add_circle_outline_rounded,
                  color: AppTheme.secondaryColor,
                  isSecondary: true,
                  onTap: () => context.push('/create-game'),
                ),
                const SizedBox(height: 24),

                // Active / Scheduled Games Hosted by Organizer (Items 1, 2)
                _buildHostedGamesSection(context, ref, hostedGamesState),
                const SizedBox(height: 20),

                // Games Joined as Player (Items 7, 8)
                _buildJoinedGamesSection(context, ref, joinedGamesState),
                const SizedBox(height: 20),

                // Organizer Wallet Overview
                _buildWalletPreviewCard(context, ref, walletState),
                const SizedBox(height: 16),

                // Quick Verification Card for Organizers
                _buildAdminVerifyCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileCard(BuildContext context, WidgetRef ref, MptUser user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primaryLight.withOpacity(0.25),
              child: Text(_getAvatarEmoji(user.avatar), style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.displayName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSuccess.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentSuccess.withOpacity(0.4)),
                        ),
                        child: const Text(
                          'Player & Organizer',
                          style: TextStyle(fontSize: 11, color: AppTheme.accentSuccess, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Anonymous ID active • Tap edit to change name/avatar',
                    style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryLight),
              tooltip: 'Edit Profile',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => ProfileEditDialog(currentUser: user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostedGamesSection(BuildContext context, WidgetRef ref, AsyncValue<List<MptGame>> hostedState) {
    return hostedState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (games) {
        if (games.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, color: AppTheme.secondaryColor, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'My Hosted Games (Organizer)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Text(
                  '${games.length} Game${games.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games.take(4).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final game = games[idx];
                final isLive = game.isInProgress;
                final isLobby = game.isLobbyOpen;

                Color statusColor = isLive
                    ? AppTheme.accentSuccess
                    : isLobby
                        ? AppTheme.primaryLight
                        : Colors.grey;

                String statusLabel = isLive
                    ? 'IN PROGRESS (LIVE)'
                    : isLobby
                        ? 'LOBBY OPEN'
                        : 'COMPLETED';

                return Card(
                  color: isLive ? AppTheme.accentSuccess.withOpacity(0.08) : AppTheme.darkCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: statusColor.withOpacity(0.5), width: isLive ? 1.5 : 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                game.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor.withOpacity(0.4)),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Code: ${game.inviteCode}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.secondaryColor),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '• Capacity: ${game.fundedCapacity} Seats',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isLive) ...[
                              ElevatedButton.icon(
                                onPressed: () => context.push('/admin-control/${game.id}'),
                                icon: const Icon(Icons.play_circle_filled, size: 18),
                                label: const Text('Resume Game Controls'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accentSuccess,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                              ),
                            ] else if (isLobby) ...[
                              ElevatedButton.icon(
                                onPressed: () => context.push('/admin-lobby/${game.id}'),
                                icon: const Icon(Icons.meeting_room, size: 18),
                                label: const Text('Open Organizer Lobby'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                              ),
                            ] else ...[
                              OutlinedButton.icon(
                                onPressed: () => context.push('/live-display/${game.id}'),
                                icon: const Icon(Icons.tv, size: 18),
                                label: const Text('View Results'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                              ),
                            ],
                          ],
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
    );
  }

  Widget _buildJoinedGamesSection(BuildContext context, WidgetRef ref, AsyncValue<List<Map<String, dynamic>>> joinedState) {
    return joinedState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (joined) {
        if (joined.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.confirmation_number_outlined, color: AppTheme.primaryLight, size: 20),
                SizedBox(width: 8),
                Text(
                  'My Joined Games (Player)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: joined.take(4).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final reg = joined[idx];
                final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                final gameId = (reg['game_id'] ?? '').toString();
                final gameName = (gameData['name'] ?? 'Tambola Game').toString();
                final gameStatus = (gameData['status'] ?? 'OPEN').toString();
                final seatStatus = (reg['seat_status'] ?? 'CONFIRMED').toString();

                final isLive = gameStatus == 'IN_PROGRESS';
                final isConfirmed = seatStatus == 'CONFIRMED' || seatStatus == 'ELIGIBLE';

                return Card(
                  color: AppTheme.darkSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isLive ? AppTheme.accentSuccess : const Color(0xFF2E334D)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gameName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isLive ? AppTheme.accentSuccess.withOpacity(0.2) : Colors.black26,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isLive ? '🟢 LIVE' : isConfirmed ? 'CONFIRMED' : 'WAITING',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isLive ? AppTheme.accentSuccess : isConfirmed ? AppTheme.primaryLight : AppTheme.accentWarning,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Seq #${reg['registration_seq'] ?? 1}', style: const TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (isLive) {
                              context.push('/play/$gameId');
                            } else {
                              context.push('/game-status/$gameId');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLive ? AppTheme.accentSuccess : AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: Text(isLive ? 'Play Ticket' : 'View Status', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isSecondary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.15),
              AppTheme.darkCard,
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFA0AEC0)),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletPreviewCard(BuildContext context, WidgetRef ref, AsyncValue walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.stars, color: AppTheme.secondaryColor, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Organizer Game Credits',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => context.push('/wallet'),
                  child: const Text('Manage Wallet'),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    walletState.when(
                      loading: () => const Text('Loading...'),
                      error: (_, __) => const Text('10 Credits'),
                      data: (w) => Text(
                        '${Formatters.formatCredits(w.availableCredits)} Credits',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'For hosting games & expanding capacity',
                      style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => context.push('/wallet'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Top Up'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminVerifyCard(BuildContext context) {
    return Card(
      color: AppTheme.darkSurface,
      child: ListTile(
        leading: const Icon(Icons.qr_code_scanner, color: AppTheme.accentInfo),
        title: const Text('Organizer Prize Verification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text('Verify and mark prize vouchers shown by winners', style: TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/verify-reward'),
      ),
    );
  }

  static String _getAvatarEmoji(String avatarKey) {
    switch (avatarKey) {
      case 'avatar_lion':
        return '🦁';
      case 'avatar_tiger':
        return '🐯';
      case 'avatar_crown':
        return '👑';
      case 'avatar_wizard':
        return '🧙';
      case 'avatar_rocket':
        return '🚀';
      case 'avatar_fox':
        return '🦊';
      case 'avatar_panda':
        return '🐼';
      case 'avatar_unicorn':
        return '🦄';
      case 'avatar_cowboy':
        return '🤠';
      case 'avatar_star':
        return '🌟';
      case 'avatar_bullseye':
        return '🎯';
      case 'avatar_rocker':
        return '🎸';
      default:
        return '🦁';
    }
  }
}
