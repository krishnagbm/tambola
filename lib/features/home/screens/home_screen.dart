import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/live_display_helper.dart';
import '../../../models/mpt_game.dart';
import '../../../models/mpt_user.dart';
import '../../../providers/app_providers.dart';
import '../../auth/widgets/auth_dialog.dart';
import '../../auth/widgets/profile_edit_dialog.dart';
import '../widgets/dashboard_footer.dart';
import '../widgets/dashboard_hero_section.dart';
import '../widgets/gameplay_showcase_section.dart';
import '../widgets/how_it_works_section.dart';
import '../widgets/opening_screen.dart';
import '../widgets/perfect_for_chips_section.dart';
import '../widgets/usp_grid_section.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../rewards/widgets/organizer_game_claims_dialog.dart';


class HomeScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const HomeScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentTabIndex;
  String _playerFilter = 'ACTIVE';
  String _organizerFilter = 'ACTIVE';
  bool _isSigningIn = false;
  String? _loadingProvider;
  final ScrollController _playerGamesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.initialTabIndex;
  }

  @override
  void dispose() {
    _playerGamesScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() {
        _currentTabIndex = widget.initialTabIndex;
      });
    }
  }

  void _refreshAll() {
    ref.invalidate(currentUserProvider);
    ref.invalidate(walletProvider);
    ref.invalidate(myHostedGamesProvider);
    ref.invalidate(myJoinedGamesProvider);
  }

  void _handleCopyLink(MptGame game) {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Direct join link copied to clipboard!')),
    );
  }

  Future<void> _handleShareInvite(MptGame game) async {
    final link = '${AppConfig.appBaseUrl}/#/join/${game.inviteCode}';
    final text = '🎉 You are invited to play DabHousie with me in "${game.name}"!\n\n'
        '🔑 Invite Code: ${game.inviteCode}\n\n'
        '👉 Tap the link below to join directly in your browser:\n$link';
    await Share.share(text, subject: 'Join DabHousie: ${game.name}');
  }

  Future<void> _handleCancelGameFromHome(MptGame game) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger),
            SizedBox(width: 8),
            Text('Cancel Event?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel "${game.name}"?\n\n'
          'This will close the lobby and deactivate the invite code (${game.inviteCode}). Any players currently in the waiting room will be notified. No credits will be charged.',
          style: const TextStyle(fontSize: 14, color: Color(0xFFE2E8F0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Event'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel Event'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(gameRepositoryProvider).cancelGame(game.id);
      ref.invalidate(myHostedGamesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Game event cancelled successfully.'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel event: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);
    final walletState = ref.watch(walletProvider);
    final hostedGamesState = ref.watch(myHostedGamesProvider);
    final joinedGamesState = ref.watch(myJoinedGamesProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: _currentTabIndex == 0
            ? null
            : _currentTabIndex == 1
                ? 'Player'
                : _currentTabIndex == 2
                    ? 'Organizer'
                    : 'Profile',
        onRefresh: _refreshAll,
      ),
      body: userState.when(
        loading: () => const OpeningScreen(),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (currentUser) => RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildDashboardTab(context, currentUser, walletState, hostedGamesState, joinedGamesState),
              _buildPlayerTab(context, joinedGamesState),
              _buildOrganizerTab(context, currentUser, hostedGamesState, walletState),
              _buildProfileTab(context, currentUser, walletState),
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
  // RESPONSIVE CONTAINER HELPER
  // ==========================================
  Widget _buildResponsiveContainer({
    required BuildContext context,
    required Widget child,
    double maxWidth = 1080,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 18);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  bool _isLiveOrPendingGame(dynamic g) {
    if (g == null) return false;
    String status = '';
    DateTime? createdAt;
    DateTime? startedAt;

    if (g is MptGame) {
      if (g.isCompleted || g.isCancelled) return false;
      status = g.status;
      createdAt = g.createdAt;
      startedAt = g.startedAt;
    } else if (g is Map) {
      status = (g['status'] ?? '').toString();
      if (status == 'COMPLETED' || status == 'CLOSED' || status == 'CANCELLED') return false;
      if (g['created_at'] != null) createdAt = DateTime.tryParse(g['created_at'].toString());
      if (g['started_at'] != null) startedAt = DateTime.tryParse(g['started_at'].toString());
    }

    if (status != 'IN_PROGRESS' && status != 'OPEN' && status != 'READY_TO_START') {
      return false;
    }

    // Stale games started > 3h ago or created > 12h ago are considered past history
    final now = DateTime.now();
    if (startedAt != null && now.difference(startedAt).inHours >= 3) return false;
    if (createdAt != null && now.difference(createdAt).inHours >= 12) return false;

    return true;
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
    // Only live or pending items appear; completed games move to history
    final liveJoined = joinedState.value?.where((reg) {
      final g = reg['game'] as Map<String, dynamic>? ?? {};
      return _isLiveOrPendingGame(g);
    }).firstOrNull;

    final liveHosted = hostedState.value?.where((g) => _isLiveOrPendingGame(g)).firstOrNull;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return _buildMobileDashboard(
        context,
        user,
        walletState,
        liveJoined,
        liveHosted,
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: _buildResponsiveContainer(
        context: context,
        maxWidth: 1080,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live Game in Progress Alert Banner
            if (liveJoined != null) ...[
              _buildLiveGameBanner(
                context,
                title: (liveJoined['game']?['name'] ?? 'Live Game').toString(),
                subtitle: 'You are registered in this live session!',
                onTap: () => context.push('/play/${liveJoined['game_id']}'),
              ),
              const SizedBox(height: 12),
            ] else if (liveHosted != null) ...[
              _buildLiveGameBanner(
                context,
                title: liveHosted.name,
                subtitle: liveHosted.isOpen
                    ? 'Lobby Open • Waiting for players. Tap to manage lobby & invite.'
                    : 'You are hosting this live session. Tap to resume caller controls.',
                onTap: () => context.push(liveHosted.isOpen ? '/admin-lobby/${liveHosted.id}' : '/admin-control/${liveHosted.id}'),
              ),
              const SizedBox(height: 12),
            ],

            // 1. Dashboard Hero Section
            const DashboardHeroSection(),
            const SizedBox(height: 14),

            // 2. Perfect For (Chip row)
            const PerfectForChipsSection(),
            const SizedBox(height: 14),

            // 3. How It Works (3-step flow)
            const HowItWorksSection(),
            const SizedBox(height: 14),

            // 4. See DabHousie in Action (Live Gameplay Visual Showcase)
            const GameplayShowcaseSection(),
            const SizedBox(height: 14),

            // 5. Quick Rules & How to Win Helper
            _buildHowToPlayCard(context),
            const SizedBox(height: 14),

            // 6. Why DabHousie (USP Grid - Instant Play, Auto Win Verification, 100% Free Family Play)
            const UspGridSection(),
            const SizedBox(height: 14),

            // 7. Dashboard Footer Tagline
            const DashboardFooter(),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DEDICATED INTUITIVE MOBILE DASHBOARD
  // ==========================================
  Widget _buildMobileDashboard(
    BuildContext context,
    MptUser user,
    AsyncValue walletState,
    dynamic liveJoined,
    MptGame? liveHosted,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live Game in Progress Alert Banner (if any)
          if (liveJoined != null) ...[
            _buildLiveGameBanner(
              context,
              title: (liveJoined['game']?['name'] ?? 'Live Game').toString(),
              subtitle: 'You are registered in this live session! Tap to play.',
              onTap: () => context.push('/play/${liveJoined['game_id']}'),
            ),
            const SizedBox(height: 14),
          ] else if (liveHosted != null) ...[
            _buildLiveGameBanner(
              context,
              title: liveHosted.name,
              subtitle: liveHosted.isOpen
                  ? 'Lobby Open • Waiting for players. Tap to manage lobby & invite.'
                  : 'You are hosting this live session. Tap to resume controls.',
              onTap: () => context.push(liveHosted.isOpen ? '/admin-lobby/${liveHosted.id}' : '/admin-control/${liveHosted.id}'),
            ),
            const SizedBox(height: 14),
          ],

          // Hero Message (No duplicate logo; AppBar contains the main logo)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF9E00), Color(0xFF4895EF)],
                  ).createShader(bounds),
                  child: const Text(
                    'Play Live Tambola, Housie, 90-Ball Bingo',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect with friends & family • Instant web play',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Card 1: Got an Invite Code?
          Container(
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEAB308), width: 1.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Text('🔑', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Got an Invite Code?',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Join instantly as guest — zero sign-up required',
                            style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => context.push('/join'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Enter Code to Join', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAB308),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Card 2: Free Family Play
          Container(
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981), width: 1.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Text('🎲', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Free Family Play',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Free for 1–5 players* (0 credits)',
                            style: TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => AuthGuard.requireHostAuth(
                    context,
                    ref,
                    () => context.push('/create-game'),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Start Free Game', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Card 3: Host Party / Event
          Container(
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Text('🎟️', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host Party / Event',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Kitty parties, society clubs & corporate galas',
                            style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => AuthGuard.requireHostAuth(
                    context,
                    ref,
                    () => context.push('/create-game'),
                  ),
                  icon: const Icon(Icons.celebration_rounded, size: 18),
                  label: const Text('Host Party (6+ Players)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }




  Widget _buildLiveGameBanner(BuildContext context, {required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.accentSuccess.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.accentSuccess, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentSuccess.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_circle_filled, color: AppTheme.accentSuccess, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.accentSuccess),
          ],
        ),
      ),
    );
  }



  Widget _buildHowToPlayCard(BuildContext context) {
    return Card(
      color: AppTheme.darkSurface,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.menu_book_rounded, color: AppTheme.primaryLight, size: 22),
        title: const Text('How to Play & Winning Patterns', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: const Text('Learn about Early 5, Lines, 4 Corners & Full House', style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 20),
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
      child: _buildResponsiveContainer(
        context: context,
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Quick Join Code Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.5), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code, color: AppTheme.secondaryColor, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Have an Invite Code?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Enter code to get ticket & seat reservation', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => context.push('/join'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('Join'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // My Joined Games Header & Filters
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.confirmation_number_outlined, color: AppTheme.primaryLight, size: 18),
                    SizedBox(width: 8),
                    Text('My Joined Games', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                Builder(
                  builder: (ctx) {
                    final rewardsList =
                        ref.watch(myRewardsProvider).value ?? [];
                    final unclaimedCount = rewardsList
                        .where((r) => r.isAvailable)
                        .length;
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: unclaimedCount > 0,
                        label: Text(
                          '$unclaimedCount',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        backgroundColor: AppTheme.secondaryColor,
                        child: const Icon(
                          Icons.emoji_events_outlined,
                          color: AppTheme.secondaryColor,
                          size: 20,
                        ),
                      ),
                      tooltip: 'My Rewards ($unclaimedCount Unclaimed)',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context.push('/rewards'),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Filter Chips (Wrapping with no horizontal scrolling)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['ACTIVE', 'LIVE', 'WAITING', 'COMPLETED', 'CANCELLED', 'ALL'].map((filter) {
                final isSelected = _playerFilter == filter;
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  label: Text(
                    filter == 'ACTIVE'
                        ? 'Active / Upcoming'
                        : filter == 'LIVE'
                            ? '🟢 Live'
                            : filter == 'WAITING'
                                ? '⏳ Upcoming Lobby'
                                : filter == 'COMPLETED'
                                    ? '🏁 Completed'
                                    : filter == 'CANCELLED'
                                        ? '🚫 Cancelled'
                                        : 'All Games',
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
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Games List
            joinedState.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (err, _) => Center(child: Text('Error loading games: $err')),
              data: (joined) {
                final filtered = joined.where((reg) {
                  final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                  final status = (gameData['status'] ?? 'OPEN').toString();
                  final isLiveOrPending = _isLiveOrPendingGame(gameData);
                  final isCancelled = status == 'CANCELLED';
                  final isCompleted = status == 'COMPLETED' || status == 'CLOSED' || (!isLiveOrPending && !isCancelled);

                  if (_playerFilter == 'ACTIVE') {
                    return isLiveOrPending && !isCancelled;
                  }
                  if (_playerFilter == 'LIVE') return status == 'IN_PROGRESS' && isLiveOrPending;
                  if (_playerFilter == 'WAITING') return (status == 'OPEN' || status == 'READY_TO_START') && isLiveOrPending && !isCancelled;
                  if (_playerFilter == 'COMPLETED') return isCompleted && !isCancelled;
                  if (_playerFilter == 'CANCELLED') return isCancelled;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.confirmation_number_outlined, size: 36, color: Color(0xFF4A5568)),
                        const SizedBox(height: 8),
                        Text(
                          _playerFilter == 'ACTIVE' || _playerFilter == 'ALL'
                              ? 'No active joined games.\nEnter an invite code to join a game!'
                              : 'No $_playerFilter games found.',
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: Scrollbar(
                      controller: _playerGamesScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _playerGamesScrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(10),
                        itemCount: filtered.length,
                        separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final reg = filtered[idx];
                          final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                          final gameId = (reg['game_id'] ?? '').toString();
                          final gameName = (gameData['name'] ?? 'DabHousie Game').toString();
                          final inviteCode = (gameData['invite_code'] ?? '').toString();
                          final gameStatus = (gameData['status'] ?? 'OPEN').toString();
                          final seatStatus = (reg['seat_status'] ?? 'CONFIRMED').toString();

                          final isLiveOrPending = _isLiveOrPendingGame(gameData);
                          final isLive = gameStatus == 'IN_PROGRESS' && isLiveOrPending;
                          final isCompleted = gameStatus == 'COMPLETED' || !isLiveOrPending;
                          final isCancelled = gameStatus == 'CANCELLED';
                          final isConfirmed = seatStatus == 'CONFIRMED' || seatStatus == 'ELIGIBLE';

                          return Card(
                            color: AppTheme.darkSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isLive
                                    ? AppTheme.accentSuccess
                                    : isCancelled
                                        ? AppTheme.accentDanger.withOpacity(0.5)
                                        : isCompleted
                                            ? const Color(0xFF3B4163)
                                            : const Color(0xFF2E334D),
                                width: isLive ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                gameName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (inviteCode.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  'Code: $inviteCode',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.secondaryColor,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isLive
                                                    ? AppTheme.accentSuccess.withOpacity(0.2)
                                                    : isCancelled
                                                        ? AppTheme.accentDanger.withOpacity(0.2)
                                                        : isCompleted
                                                            ? const Color(0xFF718096).withOpacity(0.2)
                                                            : Colors.black26,
                                                borderRadius: BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                isLive
                                                    ? '🟢 LIVE'
                                                    : isCancelled
                                                        ? '🚫 CANCELLED'
                                                        : isCompleted
                                                            ? '🏁 COMPLETED'
                                                            : isConfirmed
                                                                ? '⏳ LOBBY OPEN'
                                                                : '⏳ WAITING',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: isLive
                                                      ? AppTheme.accentSuccess
                                                      : isCancelled
                                                          ? AppTheme.accentDanger
                                                          : isCompleted
                                                              ? const Color(0xFFA0AEC0)
                                                              : isConfirmed
                                                                  ? AppTheme.primaryLight
                                                                  : AppTheme.accentWarning,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text('Seq #${reg['registration_seq'] ?? 1}', style: const TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                                          : (isCompleted || isCancelled)
                                              ? const Color(0xFF2E334D)
                                              : AppTheme.primaryColor,
                                      foregroundColor: (isCompleted || isCancelled) ? AppTheme.secondaryColor : Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                    child: Text(
                                      isLive
                                          ? 'Play Ticket'
                                          : isCancelled
                                              ? 'Cancelled'
                                              : isCompleted
                                                  ? 'View Results'
                                                  : 'Enter Lobby',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // AdSense Banner Slot right after history container
            const AdBannerSlot(
              slotId: 'DAB-PLAYER-TAB-01',
              title: 'Sponsored Partner',
              subtitle: 'Free live multiplayer with instant verification',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: ORGANIZER HUB
  // ==========================================
  Widget _buildOrganizerTab(BuildContext context, MptUser user, AsyncValue<List<MptGame>> hostedState, AsyncValue walletState) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: _buildResponsiveContainer(
        context: context,
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Create New Game Hero Button (Guarded)
            ElevatedButton.icon(
              onPressed: () => AuthGuard.requireHostAuth(
                context,
                ref,
                () => context.push('/create-game'),
              ),
              icon: const Icon(Icons.add_circle, color: Colors.black, size: 20),
              label: const Text(
                'Create New Game Event',
                style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondaryColor,
                padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),

            if (!user.isRegistered) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppTheme.secondaryColor, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host & Organizer Authentication',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Sign in with Google to schedule games, manage tickets, and preserve organizer credits across devices.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => AuthDialog.show(context, isHostContext: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Sign In'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Organizer Wallet Preview Card (Only visible to registered hosts)
            if (user.isRegistered) ...[
              _buildWalletPreviewCard(context, ref, walletState),
              const SizedBox(height: 16),
            ],

            // Hosted Games Header & Filters
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, color: AppTheme.secondaryColor, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'My Hosted Games',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Text(
                  '${hostedState.value?.length ?? 0} Games',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Filter Chips (Wrapping with no horizontal scrolling)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['ACTIVE', 'LIVE', 'LOBBY', 'COMPLETED', 'CANCELLED', 'ALL'].map((filter) {
                final isSelected = _organizerFilter == filter;
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  label: Text(
                    filter == 'ACTIVE'
                        ? 'Active & Open'
                        : filter == 'LIVE'
                            ? '🟢 Live Controls'
                            : filter == 'LOBBY'
                                ? '🚪 Lobby Open'
                                : filter == 'COMPLETED'
                                    ? '🏁 Completed'
                                    : filter == 'CANCELLED'
                                        ? '🚫 Cancelled'
                                        : 'All Events',
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
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Hosted Games List
            hostedState.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (games) {
                final filtered = games.where((g) {
                  final isLiveOrPending = _isLiveOrPendingGame(g);
                  final isCancelled = g.isCancelled;
                  final isCompleted = g.isCompleted || (!isLiveOrPending && !isCancelled);

                  if (_organizerFilter == 'ACTIVE') return isLiveOrPending && !isCancelled && (g.isInProgress || g.isLobbyOpen);
                  if (_organizerFilter == 'LIVE') return g.isInProgress && isLiveOrPending;
                  if (_organizerFilter == 'LOBBY') return g.isLobbyOpen && isLiveOrPending && !isCancelled;
                  if (_organizerFilter == 'COMPLETED') return isCompleted && !isCancelled;
                  if (_organizerFilter == 'CANCELLED') return isCancelled;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.event_note, size: 36, color: Color(0xFF4A5568)),
                        const SizedBox(height: 8),
                        Text(
                          _organizerFilter == 'ACTIVE' || _organizerFilter == 'ALL'
                              ? 'No active hosted games.\nTap "Create New Game Event" to start!'
                              : 'No $_organizerFilter events found.',
                          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final game = filtered[idx];
                    final isLiveOrPending = _isLiveOrPendingGame(game);
                    final isLive = game.isInProgress && isLiveOrPending;
                    final isLobby = game.isLobbyOpen && isLiveOrPending;
                    final isCancelled = game.isCancelled;

                    Color statusColor = isLive
                        ? const Color(0xFF10B981)
                        : isLobby
                            ? const Color(0xFF38BDF8)
                            : isCancelled
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF94A3B8);

                    Color statusBg = isLive
                        ? const Color(0xFF10B981).withValues(alpha: 0.18)
                        : isLobby
                            ? const Color(0xFF0284C7).withValues(alpha: 0.22)
                            : isCancelled
                                ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                                : const Color(0xFF475569).withValues(alpha: 0.25);

                    String statusLabel = isLive
                        ? '🟢 LIVE'
                        : isLobby
                            ? '🚪 LOBBY OPEN'
                            : isCancelled
                                ? '🚫 CANCELLED'
                                : '🏁 CONCLUDED';

                    return Card(
                      color: isLive ? AppTheme.accentSuccess.withValues(alpha: 0.08) : AppTheme.darkSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isLive ? AppTheme.accentSuccess : const Color(0xFF2E334D),
                          width: isLive ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    game.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Code: ${game.inviteCode}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• ${game.fundedCapacity} Seats',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFFA0AEC0)),
                                    ),
                                  ],
                                ),
                                if (isLive) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            OrganizerGameClaimsDialog.show(
                                              context,
                                              gameId: game.id,
                                              gameName: game.name,
                                              inviteCode: game.inviteCode,
                                            ),
                                        icon: const Icon(
                                          Icons.emoji_events_outlined,
                                          size: 13,
                                          color: AppTheme.secondaryColor,
                                        ),
                                        label: const Text('Claims'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppTheme.secondaryColor,
                                          side: BorderSide(
                                            color: AppTheme.secondaryColor
                                                .withValues(alpha: 0.5),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ElevatedButton.icon(
                                        onPressed: () => context.push(
                                          '/admin-control/${game.id}',
                                        ),
                                        icon: const Icon(
                                          Icons.play_circle_filled,
                                          size: 14,
                                        ),
                                        label: const Text('Live Controls'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.accentSuccess,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else if (isLobby) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => context.push('/admin-lobby/${game.id}'),
                                        icon: const Icon(Icons.meeting_room_outlined, size: 14),
                                        label: const Text('Open Lobby'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryLight,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFFA0AEC0)),
                                        tooltip: 'Event Options',
                                        color: AppTheme.darkCard,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: const BorderSide(color: Color(0xFF2E334D)),
                                        ),
                                        onSelected: (val) {
                                          if (val == 'copy') {
                                            _handleCopyLink(game);
                                          } else if (val == 'share') {
                                            _handleShareInvite(game);
                                          } else if (val == 'cancel') {
                                            _handleCancelGameFromHome(game);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'copy',
                                            child: Row(
                                              children: [
                                                Icon(Icons.link, size: 16, color: AppTheme.primaryLight),
                                                SizedBox(width: 8),
                                                Text('Copy Join Link', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'share',
                                            child: Row(
                                              children: [
                                                Icon(Icons.share, size: 16, color: AppTheme.secondaryColor),
                                                SizedBox(width: 8),
                                                Text('Share Invite', style: TextStyle(fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'cancel',
                                            child: Row(
                                              children: [
                                                Icon(Icons.cancel_outlined, size: 16, color: AppTheme.accentDanger),
                                                SizedBox(width: 8),
                                                Text('Cancel Event', style: TextStyle(fontSize: 13, color: AppTheme.accentDanger)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ] else if (isCancelled) ...[
                                  const Text(
                                    'Event Cancelled',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                                  ),
                                ] else ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            OrganizerGameClaimsDialog.show(
                                              context,
                                              gameId: game.id,
                                              gameName: game.name,
                                              inviteCode: game.inviteCode,
                                            ),
                                        icon: const Icon(
                                          Icons.emoji_events_outlined,
                                          size: 13,
                                        ),
                                        label: const Text('Manage Claims'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.darkCard,
                                          foregroundColor:
                                              AppTheme.secondaryColor,
                                          side: BorderSide(
                                            color: AppTheme.secondaryColor
                                                .withValues(alpha: 0.5),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            LiveDisplayHelper.openInNewWindow(
                                              context,
                                              game.id,
                                            ),
                                        icon: const Icon(Icons.tv, size: 14),
                                        label: const Text('Results ↗'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                    ],
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
            const SizedBox(height: 14),

            // Prize Verification Tool Card
            _buildAdminVerifyCard(context),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 3: PROFILE & SETTINGS
  // ==========================================
  Widget _buildProfileTab(BuildContext context, MptUser user, AsyncValue walletState) {
    final isRegistered = user.isRegistered;
    final hasAvatarUrl = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: _buildResponsiveContainer(
        context: context,
        maxWidth: 860,
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
                      backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.25),
                      backgroundImage: hasAvatarUrl ? NetworkImage(user.avatarUrl!) : null,
                      child: !hasAvatarUrl
                          ? Text(_getAvatarEmoji(user.avatar), style: const TextStyle(fontSize: 36))
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.displayName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (user.email != null && user.email!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        user.email!,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: isRegistered
                            ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                            : AppTheme.secondaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isRegistered
                            ? '✓ Registered Account (${user.provider ?? "Google"})'
                            : 'Guest Account',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isRegistered ? AppTheme.accentSuccess : AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => ProfileEditDialog(currentUser: user),
                          ),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit Display Name'),
                        ),
                        if (isRegistered)
                          OutlinedButton.icon(
                            onPressed: _handleSignOut,
                            icon: const Icon(Icons.logout, size: 16, color: AppTheme.accentDanger),
                            label: const Text('Sign Out', style: TextStyle(color: AppTheme.accentDanger)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.accentDanger),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Social Sign-In / Account Protection Section (Show when not registered)
            if (!isRegistered) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.secondaryColor, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Sign In to DabHousie',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in with Google or Apple for personal parties. To host for your organization with official branding, sign in with your company work email via Email (OTP).',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1), height: 1.4),
                    ),
                    const SizedBox(height: 18),

                    // Google Sign In
                    _buildOAuthButton(
                      icon: const CustomPaint(
                        size: Size(22, 22),
                        painter: GoogleLogoPainter(),
                      ),
                      title: 'Google',
                      subtitle: 'Continue with your Google Account',
                      isLoading: _isSigningIn && _loadingProvider == 'Google',
                      onTap: _isSigningIn ? null : _handleGoogleSignIn,
                    ),
                    const SizedBox(height: 10),

                    // Apple Sign In
                    _buildOAuthButton(
                      icon: const CustomPaint(
                        size: Size(22, 22),
                        painter: AppleLogoPainter(),
                      ),
                      title: 'Apple',
                      subtitle: 'Continue with your Apple ID',
                      isLoading: _isSigningIn && _loadingProvider == 'Apple',
                      onTap: _isSigningIn ? null : _handleAppleSignIn,
                    ),
                    const SizedBox(height: 10),

                    // Email (OTP Code) Sign In
                    _buildOAuthButton(
                      icon: const Icon(Icons.email_outlined, color: AppTheme.secondaryColor, size: 22),
                      title: 'Email (OTP Code)',
                      badge: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          '🏢 Work & Corporate',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                      subtitle: 'To host a corporate party,\nsign in with your work email & 6-digit OTP',
                      isLoading: false,
                      onTap: () => AuthDialog.show(context, startWithEmailOtp: true),
                    ),
                    const SizedBox(height: 16),

                    // Legal Note
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'By signing in, you agree to our ',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFCBD5E1),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          InkWell(
                            onTap: () => _launchURL('${AppConfig.appBaseUrl}/terms-conditions.html'),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              child: Text(
                                'Terms',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF60A5FA),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF60A5FA),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            ' and ',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFCBD5E1),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          InkWell(
                            onTap: () => _launchURL('${AppConfig.appBaseUrl}/privacy-policy.html'),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              child: Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF60A5FA),
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF60A5FA),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            '.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

          // Wallet & Verification Shortcuts
          Card(
            color: AppTheme.darkSurface,
            child: Column(
              children: [
                if (isRegistered) ...[
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.secondaryColor),
                    title: const Text('Organizer Credits & Wallet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/wallet'),
                  ),
                  const Divider(height: 1, color: Color(0xFF2E334D)),
                ],
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
                  onTap: () => _launchURL(AppConfig.appBaseUrl),
                  child: const Text(
                    'Developed by Digital App Studio',
                    style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0), decoration: TextDecoration.underline),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => _launchURL('${AppConfig.appBaseUrl}/privacy-policy.html'),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                    ),
                    InkWell(
                      onTap: () => _launchURL('${AppConfig.appBaseUrl}/terms-conditions.html'),
                      child: const Text(
                        'Terms & Conditions',
                        style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), decoration: TextDecoration.underline, decorationColor: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('DabHousie v1.0.4', style: TextStyle(fontSize: 10, color: Color(0xFF718096))),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

  // ==========================================
  // SHARED WIDGETS & AUTH ACTIONS
  // ==========================================
  Widget _buildWalletPreviewCard(BuildContext context, WidgetRef ref, AsyncValue walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.stars, color: AppTheme.secondaryColor, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Organizer Game Credits',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => context.push('/wallet'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.secondaryColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 14, color: AppTheme.secondaryColor),
                  label: const Text('Manage Wallet →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 1),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isNarrow = constraints.maxWidth < 360;

                final balanceCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    walletState.when(
                      loading: () => const Text('Loading...', style: TextStyle(fontSize: 16)),
                      error: (_, __) => const Text('0 Credits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                      data: (w) => Text(
                        '${Formatters.formatCredits(w.availableCredits)} Credits',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'For hosting games & expanding capacity',
                      style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0)),
                    ),
                  ],
                );

                final actionButtons = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (AppConfig.enableMockCredits)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            side: const BorderSide(color: AppTheme.secondaryColor),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('+200', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/wallet'),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Top Up'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      balanceCol,
                      const SizedBox(height: 10),
                      actionButtons,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: balanceCol),
                    const SizedBox(width: 8),
                    actionButtons,
                  ],
                );
              },
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
        dense: true,
        leading: const Icon(Icons.qr_code_scanner, color: AppTheme.accentInfo, size: 22),
        title: const Text('Organizer Prize Verification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: const Text('Verify and mark prize vouchers shown by winners', style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => context.push('/verify-reward'),
      ),
    );
  }

  Widget _buildOAuthButton({
    required Widget icon,
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback? onTap,
    Widget? badge,
  }) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFF1E293B),
        splashColor: AppTheme.primaryColor.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E334D), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          badge,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleOAuthSignIn(String provider, Future<void> Function() signInAction) async {
    setState(() {
      _isSigningIn = true;
      _loadingProvider = provider;
    });
    try {
      await signInAction();
      _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Redirecting to $provider Sign-In...')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$provider sign-in failed: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authRepo = ref.read(authRepositoryProvider);
    await _handleOAuthSignIn('Google', () => authRepo.signInWithGoogle());
  }

  Future<void> _handleAppleSignIn() async {
    final authRepo = ref.read(authRepositoryProvider);
    await _handleOAuthSignIn('Apple', () => authRepo.signInWithApple());
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to sign out? You will return to a guest session, and will need to sign in again to host games.',
          style: TextStyle(fontSize: 13),
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
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).signOut();
      _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed out successfully. You are now in a guest session.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out error: $e'), backgroundColor: AppTheme.accentDanger),
      );
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




