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
import '../widgets/how_it_works_section.dart';
import '../widgets/opening_screen.dart';
import '../widgets/perfect_for_chips_section.dart';
import '../widgets/usp_grid_section.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';

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
        '👉 Tap the link below to open the app or download it:\n$link';
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
                subtitle: 'You are hosting this live session. Tap to resume caller controls.',
                onTap: () => context.push('/admin-control/${liveHosted.id}'),
              ),
              const SizedBox(height: 12),
            ],

            // 1. Dashboard Hero Section (Free for 1-5, Optional App, 3 CTAs)
            const DashboardHeroSection(),
            const SizedBox(height: 14),

            // 2. USP Grid (Instant Play, Auto Win Verification, 100% Free Family Play)
            const UspGridSection(),
            const SizedBox(height: 14),

            // 3. How It Works (3-step flow)
            const HowItWorksSection(),
            const SizedBox(height: 14),

            // 4. Perfect For (Chip row)
            const PerfectForChipsSection(),
            const SizedBox(height: 14),

            // 5. Mobile Apps Download Badges Section
            _buildAppDownloadSection(context),
            const SizedBox(height: 12),

            // 6. Quick Rules & How to Win Helper
            _buildHowToPlayCard(context),
            const SizedBox(height: 8),

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
              subtitle: 'You are hosting this live session. Tap to resume controls.',
              onTap: () => context.push('/admin-control/${liveHosted.id}'),
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
                    'Play Live Tambola, Housie & 90-Ball Bingo',
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
                  'Live multiplayer for friends, family, parties & events • Instant web play',
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

          // Primary Action 1: Join Game
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.secondaryColor.withValues(alpha: 0.15),
                  AppTheme.darkCard,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5), width: 1.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Text('🔑', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join a Game',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Enter 6-digit room code — instant web play, zero download',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => context.push('/join'),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Join a Game', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Primary Action 2: Host a Game
          Container(
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5), width: 1.5),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host a Game',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Free for 1–5 players • Paid hosting for larger groups',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => AuthGuard.requireHostAuth(
                    context,
                    ref,
                    () => context.push('/create-game'),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Host a Game', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick Sign-In for Guests (if not registered)
          if (!user.isRegistered) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Sign in to save hosted games & access wallet history',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => AuthDialog.show(context),
                    child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Limited Time Disclaimer
          const Center(
            child: Text(
              '* Free tier for 1–5 players is offered for family play for a limited time and subject to terms.',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),

          // Footer links
          Center(
            child: Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('${AppConfig.appBaseUrl}/privacy-policy.html')),
                  child: const Text('Privacy Policy', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('${AppConfig.appBaseUrl}/terms-conditions.html')),
                  child: const Text('Terms', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('${AppConfig.appBaseUrl}/pricing.html')),
                  child: const Text('Pricing', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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

  Widget _buildAppDownloadSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
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
              Icon(Icons.phone_android_rounded, color: AppTheme.secondaryColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Keep DabHousie Ready',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Use the mobile app for scheduled games, push reminders and quick access to ad-hoc games. Guests can join directly on web with zero app download.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStoreButton(
                  title: 'Google Play',
                  subtitle: 'Android App',
                  icon: Icons.play_arrow_rounded,
                  onTap: () => _launchURL(AppConfig.appBaseUrl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStoreButton(
                  title: 'App Store',
                  subtitle: 'iOS / iPhone',
                  icon: Icons.apple,
                  onTap: () => _launchURL(AppConfig.appBaseUrl),
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3B4163)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subtitle, style: const TextStyle(fontSize: 8.5, color: Color(0xFFA0AEC0)), overflow: TextOverflow.ellipsis),
                  Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                ],
              ),
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
                IconButton(
                  icon: const Icon(Icons.emoji_events_outlined, color: AppTheme.secondaryColor, size: 20),
                  tooltip: 'My Rewards',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.push('/rewards'),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Filter Chips (Wrapping with no horizontal scrolling)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['ALL', 'LIVE', 'WAITING', 'COMPLETED'].map((filter) {
                final isSelected = _playerFilter == filter;
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  if (_playerFilter == 'LIVE') return status == 'IN_PROGRESS';
                  if (_playerFilter == 'WAITING') return status == 'OPEN';
                  if (_playerFilter == 'COMPLETED') return status == 'COMPLETED';
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.confirmation_number_outlined, size: 36, color: Color(0xFF4A5568)),
                        const SizedBox(height: 8),
                        Text(
                          _playerFilter == 'ALL'
                              ? 'No joined games found.\nEnter an invite code to join a game!'
                              : 'No $_playerFilter games found.',
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
                    final reg = filtered[idx];
                    final gameData = reg['game'] as Map<String, dynamic>? ?? {};
                    final gameId = (reg['game_id'] ?? '').toString();
                    final gameName = (gameData['name'] ?? 'DabHousie Game').toString();
                    final gameStatus = (gameData['status'] ?? 'OPEN').toString();
                    final seatStatus = (reg['seat_status'] ?? 'CONFIRMED').toString();

                    final isLive = gameStatus == 'IN_PROGRESS';
                    final isCompleted = gameStatus == 'COMPLETED';
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
                                  Text(
                                    gameName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
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
                                                          ? 'CONFIRMED'
                                                          : 'WAITING',
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
                                    : isCancelled
                                        ? const Color(0xFF2E334D)
                                        : isCompleted
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
                                            : 'View Status',
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

            // Organizer Wallet Preview Card
            _buildWalletPreviewCard(context, ref, walletState),
            const SizedBox(height: 16),

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
              children: ['ALL', 'LIVE', 'LOBBY', 'COMPLETED'].map((filter) {
                final isSelected = _organizerFilter == filter;
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  if (_organizerFilter == 'LIVE') return g.isInProgress;
                  if (_organizerFilter == 'LOBBY') return g.isLobbyOpen;
                  if (_organizerFilter == 'COMPLETED') return g.isCompleted || g.isCancelled;
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
                          _organizerFilter == 'ALL'
                              ? 'No hosted games yet.\nTap "Create New Game Event" to start!'
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
                    final isLive = game.isInProgress;
                    final isLobby = game.isLobbyOpen;
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
                                  ElevatedButton.icon(
                                    onPressed: () => context.push('/admin-control/${game.id}'),
                                    icon: const Icon(Icons.play_circle_filled, size: 14),
                                    label: const Text('Live Controls'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentSuccess,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                      minimumSize: Size.zero,
                                    ),
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
                                  OutlinedButton.icon(
                                    onPressed: () => LiveDisplayHelper.openInNewWindow(context, game.id),
                                    icon: const Icon(Icons.tv, size: 14),
                                    label: const Text('Results ↗'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                      minimumSize: Size.zero,
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
                          'Account Backup & Google Sign-In',
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
                    ElevatedButton(
                      onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1F2937),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSigningIn
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Center(
                                    child: Text(
                                      'G',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF4285F4)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
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
                            foregroundColor: Colors.white,
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
            ],

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
                      error: (_, __) => const Text('10 Credits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor)),
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




