import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import '../../auth/widgets/profile_edit_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTabIndex = 0;
  String _playerFilter = 'ALL';
  String _organizerFilter = 'ALL';
  final _emailController = TextEditingController();
  bool _isSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(currentUserProvider);
    ref.invalidate(walletProvider);
    ref.invalidate(myHostedGamesProvider);
    ref.invalidate(myJoinedGamesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final hostedGamesState = ref.watch(myHostedGamesProvider);
    final joinedGamesState = ref.watch(myJoinedGamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.casino, color: AppTheme.secondaryColor),
            const SizedBox(width: 8),
            Text(
              _currentTabIndex == 0
                  ? 'Tambola Multiplayer'
                  : _currentTabIndex == 1
                      ? 'Player Hub'
                      : _currentTabIndex == 2
                          ? 'Organizer Hub'
                          : 'Profile & Settings',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshAll,
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
          onRefresh: () async => _refreshAll(),
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildDashboardTab(context, user, walletState, hostedGamesState, joinedGamesState),
              _buildPlayerTab(context, joinedGamesState),
              _buildOrganizerTab(context, hostedGamesState, walletState),
              _buildProfileTab(context, user, walletState),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        backgroundColor: AppTheme.darkCard,
        indicatorColor: AppTheme.primaryColor.withOpacity(0.35),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppTheme.secondaryColor),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number, color: AppTheme.secondaryColor),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_outlined),
            selectedIcon: Icon(Icons.dashboard_customize, color: AppTheme.secondaryColor),
            label: 'Organizer',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppTheme.secondaryColor),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 0: DASHBOARD / WEB LANDING HOME
  // ==========================================
  Widget _buildDashboardTab(
    BuildContext context,
    MptUser user,
    AsyncValue walletState,
    AsyncValue<List<MptGame>> hostedState,
    AsyncValue<List<Map<String, dynamic>>> joinedState,
  ) {
    // Check if there is any active live game
    final liveJoined = joinedState.value?.where((reg) {
      final g = reg['game'] as Map<String, dynamic>? ?? {};
      return (g['status'] ?? '') == 'IN_PROGRESS';
    }).firstOrNull;

    final liveHosted = hostedState.value?.where((g) => g.isInProgress).firstOrNull;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Player Identity Bar
          _buildUserProfileStrip(context, user, walletState),
          const SizedBox(height: 16),

          // Live Game in Progress Alert Banner
          if (liveJoined != null) ...[
            _buildLiveGameBanner(
              context,
              title: (liveJoined['game']?['name'] ?? 'Live Game').toString(),
              subtitle: 'You are registered in this live session!',
              onTap: () => context.push('/play/${liveJoined['game_id']}'),
            ),
            const SizedBox(height: 16),
          ] else if (liveHosted != null) ...[
            _buildLiveGameBanner(
              context,
              title: liveHosted.name,
              subtitle: 'You are hosting this live session. Tap to resume caller controls.',
              onTap: () => context.push('/admin-control/${liveHosted.id}'),
            ),
            const SizedBox(height: 16),
          ],

          // Quick Action Cards
          Row(
            children: [
              Expanded(
                child: _buildHeroCard(
                  context: context,
                  title: 'Join Game',
                  subtitle: 'Enter invite code',
                  icon: Icons.login_rounded,
                  color: AppTheme.primaryColor,
                  onTap: () => context.push('/join'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildHeroCard(
                  context: context,
                  title: 'Create Game',
                  subtitle: 'Host new event',
                  icon: Icons.add_circle_outline_rounded,
                  color: AppTheme.secondaryColor,
                  isSecondary: true,
                  onTap: () => context.push('/create-game'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // USP Showcase: Why Play Tambola Multiplayer?
          _buildUspShowcaseSection(context),
          const SizedBox(height: 24),

          // Mobile Apps Download Badges Section
          _buildAppDownloadSection(context),
          const SizedBox(height: 20),

          // Quick Rules & How to Win Helper
          _buildHowToPlayCard(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildUserProfileStrip(BuildContext context, MptUser user, AsyncValue walletState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryLight.withOpacity(0.25),
            child: Text(_getAvatarEmoji(user.avatar), style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user.isAnonymous ? 'Guest Player • Tap Profile to backup' : 'Verified Player',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => context.push('/wallet'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars, size: 16, color: AppTheme.secondaryColor),
                  const SizedBox(width: 4),
                  walletState.when(
                    loading: () => const Text('...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    error: (_, __) => const Text('10 Credits', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                    data: (w) => Text(
                      '${w.availableCredits} C',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveGameBanner(BuildContext context, {required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.accentSuccess.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.accentSuccess, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentSuccess.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_circle_filled, color: AppTheme.accentSuccess, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSuccess,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('LIVE NOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppTheme.accentSuccess),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard({
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.18),
              AppTheme.darkCard,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUspShowcaseSection(BuildContext context) {
    final usps = [
      {
        'icon': Icons.bolt_rounded,
        'color': AppTheme.secondaryColor,
        'title': 'Zero-Lag Multiplayer',
        'desc': 'Synchronized realtime caller & live board for 100+ players.',
      },
      {
        'icon': Icons.grid_view_rounded,
        'color': AppTheme.primaryLight,
        'title': '100% Unique Tickets',
        'desc': 'Authentic 3x9 tickets with 15 numbers across 9 columns.',
      },
      {
        'icon': Icons.tv_rounded,
        'color': AppTheme.accentInfo,
        'title': 'Voice Caller & TV Board',
        'desc': 'Voice announcements with widescreen TV projector mode.',
      },
      {
        'icon': Icons.verified_rounded,
        'color': AppTheme.accentSuccess,
        'title': 'Anti-Bogey Validation',
        'desc': 'Automated instant verification for lines & Full House.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: AppTheme.secondaryColor, size: 18),
                SizedBox(width: 8),
                Text(
                  'Why Play Tambola Multiplayer?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            Text(
              'Swipe →',
              style: TextStyle(fontSize: 11, color: Color(0xFF718096)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: usps.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, idx) {
              final item = usps[idx];
              final color = item['color'] as Color;
              return Container(
                width: 200,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(item['icon'] as IconData, color: color, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item['title'] as String,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['desc'] as String,
                      style: const TextStyle(fontSize: 10, color: Color(0xFFA0AEC0), height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAppDownloadSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E334D)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withOpacity(0.12),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.phone_android_rounded, color: AppTheme.secondaryColor, size: 22),
              SizedBox(width: 8),
              Text(
                'Play Anywhere on Any Device',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Enjoy Tambola seamlessly in your web browser or download the native mobile apps.',
            style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildStoreButton(
                  title: 'Google Play',
                  subtitle: 'Android App',
                  icon: Icons.play_arrow_rounded,
                  onTap: () => _launchURL('https://tambola.digitalappstudio.com'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStoreButton(
                  title: 'App Store',
                  subtitle: 'iOS / iPhone',
                  icon: Icons.apple,
                  onTap: () => _launchURL('https://tambola.digitalappstudio.com'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreButton({required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3B4163)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFFA0AEC0))),
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowToPlayCard(BuildContext context) {
    return Card(
      color: AppTheme.darkSurface,
      child: ListTile(
        leading: const Icon(Icons.menu_book_rounded, color: AppTheme.primaryLight),
        title: const Text('How to Play & Winning Patterns', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text('Learn about Early 5, Lines, 4 Corners & Full House', style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showHowToPlayDialog(context),
      ),
    );
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Winning Patterns', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('⭐ Early 5 (Jaldi 5): First player to mark any 5 numbers on their ticket.', style: TextStyle(fontSize: 13, height: 1.4)),
              SizedBox(height: 10),
              Text('⭐ Top Line: All 5 numbers on the top row marked.', style: TextStyle(fontSize: 13, height: 1.4)),
              SizedBox(height: 10),
              Text('⭐ Middle Line: All 5 numbers on the middle row marked.', style: TextStyle(fontSize: 13, height: 1.4)),
              SizedBox(height: 10),
              Text('⭐ Bottom Line: All 5 numbers on the bottom row marked.', style: TextStyle(fontSize: 13, height: 1.4)),
              SizedBox(height: 10),
              Text('⭐ Four Corners: The 1st and last numbers of the top and bottom rows marked.', style: TextStyle(fontSize: 13, height: 1.4)),
              SizedBox(height: 10),
              Text('🏆 Full House: All 15 numbers on the 3x9 ticket completed!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor, height: 1.4)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It!'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: PLAYER HUB
  // ==========================================
  Widget _buildPlayerTab(BuildContext context, AsyncValue<List<Map<String, dynamic>>> joinedState) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick Join Code Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.5), width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code, color: AppTheme.secondaryColor, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Have an Invite Code?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('Enter code to get ticket & seat reservation', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => context.push('/join'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // My Joined Games Header & Filters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.confirmation_number_outlined, color: AppTheme.primaryLight, size: 20),
                  SizedBox(width: 8),
                  Text('My Joined Games', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events_outlined, color: AppTheme.secondaryColor, size: 20),
                tooltip: 'My Rewards',
                onPressed: () => context.push('/rewards'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'LIVE', 'WAITING', 'COMPLETED'].map((filter) {
                final isSelected = _playerFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      filter == 'ALL'
                          ? 'All Games'
                          : filter == 'LIVE'
                              ? '🟢 Live'
                              : filter == 'WAITING'
                                  ? '⏳ Upcoming'
                                  : '🏁 Completed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : const Color(0xFFA0AEC0),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: AppTheme.darkSurface,
                    onSelected: (_) => setState(() => _playerFilter = filter),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Games List
          joinedState.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
            error: (err, _) => Center(child: Text('Error loading games: $err')),
            data: (joined) {
              final filtered = joined.where((reg) {
                final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                final status = (gameData['status'] ?? 'OPEN').toString();
                if (_playerFilter == 'LIVE') return status == 'IN_PROGRESS';
                if (_playerFilter == 'WAITING') return status == 'OPEN';
                if (_playerFilter == 'COMPLETED') return status == 'COMPLETED';
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(30),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.confirmation_number_outlined, size: 48, color: Color(0xFF4A5568)),
                      const SizedBox(height: 10),
                      Text(
                        _playerFilter == 'ALL'
                            ? 'No joined games found.\nEnter an invite code to join a game!'
                            : 'No $_playerFilter games found.',
                        style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, idx) {
                  final reg = filtered[idx];
                  final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                  final gameId = (reg['game_id'] ?? '').toString();
                  final gameName = (gameData['name'] ?? 'Tambola Game').toString();
                  final gameStatus = (gameData['status'] ?? 'OPEN').toString();
                  final seatStatus = (reg['seat_status'] ?? 'CONFIRMED').toString();

                  final isLive = gameStatus == 'IN_PROGRESS';
                  final isCompleted = gameStatus == 'COMPLETED';
                  final isConfirmed = seatStatus == 'CONFIRMED' || seatStatus == 'ELIGIBLE';

                  return Card(
                    color: AppTheme.darkSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isLive
                            ? AppTheme.accentSuccess
                            : isCompleted
                                ? const Color(0xFF3B4163)
                                : const Color(0xFF2E334D),
                        width: isLive ? 1.5 : 1,
                      ),
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
                                        color: isLive
                                            ? AppTheme.accentSuccess.withOpacity(0.2)
                                            : isCompleted
                                                ? const Color(0xFF718096).withOpacity(0.2)
                                                : Colors.black26,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isLive
                                            ? '🟢 LIVE'
                                            : isCompleted
                                                ? '🏁 COMPLETED'
                                                : isConfirmed
                                                    ? 'CONFIRMED'
                                                    : 'WAITING',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isLive
                                              ? AppTheme.accentSuccess
                                              : isCompleted
                                                  ? const Color(0xFFA0AEC0)
                                                  : isConfirmed
                                                      ? AppTheme.primaryLight
                                                      : AppTheme.accentWarning,
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
                              if (isLive || isCompleted) {
                                context.push('/play/$gameId');
                              } else {
                                context.push('/game-status/$gameId');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isLive
                                  ? AppTheme.accentSuccess
                                  : isCompleted
                                      ? const Color(0xFF2E334D)
                                      : AppTheme.primaryColor,
                              foregroundColor: isCompleted ? AppTheme.secondaryColor : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            child: Text(
                              isLive
                                  ? 'Play Ticket'
                                  : isCompleted
                                      ? 'View Results'
                                      : 'View Status',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: ORGANIZER HUB
  // ==========================================
  Widget _buildOrganizerTab(BuildContext context, AsyncValue<List<MptGame>> hostedState, AsyncValue walletState) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Create New Game Hero Button
          ElevatedButton.icon(
            onPressed: () => context.push('/create-game'),
            icon: const Icon(Icons.add_circle, color: Colors.black, size: 22),
            label: const Text('Create New Game Event', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 16),

          // Organizer Wallet Preview Card
          _buildWalletPreviewCard(context, ref, walletState),
          const SizedBox(height: 20),

          // Hosted Games Header & Filters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.dashboard_customize_outlined, color: AppTheme.secondaryColor, size: 20),
                  SizedBox(width: 8),
                  Text('My Hosted Games', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              Text(
                '${hostedState.value?.length ?? 0} Games',
                style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'LIVE', 'LOBBY', 'COMPLETED'].map((filter) {
                final isSelected = _organizerFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      filter == 'ALL'
                          ? 'All Events'
                          : filter == 'LIVE'
                              ? '🟢 Live Controls'
                              : filter == 'LOBBY'
                                  ? '🚪 Lobby Open'
                                  : '🏁 Concluded',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : const Color(0xFFA0AEC0),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.secondaryColor.withOpacity(0.3),
                    side: BorderSide(color: isSelected ? AppTheme.secondaryColor : const Color(0xFF2E334D)),
                    backgroundColor: AppTheme.darkSurface,
                    onSelected: (_) => setState(() => _organizerFilter = filter),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Hosted Games List
          hostedState.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (games) {
              final filtered = games.where((g) {
                if (_organizerFilter == 'LIVE') return g.isInProgress;
                if (_organizerFilter == 'LOBBY') return g.isLobbyOpen;
                if (_organizerFilter == 'COMPLETED') return g.isCompleted;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(30),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.event_note, size: 48, color: Color(0xFF4A5568)),
                      const SizedBox(height: 10),
                      const Text(
                        'No hosted games in this filter.\nTap "Create New Game Event" to start!',
                        style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, idx) {
                  final game = filtered[idx];
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
              );
            },
          ),
          const SizedBox(height: 16),

          // Prize Verification Tool Card
          _buildAdminVerifyCard(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: PROFILE & SETTINGS
  // ==========================================
  Widget _buildProfileTab(BuildContext context, MptUser user, AsyncValue walletState) {
    final isProtected = ref.read(authRepositoryProvider).isProtectedIdentity();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppTheme.primaryLight.withOpacity(0.25),
                    child: Text(_getAvatarEmoji(user.avatar), style: const TextStyle(fontSize: 36)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.displayName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isProtected ? AppTheme.accentSuccess.withOpacity(0.2) : AppTheme.secondaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isProtected ? '✓ Cloud Account Linked' : 'Guest Account',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isProtected ? AppTheme.accentSuccess : AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => ProfileEditDialog(currentUser: user),
                    ),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Change Display Name & Avatar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Social Sign-In / Account Protection Section
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.secondaryColor, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Account Backup & Social Sign-In',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Link your account with Google or Email to save your organizer credits, tickets, and game history across devices.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 16),

                // Google Sign In Button
                ElevatedButton.icon(
                  onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 24, color: Colors.white),
                  label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // Email Sign In Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Enter email address',
                          prefixIcon: Icon(Icons.email_outlined),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isSigningIn ? null : _handleEmailSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: const Text('Send Link'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Wallet & Verification Shortcuts
          Card(
            color: AppTheme.darkSurface,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.secondaryColor),
                  title: const Text('Organizer Credits & Wallet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/wallet'),
                ),
                const Divider(height: 1, color: Color(0xFF2E334D)),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined, color: AppTheme.primaryLight),
                  title: const Text('My Rewards & Vouchers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/rewards'),
                ),
                const Divider(height: 1, color: Color(0xFF2E334D)),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner, color: AppTheme.accentInfo),
                  title: const Text('Organizer Prize Verification', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/verify-reward'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Company / App Info Footer
          Center(
            child: Column(
              children: [
                InkWell(
                  onTap: () => _launchURL('https://tambola.digitalappstudio.com'),
                  child: const Text(
                    'Developed by Digital App Studio',
                    style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0), decoration: TextDecoration.underline),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Tambola Multiplayer v1.0.4', style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==========================================
  // SHARED WIDGETS & AUTH ACTIONS
  // ==========================================
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
                Row(
                  children: [
                    if (AppConfig.enableMockCredits)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                          onPressed: () async {
                            await ref.read(walletRepositoryProvider).addMockCredits(200);
                            ref.invalidate(walletProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('+200 Test Credits added!'), backgroundColor: AppTheme.accentSuccess),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            side: const BorderSide(color: AppTheme.secondaryColor),
                          ),
                          child: const Text('+200', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
                        ),
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

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Redirecting to Google Sign-In...')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google Sign-In error: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handleEmailSignIn() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address'), backgroundColor: AppTheme.accentWarning),
      );
      return;
    }

    setState(() => _isSigningIn = true);
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Magic sign-in link sent to $email! Please check your inbox.'), backgroundColor: AppTheme.accentSuccess),
      );
      _emailController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email sign-in error: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _launchURL(String urlStr) async {
    final uri = Uri.parse(urlStr);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

