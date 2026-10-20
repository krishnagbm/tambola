import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/app_providers.dart';
import '../widgets/create_promotional_series_dialog.dart';

class SuperAdminDashboardScreen extends ConsumerStatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  ConsumerState<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState
    extends ConsumerState<SuperAdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Games Filter States
  String _selectedTierFilter = 'ALL';
  bool _hideBelowQuorum = false;
  String _visibilityFilter = 'ALL'; // 'ALL', 'PUBLIC', 'HIDDEN'
  String _searchQuery = '';
  String _hostSearchQuery = '';

  // Payments Filter States
  String _paymentSearchQuery = '';
  String _paymentModeFilter = 'ALL'; // 'ALL', 'TEST', 'LIVE'

  // Users Filter States
  String _userSearchQuery = '';
  String _userTypeFilter = 'ALL'; // 'ALL', 'ORGANIZERS', 'PLAYERS'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(currentAdminRoleProvider);
    ref.invalidate(adminReportsOverviewProvider);
  }

  Future<void> _toggleGameVisibility(String gameId, bool currentVisibility) async {
    final nextVal = !currentVisibility;
    try {
      final success = await ref
          .read(adminReportsRepositoryProvider)
          .setGamePublicVisibility(gameId, nextVal);

      if (success && mounted) {
        ref.invalidate(adminReportsOverviewProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: nextVal ? AppTheme.accentSuccess : const Color(0xFF475569),
            content: Text(
              nextVal
                  ? '🌐 Game is now PUBLIC in Recent Games.'
                  : '🔒 Game is now HIDDEN from Recent Games.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentDanger,
            content: Text('Failed to update visibility: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleAutoHideBelowQuorum() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text('Auto-Hide Below-Quorum Games', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'This will automatically hide any game with fewer than 2 players from the public Recent Games page (is_publicly_visible = false).\n\nDo you want to proceed?',
          style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hide Games (< 2 Players)'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final count = await ref
          .read(adminReportsRepositoryProvider)
          .autoHideBelowQuorumGames(minQuorum: 2);

      if (mounted) {
        ref.invalidate(adminReportsOverviewProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentSuccess,
            content: Text('✅ Cleaned up $count game(s) below quorum from Recent Games.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentDanger,
            content: Text('Auto-hide failed: $e'),
          ),
        );
      }
    }
  }

  void _showCreatePromotionalSeriesDialog(List<dynamic> games) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CreatePromotionalSeriesDialog(existingGames: games),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleState = ref.watch(currentAdminRoleProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFF16192E),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                color: AppTheme.secondaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Super Admin Reports',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'DabHousie Executive Control Center',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Reports',
            icon: const Icon(Icons.refresh, color: AppTheme.secondaryColor),
            onPressed: _refreshAll,
          ),
          IconButton(
            tooltip: 'Return to Home',
            icon: const Icon(Icons.home_outlined, color: Colors.white70),
            onPressed: () => context.go('/'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: roleState.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.secondaryColor),
              SizedBox(height: 16),
              Text(
                'Verifying Administrator Privileges...',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ],
          ),
        ),
        error: (err, _) => _buildAccessRestrictedView(
          errorMessage: err.toString(),
          userEmail: null,
        ),
        data: (roleData) {
          final isAdmin = roleData['is_admin'] == true;
          final userEmail = roleData['email'] as String?;

          if (!isAdmin) {
            return _buildAccessRestrictedView(
              errorMessage: null,
              userEmail: userEmail,
            );
          }

          return _buildReportsDashboard(userEmail ?? 'Super Admin');
        },
      ),
    );
  }

  // ==========================================
  // ACCESS RESTRICTED / ONBOARDING VIEW
  // ==========================================
  Widget _buildAccessRestrictedView({
    String? errorMessage,
    String? userEmail,
  }) {
    final email = userEmail ?? 'Not Signed In';
    final sqlGrantCommand =
        email.isNotEmpty && email != 'Not Signed In'
            ? 'UPDATE public."MPT_admin_profiles"\nSET role = \'ADMIN\'\nWHERE email = \'$email\';'
            : 'UPDATE public."MPT_admin_profiles"\nSET role = \'ADMIN\'\nWHERE email = \'your_email@gmail.com\';';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Card(
            color: AppTheme.darkCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF334155), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.accentDanger.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_person_rounded,
                        color: AppTheme.accentDanger,
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Super Admin Access Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    userEmail != null && userEmail.isNotEmpty
                        ? 'Your account ($email) is currently signed in with role "HOST". Super Admin privileges are required to view executive reports.'
                        : 'You must sign in with an authorized Super Admin account to access this page.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                      height: 1.4,
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMessage,
                        style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.terminal, color: AppTheme.secondaryColor, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'How to Grant Yourself Admin Role:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Execute this in your Supabase SQL Editor:',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF020617),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SelectableText(
                            sqlGrantCommand,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: sqlGrantCommand));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('SQL Command copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Copy SQL', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Return Home'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _refreshAll,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Check Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondaryColor,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // AUTHORIZED REPORTS DASHBOARD
  // ==========================================
  Widget _buildReportsDashboard(String adminEmail) {
    final reportsAsync = ref.watch(adminReportsOverviewProvider);

    return reportsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.secondaryColor),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.accentDanger, size: 48),
              const SizedBox(height: 12),
              Text(
                'Error Loading Reports: $err',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final metrics = (data['metrics'] as Map<String, dynamic>?) ?? {};
        final recentGames = (data['recent_games'] as List?) ?? [];
        final recentHosts = (data['recent_hosts'] as List?) ?? [];
        final recentPayments = (data['recent_payments'] as List?) ?? [];
        final recentUsers = (data['recent_users'] as List?) ?? [];
        final brandOffers = (data['brand_offers'] as List?) ?? [];
        final brandApprovals = (data['brand_approvals'] as List?) ?? [];

        return Column(
          children: [
            // Top Executive KPI Strip with interactive drilldown
            _buildExecutiveSummaryHeader(metrics, adminEmail, data),

            if (data['is_fallback_mode'] == true)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_sync_outlined, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Direct Query Mode Active — Run updated migration 20261016000001 in Supabase to activate server RPC.',
                        style: TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _refreshAll,
                      child: const Text('Refresh', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // Tab Bar
            Container(
              color: const Color(0xFF131728),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.secondaryColor,
                labelColor: AppTheme.secondaryColor,
                unselectedLabelColor: const Color(0xFF94A3B8),
                isScrollable: true,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    text: 'Games (${recentGames.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.people_outline, size: 18),
                    text: 'Hosts (${recentHosts.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    text: 'Stripe Payments (${recentPayments.isNotEmpty ? recentPayments.length : (metrics['total_payments_count'] ?? 0)})',
                  ),
                  Tab(
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    text: 'Reg. Users (${recentUsers.isNotEmpty ? recentUsers.length : (metrics['total_registered_users'] ?? 0)})',
                  ),
                  Tab(
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    text: 'Brand Offers (${brandOffers.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    text: 'Brand Approvals (${brandApprovals.length})',
                  ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGamesTab(recentGames),
                  _buildHostsTab(recentHosts),
                  _buildPaymentsTab(recentPayments, metrics),
                  _buildUsersTab(recentUsers, metrics),
                  _buildBrandOffersTab(brandOffers),
                  _buildBrandApprovalsTab(brandApprovals),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // EXECUTIVE KPI HEADER
  // ==========================================
  Widget _buildExecutiveSummaryHeader(
    Map<String, dynamic> m,
    String adminEmail,
    Map<String, dynamic> fullData,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF16192E),
        border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'PLATFORM METRICS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE SUPABASE DATA',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mark_email_read_outlined, size: 11, color: Color(0xFF10B981)),
                        SizedBox(width: 4),
                        Text(
                          'ALERTS: contact@dabhousie.com',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                'Admin: $adminEmail',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKpiCard(
                  title: 'Total Games',
                  value: '${m['total_games'] ?? 0}',
                  subText: '${m['active_games'] ?? 0} active / ${m['completed_games'] ?? 0} done',
                  icon: Icons.sports_esports,
                  color: AppTheme.primaryLight,
                  onTap: () {
                    _tabController.animateTo(0);
                    _showGamesDrilldownModal(fullData);
                  },
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Reg. Users',
                  value: '${m['total_registered_users'] ?? 0}',
                  subText: '${m['total_users'] ?? 0} total player profiles',
                  icon: Icons.people,
                  color: AppTheme.accentSuccess,
                  onTap: () {
                    _tabController.animateTo(3);
                    _showUsersDrilldownModal(fullData);
                  },
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Tickets & Claims',
                  value: '${m['total_tickets'] ?? 0}',
                  subText: '${m['total_claims'] ?? 0} verified claims',
                  icon: Icons.confirmation_number_outlined,
                  color: AppTheme.secondaryColor,
                  onTap: () => _showTicketsClaimsDrilldownModal(fullData),
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Brand Offers',
                  value: '${m['total_brand_offers'] ?? 0}',
                  subText: '${m['active_brand_offers'] ?? 0} active in catalog',
                  icon: Icons.card_giftcard,
                  color: Colors.amberAccent,
                  onTap: () {
                    _tabController.animateTo(4);
                    _showBrandOffersDrilldownModal(fullData);
                  },
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Brand Approvals',
                  value: '${m['total_brand_approvals'] ?? 0}',
                  subText: '${m['pending_brand_approvals'] ?? 0} pending review',
                  icon: Icons.verified_user,
                  color: AppTheme.accentInfo,
                  onTap: () {
                    _tabController.animateTo(5);
                    _showBrandApprovalsDrilldownModal(fullData);
                  },
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Stripe Payments',
                  value: '${m['total_payments_count'] ?? 0}',
                  subText: '\$${((m['total_revenue_amount'] ?? 0) as num).toStringAsFixed(2)} volume',
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF10B981),
                  onTap: () {
                    _tabController.animateTo(2);
                    _showPaymentsDrilldownModal(fullData);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subText,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 175,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2238),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: onTap != null ? color.withValues(alpha: 0.35) : const Color(0xFF2E334D),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, size: 9, color: color.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: color.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Drilldown',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.open_in_new, size: 8.5, color: color),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: RECENT GAMES (WITH CAPACITY & QUORUM CONTROLS)
  // ==========================================
  Widget _buildGamesTab(List games) {
    if (games.isEmpty) {
      return _buildEmptyTabState(
        'No games found',
        'Games will appear here once organizers create them.',
      );
    }

    // Filter games based on selected criteria
    final filteredGames = games.where((item) {
      final g = item as Map<String, dynamic>;
      final cap = (g['initial_funded_capacity'] as num?)?.toInt() ?? 25;
      final isVisible = g['is_publicly_visible'] != false;
      final confirmedCount = (g['confirmed_players_count'] as num?)?.toInt() ?? (g['player_count'] as num?)?.toInt() ?? 0;
      final quorumMet = confirmedCount >= 2;
      final name = (g['name'] as String? ?? '').toLowerCase();
      final code = (g['invite_code'] as String? ?? '').toLowerCase();
      final host = (g['host_identifier'] as String? ?? '').toLowerCase();

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !code.contains(q) && !host.contains(q)) {
          return false;
        }
      }

      // Quorum filter
      if (_hideBelowQuorum && !quorumMet) {
        return false;
      }

      // Visibility filter
      if (_visibilityFilter == 'PUBLIC' && !isVisible) return false;
      if (_visibilityFilter == 'HIDDEN' && isVisible) return false;

      // Capacity Tier filter
      if (_selectedTierFilter == 'Family Pack (1–5)' && cap > 5) return false;
      if (_selectedTierFilter == 'Small Party (6–25)' && (cap < 6 || cap > 25)) return false;
      if (_selectedTierFilter == 'Standard Event (26–50)' && (cap < 26 || cap > 50)) return false;
      if (_selectedTierFilter == 'Large Gala (51–100)' && (cap < 51 || cap > 100)) return false;
      if (_selectedTierFilter == 'Mega Event (101–250+)' && cap < 101) return false;

      return true;
    }).toList();

    return Column(
      children: [
        // Controls / Filters Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF131728),
            border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search & Auto-Hide Quorum Button
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search by game name, code, or host...',
                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showCreatePromotionalSeriesDialog(games),
                    icon: const Icon(Icons.celebration, size: 15),
                    label: const Text(
                      'Create Promo Series 🏆',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: AppTheme.secondaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _handleAutoHideBelowQuorum,
                    icon: const Icon(Icons.auto_fix_high, size: 14),
                    label: const Text('Auto-Hide < 2 Players', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Capacity Tier Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTierFilterChip('ALL', 'All Tiers (${games.length})'),
                    const SizedBox(width: 6),
                    _buildTierFilterChip('Family Pack (1–5)', 'Family (1–5)'),
                    const SizedBox(width: 6),
                    _buildTierFilterChip('Small Party (6–25)', 'Small (6–25)'),
                    const SizedBox(width: 6),
                    _buildTierFilterChip('Standard Event (26–50)', 'Standard (26–50)'),
                    const SizedBox(width: 6),
                    _buildTierFilterChip('Large Gala (51–100)', 'Gala (51–100)'),
                    const SizedBox(width: 6),
                    _buildTierFilterChip('Mega Event (101–250+)', 'Mega (101+)'),
                    const SizedBox(width: 14),

                    // Quorum & Visibility toggles
                    FilterChip(
                      selected: _hideBelowQuorum,
                      onSelected: (val) => setState(() => _hideBelowQuorum = val),
                      label: const Text('Only Quorum Met (≥ 2p)', style: TextStyle(fontSize: 11)),
                      selectedColor: AppTheme.secondaryColor.withValues(alpha: 0.25),
                      checkmarkColor: AppTheme.secondaryColor,
                      backgroundColor: const Color(0xFF0F172A),
                    ),
                    const SizedBox(width: 6),
                    _buildVisibilityDropdown(),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List of Filtered Games
        Expanded(
          child: filteredGames.isEmpty
              ? _buildEmptyTabState(
                  'No games match your filters',
                  'Try clearing the capacity tier, quorum filter, or search keywords.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredGames.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final g = filteredGames[i] as Map<String, dynamic>;
                    return _buildGameCard(g);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTierFilterChip(String value, String label) {
    final isSelected = _selectedTierFilter == value;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedTierFilter = value),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.black : Colors.white70,
        ),
      ),
      selectedColor: AppTheme.secondaryColor,
      backgroundColor: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Widget _buildVisibilityDropdown() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _visibilityFilter,
          dropdownColor: AppTheme.darkCard,
          style: const TextStyle(fontSize: 11, color: Colors.white),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Visibility: All')),
            DropdownMenuItem(value: 'PUBLIC', child: Text('Recent: Public Only')),
            DropdownMenuItem(value: 'HIDDEN', child: Text('Recent: Hidden Only')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _visibilityFilter = val);
          },
        ),
      ),
    );
  }

  // ==========================================
  // SINGLE GAME CARD (WITH RICH ACTIONS & QUORUM BADGE)
  // ==========================================
  Widget _buildGameCard(Map<String, dynamic> g) {
    final status = g['status'] as String? ?? 'OPEN';
    final statusColor = _getStatusColor(status);
    final isPubliclyVisible = g['is_publicly_visible'] != false;
    final confirmedCount = (g['confirmed_players_count'] as num?)?.toInt() ?? (g['player_count'] as num?)?.toInt() ?? 0;
    final quorumMet = confirmedCount >= 2;
    final tierName = g['capacity_tier_name'] as String? ?? 'Cap: ${g['initial_funded_capacity'] ?? 25}';
    final gameId = g['id'] as String? ?? '';
    final schedRaw = g['scheduled_at'];
    final scheduledAt = schedRaw != null ? DateTime.tryParse(schedRaw.toString()) : null;

    return Card(
      color: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isPubliclyVisible ? const BorderSide(color: Color(0xFF2E334D)).color : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Name, Status, and Visibility Badge
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          g['name'] as String? ?? 'Untitled Game',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tierName,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (scheduledAt != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alarm_on_rounded, size: 12, color: AppTheme.secondaryColor),
                        const SizedBox(width: 4),
                        Text(
                          Formatters.formatShortDate(scheduledAt.toLocal()),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Middle Row: Invite Code, Host info, and Quorum badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CODE: ${g['invite_code'] ?? "------"}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.person_outline, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Host: ${g['host_identifier'] ?? "Unknown"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quorum & Visibility Badges Row
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Quorum status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: quorumMet
                        ? AppTheme.accentSuccess.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: quorumMet ? AppTheme.accentSuccess.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        quorumMet ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        size: 13,
                        color: quorumMet ? AppTheme.accentSuccess : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        quorumMet
                            ? 'Quorum Met ($confirmedCount players)'
                            : 'Below Quorum ($confirmedCount / min 2)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: quorumMet ? AppTheme.accentSuccess : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                // Public Recent Games Visibility Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isPubliclyVisible
                        ? const Color(0xFF0369A1).withValues(alpha: 0.2)
                        : const Color(0xFF334155).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPubliclyVisible ? '🌐 Recent: Visible' : '🔒 Recent: Hidden',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPubliclyVisible ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),

                // Claims and Calls count
                Text(
                  '🏆 ${g['claims_count'] ?? 0} claims  •  🎱 ${g['called_count'] ?? 0}/90 balls',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (g['created_at'] != null)
                  Text(
                    Formatters.formatShortDate(DateTime.parse(g['created_at'])),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  )
                else
                  const SizedBox(),

                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // Host Lobby Button
                    if (status != 'COMPLETED' && status != 'CANCELLED')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        ),
                        onPressed: () => context.push('/admin-lobby/$gameId'),
                        icon: const Icon(Icons.meeting_room, size: 13),
                        label: const Text('Host Lobby', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),

                    // Start Game / Live Caller Controls Button
                    if (status == 'OPEN' || status == 'READY_TO_START')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSuccess,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        ),
                        onPressed: () => context.push('/admin-control/$gameId?autopilot=true'),
                        icon: const Icon(Icons.play_arrow_rounded, size: 14),
                        label: const Text('Start Game', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    else if (status == 'IN_PROGRESS')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSuccess,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                        ),
                        onPressed: () => context.push('/admin-control/$gameId?autopilot=true'),
                        icon: const Icon(Icons.sensors, size: 14),
                        label: const Text('Live Controls', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),

                    // TV Display
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                      onPressed: () => context.push('/live-display/$gameId'),
                      icon: const Icon(Icons.tv, size: 13),
                      label: const Text('Live TV', style: TextStyle(fontSize: 11)),
                    ),

                    // Detailed Game Inspector Modal (Replacing "Status Screen")
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      ),
                      onPressed: () => _showGameInspectionDialog(context, g),
                      icon: const Icon(Icons.analytics_outlined, size: 14, color: AppTheme.secondaryColor),
                      label: const Text('Inspect Stats', style: TextStyle(fontSize: 11)),
                    ),

                    // Visibility Toggle Button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      ),
                      onPressed: () => _toggleGameVisibility(gameId, isPubliclyVisible),
                      icon: Icon(
                        isPubliclyVisible ? Icons.visibility_off : Icons.visibility,
                        size: 14,
                        color: isPubliclyVisible ? Colors.orangeAccent : const Color(0xFF38BDF8),
                      ),
                      label: Text(
                        isPubliclyVisible ? 'Hide from Recent' : 'Show in Recent',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPubliclyVisible ? Colors.orangeAccent : const Color(0xFF38BDF8),
                        ),
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

  // ==========================================
  // DETAILED GAME INSPECTION DIALOG
  // ==========================================
  void _showGameInspectionDialog(
    BuildContext context,
    Map<String, dynamic> gameSummary,
  ) {
    final gameId = gameSummary['id'] as String;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
            child: FutureBuilder<Map<String, dynamic>>(
              future: ref.read(adminReportsRepositoryProvider).getAdminGameDetails(gameId),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.secondaryColor),
                        SizedBox(height: 16),
                        Text('Loading Game Analytics & Participants...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.accentDanger, size: 40),
                        const SizedBox(height: 12),
                        Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
                      ],
                    ),
                  );
                }

                final details = snapshot.data ?? {};
                final game = (details['game'] as Map<String, dynamic>?) ?? gameSummary;
                final players = (details['players'] as List?) ?? [];
                final claims = (details['claims'] as List?) ?? [];
                final calledNumbers = (details['called_numbers'] as List?) ?? [];

                final isPublic = game['is_publicly_visible'] != false;
                final confirmedCount = players.where((p) => p['seat_status'] == 'CONFIRMED' || p['seat_status'] == 'ELIGIBLE').length;
                final quorumMet = confirmedCount >= 2;

                return DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      // Dialog Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: const BoxDecoration(
                          color: Color(0xFF16192E),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.analytics, color: AppTheme.secondaryColor, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    game['name'] ?? 'Game Statistics',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Code: ${game['invite_code']}  •  Status: ${game['status']}',
                                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () => Navigator.pop(dialogCtx),
                            ),
                          ],
                        ),
                      ),

                      // Quorum & Visibility Banner inside Dialog
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        color: const Color(0xFF0F172A),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  quorumMet ? Icons.check_circle : Icons.warning_amber_rounded,
                                  size: 16,
                                  color: quorumMet ? AppTheme.accentSuccess : Colors.orangeAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  quorumMet
                                      ? 'Quorum Met ($confirmedCount players confirmed)'
                                      : 'Below Quorum ($confirmedCount / min 2 players)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: quorumMet ? AppTheme.accentSuccess : Colors.orangeAccent,
                                  ),
                                ),
                              ],
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                Navigator.pop(dialogCtx);
                                await _toggleGameVisibility(gameId, isPublic);
                              },
                              icon: Icon(
                                isPublic ? Icons.visibility_off : Icons.visibility,
                                size: 14,
                                color: isPublic ? Colors.orangeAccent : const Color(0xFF38BDF8),
                              ),
                              label: Text(
                                isPublic ? 'Hide from Recent' : 'Make Public',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isPublic ? Colors.orangeAccent : const Color(0xFF38BDF8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tabs
                      Container(
                        color: const Color(0xFF131728),
                        child: TabBar(
                          indicatorColor: AppTheme.secondaryColor,
                          labelColor: AppTheme.secondaryColor,
                          unselectedLabelColor: const Color(0xFF94A3B8),
                          tabs: [
                            Tab(text: 'Players (${players.length})'),
                            Tab(text: 'Claims (${claims.length})'),
                            Tab(text: 'Numbers (${calledNumbers.length}/90)'),
                          ],
                        ),
                      ),

                      // Tab Views
                      Expanded(
                        child: TabBarView(
                          children: [
                            // 1. Players List
                            players.isEmpty
                                ? const Center(child: Text('No players registered yet.', style: TextStyle(color: Colors.white60)))
                                : ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: players.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFF2E334D)),
                                    itemBuilder: (context, idx) {
                                      final p = players[idx] as Map<String, dynamic>;
                                      return ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.2),
                                          child: Text('${idx + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                                        ),
                                        title: Text(p['display_name'] ?? 'Anonymous Player', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                        subtitle: Text('Status: ${p['seat_status']} • Tickets: ${p['tickets_count'] ?? 1}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                        trailing: p['joined_at'] != null
                                            ? Text(Formatters.formatShortDate(DateTime.parse(p['joined_at'])), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)))
                                            : null,
                                      );
                                    },
                                  ),

                            // 2. Claims List
                            claims.isEmpty
                                ? const Center(child: Text('No claims submitted yet.', style: TextStyle(color: Colors.white60)))
                                : ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: claims.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFF2E334D)),
                                    itemBuilder: (context, idx) {
                                      final c = claims[idx] as Map<String, dynamic>;
                                      final cStatus = c['status'] as String? ?? 'SUBMITTED';
                                      final isApproved = cStatus == 'APPROVED';
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          '${c['prize_type'] ?? "PRIZE"} - ${c['player_name'] ?? "Player"}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        subtitle: Text(
                                          c['rejection_reason'] != null ? 'Reason: ${c['rejection_reason']}' : 'Status: $cStatus',
                                          style: TextStyle(fontSize: 11, color: isApproved ? AppTheme.accentSuccess : Color(0xFF94A3B8)),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isApproved ? AppTheme.accentSuccess.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(cStatus, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isApproved ? AppTheme.accentSuccess : Colors.redAccent)),
                                        ),
                                      );
                                    },
                                  ),

                            // 3. Called Numbers
                            calledNumbers.isEmpty
                                ? const Center(child: Text('No numbers drawn yet.', style: TextStyle(color: Colors.white60)))
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: calledNumbers.map((n) {
                                        return Container(
                                          width: 38,
                                          height: 38,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5)),
                                          ),
                                          child: Text(
                                            '${n['number'] ?? n['called_number'] ?? n}',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                          ],
                        ),
                      ),

                      // Dialog Footer Actions
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF16192E),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Host: ${game['host_email'] != null && game['host_email'] != "" ? game['host_email'] : game['host_identifier']}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(dialogCtx);
                                    context.push('/live-display/$gameId');
                                  },
                                  icon: const Icon(Icons.tv, size: 14),
                                  label: const Text('Live TV', style: TextStyle(fontSize: 11)),
                                ),
                                if ((game['status'] ?? '').toString() != 'COMPLETED' && (game['status'] ?? '').toString() != 'CANCELLED') ...[
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.secondaryColor,
                                      foregroundColor: Colors.black,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(dialogCtx);
                                      context.push('/admin-lobby/$gameId');
                                    },
                                    icon: const Icon(Icons.meeting_room, size: 14),
                                    label: const Text('Host Lobby', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.accentSuccess,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(dialogCtx);
                                      context.push('/admin-control/$gameId?autopilot=true');
                                    },
                                    icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                    label: Text(
                                      (game['status'] ?? '').toString() == 'IN_PROGRESS' ? 'Live Controls' : 'Start Game',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 2: REGISTERED HOSTS & CREDIT ACTIONS
  // ==========================================
  Widget _buildHostsTab(List hosts) {
    final filteredHosts = hosts.where((item) {
      final h = item as Map<String, dynamic>;
      final email = (h['email'] as String? ?? '').toLowerCase();
      final uid = (h['user_id'] as String? ?? '').toLowerCase();
      if (_hostSearchQuery.isNotEmpty) {
        final q = _hostSearchQuery.toLowerCase();
        return email.contains(q) || uid.contains(q);
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Controls / Grant Promo Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF131728),
            border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    onChanged: (val) => setState(() => _hostSearchQuery = val.trim()),
                    style: const TextStyle(fontSize: 12.5, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search hosts by email or user ID...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                ),
                onPressed: () => _showGrantCreditsDialog(),
                icon: const Icon(Icons.card_giftcard, size: 16),
                label: const Text(
                  'Grant Promo Credits',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // Helpful Context Banner on Host Directory
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.secondaryColor, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Host Roster Context: ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11.5),
                    children: [
                      const TextSpan(
                        text: 'This directory lists accounts with active organizer privileges, game creations, or wallets. If only your own email is listed, other sign-ups joined as players and have not yet created their own game. ',
                        style: TextStyle(fontWeight: FontWeight.normal, color: Color(0xFF94A3B8)),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: InkWell(
                          onTap: () => _tabController.animateTo(3),
                          child: const Text(
                            'Switch to Reg. Users tab to inspect all player accounts &rarr;',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: filteredHosts.isEmpty
              ? _buildEmptyTabState(
                  'No Hosts Found',
                  _hostSearchQuery.isNotEmpty
                      ? 'No registered hosts match your search query.'
                      : 'Organizers who register will appear here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredHosts.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final h = filteredHosts[i] as Map<String, dynamic>;
                    final role = h['role'] as String? ?? 'HOST';
                    final isAdmin = role.toUpperCase() == 'ADMIN';
                    final credits = (h['available_credits'] as num?)?.toInt() ?? 0;
                    final expiresAt = h['credits_expire_at'] as String?;

                    return Card(
                      color: AppTheme.darkCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isAdmin ? AppTheme.secondaryColor.withValues(alpha: 0.5) : const Color(0xFF2E334D),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isAdmin
                                  ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                                  : AppTheme.primaryLight.withValues(alpha: 0.2),
                              child: Icon(
                                isAdmin ? Icons.shield_outlined : Icons.person,
                                color: isAdmin ? AppTheme.secondaryColor : AppTheme.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          h['email'] as String? ?? 'No Email',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isAdmin
                                              ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                                              : Colors.white10,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          role.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isAdmin ? AppTheme.secondaryColor : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'User ID: ${h['user_id'] ?? ""}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        '🎮 ${h['games_created_count'] ?? 0} games created',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '💳 $credits credits',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                                        ),
                                      ),
                                      if (expiresAt != null)
                                        Text(
                                          '⏳ Expires: ${Formatters.formatShortDate(DateTime.parse(expiresAt))}',
                                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quick Action Button on Host Card
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.secondaryColor,
                                side: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onPressed: () => _showGrantCreditsDialog(
                                prefilledEmail: h['email'] as String?,
                                prefilledUserId: h['user_id'] as String?,
                                currentCredits: credits,
                              ),
                              icon: const Icon(Icons.add_circle_outline, size: 14),
                              label: const Text('Add Credits', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showGrantCreditsDialog({
    String? prefilledEmail,
    String? prefilledUserId,
    int? currentCredits,
  }) async {
    final emailController = TextEditingController(text: prefilledEmail ?? '');
    final creditsController = TextEditingController(text: '300');
    final validityController = TextEditingController(text: '30');
    final reasonController = TextEditingController(text: 'Marketing Promo (10 Hosts Launch)');
    bool isSubmitting = false;
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: AppTheme.darkCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.card_giftcard, color: AppTheme.secondaryColor, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Grant Free / Promo Credits',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Allocate promotional credits with custom validity',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Host Email
                      const Text('Target Host Email:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: emailController,
                        enabled: !isSubmitting,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'e.g. host@gmail.com',
                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          prefixIcon: const Icon(Icons.email_outlined, size: 16, color: Color(0xFF94A3B8)),
                        ),
                      ),
                      if (currentCredits != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Current Balance: $currentCredits credits',
                          style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Credits Amount & Quick Chips
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Credits to Grant:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                          Row(
                            children: [100, 300, 500, 1000].map((preset) {
                              final isSelected = creditsController.text == preset.toString();
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: ChoiceChip(
                                  label: Text('+$preset', style: TextStyle(fontSize: 10, color: isSelected ? Colors.black : Colors.white)),
                                  selected: isSelected,
                                  selectedColor: AppTheme.secondaryColor,
                                  backgroundColor: const Color(0xFF1E293B),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  onSelected: isSubmitting ? null : (_) {
                                    setDialogState(() => creditsController.text = preset.toString());
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: creditsController,
                        enabled: !isSubmitting,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '300',
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          prefixIcon: const Icon(Icons.monetization_on_outlined, size: 16, color: AppTheme.secondaryColor),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Validity in Days & Quick Chips
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Validity (Days):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                          Row(
                            children: [7, 15, 30, 60, 365].map((preset) {
                              final isSelected = validityController.text == preset.toString();
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: ChoiceChip(
                                  label: Text('$preset d', style: TextStyle(fontSize: 10, color: isSelected ? Colors.black : Colors.white)),
                                  selected: isSelected,
                                  selectedColor: AppTheme.secondaryColor,
                                  backgroundColor: const Color(0xFF1E293B),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  onSelected: isSubmitting ? null : (_) {
                                    setDialogState(() => validityController.text = preset.toString());
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: validityController,
                        enabled: !isSubmitting,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '30',
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          prefixIcon: const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF94A3B8)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reason / Note
                      const Text('Campaign / Reason Note:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: reasonController,
                        enabled: !isSubmitting,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'e.g. Marketing Promo (10 Hosts Launch)',
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                          prefixIcon: const Icon(Icons.campaign_outlined, size: 16, color: Color(0xFF94A3B8)),
                        ),
                      ),

                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentDanger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.4)),
                          ),
                          child: Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Submit / Cancel
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondaryColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final email = emailController.text.trim();
                                    final credits = int.tryParse(creditsController.text.trim()) ?? 0;
                                    final days = int.tryParse(validityController.text.trim()) ?? 30;
                                    final reason = reasonController.text.trim();

                                    if (email.isEmpty) {
                                      setDialogState(() => errorText = 'Please enter a target host email');
                                      return;
                                    }
                                    if (credits <= 0) {
                                      setDialogState(() => errorText = 'Credits must be greater than 0');
                                      return;
                                    }

                                    setDialogState(() {
                                      isSubmitting = true;
                                      errorText = null;
                                    });

                                    try {
                                      final res = await ref.read(adminReportsRepositoryProvider).grantCreditsToHost(
                                        targetEmail: email,
                                        targetUserId: prefilledUserId,
                                        credits: credits,
                                        validityDays: days,
                                        reason: reason.isNotEmpty ? reason : 'Marketing Promo',
                                      );

                                      if (res['success'] == true) {
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                        }
                                        if (mounted) {
                                          ref.invalidate(adminReportsOverviewProvider);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: AppTheme.accentSuccess,
                                              content: Text('🎁 Successfully granted $credits credits to $email! (New balance: ${res['new_balance']} credits)'),
                                              duration: const Duration(seconds: 4),
                                            ),
                                          );
                                        }
                                      } else {
                                        setDialogState(() {
                                          isSubmitting = false;
                                          errorText = res['error'] ?? 'Failed to grant credits. Verify user exists.';
                                        });
                                      }
                                    } catch (err) {
                                      setDialogState(() {
                                        isSubmitting = false;
                                        errorText = 'Error: $err';
                                      });
                                    }
                                  },
                            icon: isSubmitting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.check_circle_outline, size: 16),
                            label: Text(isSubmitting ? 'Granting...' : 'Grant Credits'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 3: BRAND OFFERS
  // ==========================================
  Widget _buildBrandOffersTab(List offers) {
    if (offers.isEmpty) {
      return _buildEmptyTabState(
        'No Brand Offers',
        'Partner offers in MPT_brand_offers will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: offers.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final b = offers[i] as Map<String, dynamic>;
        final status = b['status'] as String? ?? 'ACTIVE';

        return Card(
          color: AppTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2E334D)),
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
                        '${b['brand_name'] ?? "Brand"} • ${b['product_title'] ?? ""}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: status == 'ACTIVE'
                            ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: status == 'ACTIVE' ? AppTheme.accentSuccess : Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Domain: ${b['brand_domain'] ?? "N/A"}  •  Retail: \$${b['retail_price'] ?? 0}  •  Host: \$${b['organizer_price'] ?? 0}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 4),
                Text(
                  '📊 ${b['clicks_count'] ?? 0} clicks  •  Assigned to ${b['games_assigned_count'] ?? 0} games',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 4: BRAND APPROVALS
  // ==========================================
  Widget _buildBrandApprovalsTab(List approvals) {
    if (approvals.isEmpty) {
      return _buildEmptyTabState(
        'No Brand Approvals',
        'Custom corporate brand approval submissions will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: approvals.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final a = approvals[i] as Map<String, dynamic>;
        final status = a['status'] as String? ?? 'PENDING';
        final statusColor = status == 'APPROVED'
            ? AppTheme.accentSuccess
            : (status == 'PENDING' ? Colors.amberAccent : AppTheme.accentDanger);

        return Card(
          color: AppTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2E334D)),
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
                        a['organization_name'] as String? ?? 'Organization',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Approver Email: ${a['approver_email'] ?? "None"}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Game ID: ${a['game_id'] ?? "Global"}',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                    ),
                    if (a['created_at'] != null)
                      Text(
                        Formatters.formatShortDate(DateTime.parse(a['created_at'])),
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 3: STRIPE PAYMENTS DRILL-DOWN LEDGER
  // ==========================================
  Widget _buildPaymentsTab(List payments, Map<String, dynamic> metrics) {
    if (payments.isEmpty) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: ref.read(adminReportsRepositoryProvider).getPaymentsLedger(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.secondaryColor),
            );
          }
          final loaded = snapshot.data ?? [];
          return _renderPaymentsList(loaded, metrics);
        },
      );
    }
    return _renderPaymentsList(payments, metrics);
  }

  Widget _renderPaymentsList(List payments, Map<String, dynamic> metrics) {
    final filtered = payments.where((item) {
      final p = item as Map<String, dynamic>;
      final email = (p['email'] as String? ?? '').toLowerCase();
      final pack = (p['pack'] as String? ?? '').toLowerCase();
      final pRef = (p['provider_ref'] as String? ?? '').toLowerCase();

      final isTest = p['is_test_mode'] == true ||
          pRef.contains('_test_') ||
          pRef.startsWith('cs_test_') ||
          pRef.startsWith('pi_test_');

      if (_paymentModeFilter == 'TEST' && !isTest) return false;
      if (_paymentModeFilter == 'LIVE' && isTest) return false;

      if (_paymentSearchQuery.isNotEmpty) {
        final q = _paymentSearchQuery.toLowerCase();
        return email.contains(q) || pack.contains(q) || pRef.contains(q);
      }
      return true;
    }).toList();

    num totalVolume = 0;
    int testCount = 0;
    int liveCount = 0;

    for (final item in payments) {
      final p = item as Map<String, dynamic>;
      final amt = (p['amount_usd'] as num?) ?? 0;
      totalVolume += amt;
      final pRef = (p['provider_ref'] as String? ?? '').toLowerCase();
      final isTest = p['is_test_mode'] == true ||
          pRef.contains('_test_') ||
          pRef.startsWith('cs_test_') ||
          pRef.startsWith('pi_test_');
      if (isTest) {
        testCount++;
      } else {
        liveCount++;
      }
    }

    return Column(
      children: [
        // Payments Summary Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF131728),
            border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top metric badges
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPaymentSummaryBadge(
                      label: 'Total Volume',
                      value: '\$${totalVolume.toStringAsFixed(2)} USD',
                      color: const Color(0xFF10B981),
                      icon: Icons.payments_outlined,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentSummaryBadge(
                      label: 'All Transactions',
                      value: '${payments.length}',
                      color: Colors.white,
                      icon: Icons.receipt_long,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentSummaryBadge(
                      label: 'Test Sandbox',
                      value: '$testCount test',
                      color: Colors.amberAccent,
                      icon: Icons.science_outlined,
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentSummaryBadge(
                      label: 'Production Live',
                      value: '$liveCount live',
                      color: const Color(0xFF38BDF8),
                      icon: Icons.verified_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Filter Chips & Search
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _paymentSearchQuery = val.trim()),
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search by customer email, pack, or session ID...',
                          hintStyle:
                              const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.search,
                              size: 16, color: Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('All', style: TextStyle(fontSize: 11)),
                        selected: _paymentModeFilter == 'ALL',
                        selectedColor: AppTheme.secondaryColor,
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _paymentModeFilter = 'ALL'),
                      ),
                      ChoiceChip(
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🧪 Test Only', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        selected: _paymentModeFilter == 'TEST',
                        selectedColor: Colors.amberAccent,
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _paymentModeFilter = 'TEST'),
                      ),
                      ChoiceChip(
                        label: const Text('🟢 Live Only',
                            style: TextStyle(fontSize: 11)),
                        selected: _paymentModeFilter == 'LIVE',
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _paymentModeFilter = 'LIVE'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // List of Payments
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyTabState(
                  'No Stripe Transactions Found',
                  _paymentSearchQuery.isNotEmpty
                      ? 'No payments match your search filter.'
                      : 'Completed customer checkout purchases will appear here in real time.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = filtered[i] as Map<String, dynamic>;
                    final pRef =
                        (p['provider_ref'] as String? ?? '').toLowerCase();
                    final isTest = p['is_test_mode'] == true ||
                        pRef.contains('_test_') ||
                        pRef.startsWith('cs_test_') ||
                        pRef.startsWith('pi_test_');

                    final amount = (p['amount_usd'] as num?) ?? 0;
                    final credits = (p['credits'] as num?)?.toInt() ?? 0;
                    final packName = p['pack'] as String? ?? 'Credits Pack';
                    final email = p['email'] as String? ?? 'No Email';
                    final status =
                        (p['status'] as String? ?? 'completed').toUpperCase();
                    final createdAt = p['created_at'] as String?;

                    return Card(
                      color: AppTheme.darkCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isTest
                              ? Colors.amber.withValues(alpha: 0.5)
                              : const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Amount & Mode Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isTest
                                          ? Colors.amber.withValues(alpha: 0.15)
                                          : const Color(0xFF10B981)
                                              .withValues(alpha: 0.15),
                                      child: Icon(
                                        isTest
                                            ? Icons.science_outlined
                                            : Icons.payments_outlined,
                                        size: 16,
                                        color: isTest
                                            ? Colors.amberAccent
                                            : const Color(0xFF10B981),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '\$${amount.toStringAsFixed(2)} ${p['currency'] ?? 'USD'}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondaryColor
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '+$credits credits',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.secondaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Test vs Live Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isTest
                                        ? Colors.amber.withValues(alpha: 0.15)
                                        : const Color(0xFF10B981)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isTest
                                          ? Colors.amberAccent
                                          : const Color(0xFF10B981),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isTest
                                            ? Icons.science
                                            : Icons.verified,
                                        size: 12,
                                        color: isTest
                                            ? Colors.amberAccent
                                            : const Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isTest
                                            ? 'TEST TRANSACTION'
                                            : 'LIVE PAYMENT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isTest
                                              ? Colors.amberAccent
                                              : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Payer Info
                            Row(
                              children: [
                                const Icon(Icons.email_outlined,
                                    size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Pack & Date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Pack: ${packName.toUpperCase()}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                                if (createdAt != null)
                                  Text(
                                    Formatters.formatShortDate(
                                        DateTime.parse(createdAt)),
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Stripe Ref ID with copy button
                            Row(
                              children: [
                                const Text(
                                  'Stripe Ref: ',
                                  style: TextStyle(
                                      fontSize: 10.5, color: Color(0xFF64748B)),
                                ),
                                Expanded(
                                  child: Text(
                                    p['provider_ref'] ?? 'N/A',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                if (p['provider_ref'] != null)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.copy,
                                        size: 13, color: AppTheme.secondaryColor),
                                    tooltip: 'Copy Stripe Session ID',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text: p['provider_ref'].toString()));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Stripe reference ID copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPaymentSummaryBadge({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2238),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8))),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: REGISTERED USERS & PLAYERS DRILL-DOWN
  // ==========================================
  Widget _buildUsersTab(List users, Map<String, dynamic> metrics) {
    if (users.isEmpty) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future:
            ref.read(adminReportsRepositoryProvider).getRegisteredUsersList(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.secondaryColor),
            );
          }
          final loaded = snapshot.data ?? [];
          return _renderUsersList(loaded, metrics);
        },
      );
    }
    return _renderUsersList(users, metrics);
  }

  Widget _renderUsersList(List users, Map<String, dynamic> metrics) {
    final filtered = users.where((item) {
      final u = item as Map<String, dynamic>;
      final email = (u['email'] as String? ?? '').toLowerCase();
      final name = (u['display_name'] as String? ?? '').toLowerCase();
      final uid = (u['user_id'] as String? ?? u['id'] as String? ?? '').toLowerCase();
      final hostedCount = (u['games_hosted_count'] as num?)?.toInt() ?? 0;

      if (_userTypeFilter == 'ORGANIZERS' && hostedCount == 0) return false;
      if (_userTypeFilter == 'PLAYERS' && hostedCount > 0) return false;

      if (_userSearchQuery.isNotEmpty) {
        final q = _userSearchQuery.toLowerCase();
        return email.contains(q) || name.contains(q) || uid.contains(q);
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Controls bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF131728),
            border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _userSearchQuery = val.trim()),
                        style: const TextStyle(fontSize: 12.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search users by name, email, or user ID...',
                          hintStyle:
                              const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.search,
                              size: 16, color: Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('All Users',
                            style: TextStyle(fontSize: 11)),
                        selected: _userTypeFilter == 'ALL',
                        selectedColor: AppTheme.secondaryColor,
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _userTypeFilter = 'ALL'),
                      ),
                      ChoiceChip(
                        label: const Text('Organizers',
                            style: TextStyle(fontSize: 11)),
                        selected: _userTypeFilter == 'ORGANIZERS',
                        selectedColor: AppTheme.primaryLight,
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _userTypeFilter = 'ORGANIZERS'),
                      ),
                      ChoiceChip(
                        label: const Text('Players Only',
                            style: TextStyle(fontSize: 11)),
                        selected: _userTypeFilter == 'PLAYERS',
                        selectedColor: AppTheme.accentSuccess,
                        backgroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        onSelected: (_) =>
                            setState(() => _userTypeFilter = 'PLAYERS'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Users List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyTabState(
                  'No Users Found',
                  _userSearchQuery.isNotEmpty
                      ? 'No user accounts match your search filter.'
                      : 'All players and organizers who register will appear here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final u = filtered[i] as Map<String, dynamic>;
                    final email = u['email'] as String? ?? 'No Email';
                    final name = u['display_name'] as String? ?? 'Player';
                    final role = (u['role'] as String? ?? 'PLAYER').toUpperCase();
                    final isAdmin = role == 'ADMIN';
                    final isHost = role == 'HOST' ||
                        ((u['games_hosted_count'] as num?)?.toInt() ?? 0) > 0;
                    final credits =
                        (u['credits_balance'] as num?)?.toInt() ?? 0;
                    final gamesHosted =
                        (u['games_hosted_count'] as num?)?.toInt() ?? 0;
                    final gamesJoined =
                        (u['games_joined_count'] as num?)?.toInt() ?? 0;
                    final registeredAt =
                        u['registered_at'] as String? ?? u['created_at'] as String?;
                    final userId =
                        (u['user_id'] as String? ?? u['id'] as String? ?? '');

                    return Card(
                      color: AppTheme.darkCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isAdmin
                              ? AppTheme.secondaryColor.withValues(alpha: 0.6)
                              : isHost
                                  ? AppTheme.primaryLight.withValues(alpha: 0.4)
                                  : const Color(0xFF2E334D),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isAdmin
                                  ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                                  : isHost
                                      ? AppTheme.primaryLight.withValues(alpha: 0.2)
                                      : const Color(0xFF334155),
                              child: Icon(
                                isAdmin
                                    ? Icons.shield
                                    : isHost
                                        ? Icons.sports_esports
                                        : Icons.person_outline,
                                color: isAdmin
                                    ? AppTheme.secondaryColor
                                    : isHost
                                        ? AppTheme.primaryLight
                                        : Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isAdmin
                                              ? AppTheme.secondaryColor
                                                  .withValues(alpha: 0.2)
                                              : isHost
                                                  ? AppTheme.primaryLight
                                                      .withValues(alpha: 0.2)
                                                  : Colors.white10,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          role,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isAdmin
                                                ? AppTheme.secondaryColor
                                                : isHost
                                                    ? AppTheme.primaryLight
                                                    : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        '🎮 $gamesHosted hosted',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8)),
                                      ),
                                      Text(
                                        '🎟️ $gamesJoined joined',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8)),
                                      ),
                                      if (credits > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.secondaryColor
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '💳 $credits credits',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.secondaryColor,
                                            ),
                                          ),
                                        ),
                                      if (registeredAt != null)
                                        Text(
                                          '📅 Joined: ${Formatters.formatShortDate(DateTime.parse(registeredAt))}',
                                          style: const TextStyle(
                                              fontSize: 10.5,
                                              color: Color(0xFF64748B)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.secondaryColor,
                                side: BorderSide(
                                    color: AppTheme.secondaryColor
                                        .withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              onPressed: () => _showGrantCreditsDialog(
                                prefilledEmail: email != 'No Email' ? email : null,
                                prefilledUserId: userId.isNotEmpty ? userId : null,
                                currentCredits: credits,
                              ),
                              icon: const Icon(Icons.add_circle_outline, size: 14),
                              label: const Text('Add Credits',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TICKETS & CLAIMS DRILL-DOWN MODAL
  // ==========================================
  void _showTicketsClaimsDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final summary =
        (fullData['tickets_claims_summary'] as Map<String, dynamic>?) ?? {};
    final prizeClaims = (summary['claims_by_prize'] as List?) ?? [];
    final topGames = (summary['top_games_by_tickets'] as List?) ?? [];

    final totalTickets = summary['total_tickets'] ?? metrics['total_tickets'] ?? 0;
    final totalClaims = summary['total_claims'] ?? metrics['total_claims'] ?? 0;
    final approvedClaims = summary['approved_claims'] ?? 0;
    final rejectedClaims = summary['rejected_claims'] ?? 0;
    final approvalRate = (totalClaims as num) > 0
        ? (((approvedClaims as num) / totalClaims) * 100).toStringAsFixed(1)
        : '0.0';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.confirmation_number_outlined,
                            color: AppTheme.secondaryColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Platform Tickets & Claims Analytics',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Comprehensive verification rate & prize distribution',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Cards Grid
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Tickets',
                                value: '$totalTickets',
                                color: AppTheme.secondaryColor,
                                icon: Icons.confirmation_number_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Verified Claims',
                                value: '$totalClaims',
                                color: AppTheme.accentSuccess,
                                icon: Icons.verified_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Approval Rate',
                                value: '$approvalRate%',
                                color: const Color(0xFF38BDF8),
                                icon: Icons.pie_chart_outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Claims Breakdown
                        const Text(
                          'CLAIM VERIFICATION AUDIT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            children: [
                              _buildAuditRow(
                                  'Approved Claims (Prizes Won)',
                                  '$approvedClaims',
                                  AppTheme.accentSuccess),
                              const Divider(height: 16, color: Color(0xFF1E293B)),
                              _buildAuditRow(
                                  'Rejected Claims (Bogus / Late)',
                                  '$rejectedClaims',
                                  Colors.redAccent),
                              const Divider(height: 16, color: Color(0xFF1E293B)),
                              _buildAuditRow(
                                  'Pending Claims In Review',
                                  '${summary['pending_claims'] ?? 0}',
                                  Colors.amberAccent),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Prize Distribution Breakdown
                        const Text(
                          'CLAIMS BY PRIZE TYPE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (prizeClaims.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Standard 6 prize categories: Early Five, Top Line, Middle Line, Bottom Line, Corners, and Full House. Claims will appear as players win.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          )
                        else
                          Column(
                            children: prizeClaims.map((pz) {
                              final pMap = pz as Map<String, dynamic>;
                              final pzType = pMap['prize_type'] ?? 'Prize';
                              final count = pMap['count'] ?? 0;
                              final approved = pMap['approved_count'] ?? 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2238),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$pzType',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                    Text(
                                      '$approved approved / $count submitted',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.secondaryColor),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        if (topGames.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'TOP GAMES BY TICKET VOLUME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: topGames.map((tg) {
                              final gMap = tg as Map<String, dynamic>;
                              final gName = gMap['name'] ?? 'Game';
                              final gCode = gMap['invite_code'] ?? '------';
                              final tCount = gMap['tickets_count'] ?? 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('$gName ($gCode)',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white)),
                                    Text('$tCount tickets',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.secondaryColor)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // DRILLDOWN MODAL 1: STRIPE PAYMENTS & LEDGER
  // ==========================================
  void _showPaymentsDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final payments = (fullData['recent_payments'] as List?) ?? [];

    final totalCount = metrics['total_payments_count'] ?? payments.length;
    final totalRev = ((metrics['total_revenue_amount'] ?? 0) as num).toDouble();

    int testCount = 0;
    for (final p in payments) {
      final m = p as Map<String, dynamic>;
      final ref = m['provider_ref']?.toString().toLowerCase() ?? '';
      final isTest = m['is_test_mode'] == true ||
          ref.contains('_test_') ||
          ref.startsWith('cs_test_') ||
          ref.startsWith('pi_test_');
      if (isTest) testCount++;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.payments_outlined,
                            color: Color(0xFF10B981), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stripe Financial & Revenue Drilldown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Payment audit trail, test transactions verification & volume',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Cards Grid
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Payments',
                                value: '$totalCount',
                                color: const Color(0xFF10B981),
                                icon: Icons.receipt_long,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Gross Volume (USD)',
                                value: '\$${totalRev.toStringAsFixed(2)}',
                                color: AppTheme.secondaryColor,
                                icon: Icons.attach_money,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Test Mode Transactions',
                                value: '$testCount of ${payments.length}',
                                color: testCount > 0 ? Colors.amberAccent : const Color(0xFF10B981),
                                icon: Icons.science_outlined,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Answer to User Query: Test Mode Verification Banner
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: testCount > 0
                                ? Colors.amber.withValues(alpha: 0.12)
                                : const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: testCount > 0
                                  ? Colors.amber.withValues(alpha: 0.4)
                                  : const Color(0xFF10B981).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                testCount > 0 ? Icons.bug_report_outlined : Icons.check_circle_outline,
                                color: testCount > 0 ? Colors.amber : const Color(0xFF10B981),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      testCount > 0
                                          ? '🧪 TEST TRANSACTION VERIFICATION CONFIRMED'
                                          : '🟢 LIVE STRIPE PAYMENTS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: testCount > 0 ? Colors.amber : const Color(0xFF10B981),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      testCount > 0
                                          ? '$testCount recorded Stripe transaction(s) used Stripe Test Mode (provider ref starts with "cs_test_" or "pi_test_"). These are verified sandbox test sessions — no real credit card was charged.'
                                          : 'All recorded transactions were settled in Stripe production mode.',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                        const Text(
                          'TRANSACTION LEDGER BREAKDOWN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (payments.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'No payment records found in database.',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: payments.map((p) {
                              final pMap = p as Map<String, dynamic>;
                              final ref = pMap['provider_ref']?.toString() ?? 'N/A';
                              final isTest = pMap['is_test_mode'] == true ||
                                  ref.toLowerCase().contains('_test_') ||
                                  ref.toLowerCase().startsWith('cs_test_');
                              final pack = pMap['pack']?.toString() ?? 'Credit Pack';
                              final credits = pMap['credits']?.toString() ?? '0';
                              final amt = pMap['amount_usd']?.toString() ?? '0.00';
                              final email = pMap['email']?.toString() ?? 'No Email';
                              final status = pMap['status']?.toString().toUpperCase() ?? 'COMPLETED';
                              final date = pMap['created_at'] != null
                                  ? Formatters.formatShortDate(DateTime.tryParse(pMap['created_at'].toString()) ?? DateTime.now())
                                  : 'Recently';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isTest
                                        ? Colors.amber.withValues(alpha: 0.3)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              pack,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isTest
                                                    ? Colors.amber.withValues(alpha: 0.15)
                                                    : const Color(0xFF10B981).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isTest ? '🧪 TEST TRANSACTION' : '🟢 LIVE PAYMENT',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: isTest ? Colors.amber : const Color(0xFF10B981),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '\$$amt USD',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.email_outlined, size: 13, color: Color(0xFF94A3B8)),
                                        const SizedBox(width: 4),
                                        Text(email, style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                                        const SizedBox(width: 14),
                                        const Icon(Icons.token, size: 13, color: AppTheme.secondaryColor),
                                        const SizedBox(width: 4),
                                        Text('$credits credits', style: const TextStyle(fontSize: 11.5, color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
                                        const Spacer(),
                                        Text(status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Ref: $ref',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF64748B)),
                                          ),
                                        ),
                                        Text(date, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.tab, size: 16, color: AppTheme.secondaryColor),
                        label: const Text('Go to Stripe Payments Tab', style: TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _tabController.animateTo(2);
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // DRILLDOWN MODAL 2: TOTAL GAMES & QUORUM
  // ==========================================
  void _showGamesDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final games = (fullData['recent_games'] as List?) ?? [];

    final totalGames = metrics['total_games'] ?? games.length;
    final activeGames = metrics['active_games'] ?? 0;
    final completedGames = metrics['completed_games'] ?? 0;

    int quorumMetCount = 0;
    for (final g in games) {
      final gMap = g as Map<String, dynamic>;
      final confirmed = (gMap['confirmed_players_count'] as num?)?.toInt() ?? 0;
      if (confirmed >= 2) quorumMetCount++;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.sports_esports,
                            color: AppTheme.primaryLight, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Games & Quorum Activity Drilldown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Capacity tiers, active sessions, and quorum thresholds',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Mini Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Games',
                                value: '$totalGames',
                                color: AppTheme.primaryLight,
                                icon: Icons.casino,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Active Sessions',
                                value: '$activeGames',
                                color: AppTheme.accentSuccess,
                                icon: Icons.play_circle_outline,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Completed Games',
                                value: '$completedGames',
                                color: const Color(0xFF94A3B8),
                                icon: Icons.check_circle_outline,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Quorum Met (≥ 2)',
                                value: '$quorumMetCount',
                                color: AppTheme.secondaryColor,
                                icon: Icons.groups_outlined,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Text(
                          'RECENT GAMES SUMMARY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (games.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No games created yet.', style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          )
                        else
                          Column(
                            children: games.take(12).map((g) {
                              final gMap = g as Map<String, dynamic>;
                              final name = gMap['name'] ?? 'Unnamed Game';
                              final code = gMap['invite_code'] ?? '------';
                              final status = (gMap['status'] ?? 'OPEN').toString().toUpperCase();
                              final tier = gMap['capacity_tier_name'] ?? 'Family Pack';
                              final host = gMap['host_identifier'] ?? 'Host';
                              final confirmed = (gMap['confirmed_players_count'] as num?)?.toInt() ?? 0;
                              final quorum = confirmed >= 2;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                              const SizedBox(width: 8),
                                              Text('($code)', style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor, fontFamily: 'monospace')),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text('Host: $host • Tier: $tier', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: quorum ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        quorum ? '✓ Quorum Met ($confirmed)' : 'Quorum Pending ($confirmed)',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: quorum ? const Color(0xFF10B981) : Colors.amber,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _getStatusColor(status)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.tab, size: 16, color: AppTheme.secondaryColor),
                        label: const Text('Go to Games Tab', style: TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _tabController.animateTo(0);
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // DRILLDOWN MODAL 3: USERS & HOSTS DIRECTORY
  // ==========================================
  void _showUsersDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final users = (fullData['recent_users'] as List?) ?? [];
    final hosts = (fullData['recent_hosts'] as List?) ?? [];

    final registeredUsersCount = metrics['total_registered_users'] ?? users.where((u) => (u as Map)['is_anonymous'] != true).length;
    final totalUsersCount = metrics['total_users'] ?? users.length;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.people_outline,
                            color: AppTheme.accentSuccess, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Registered Users & Hosts Directory',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Accounts breakdown, organizer privileges & wallet balances',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Mini Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Email Reg. Users',
                                value: '$registeredUsersCount',
                                color: AppTheme.accentSuccess,
                                icon: Icons.how_to_reg_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Player Profiles',
                                value: '$totalUsersCount',
                                color: Colors.white70,
                                icon: Icons.group_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Active Hosts (Wallets)',
                                value: '${hosts.length}',
                                color: AppTheme.secondaryColor,
                                icon: Icons.admin_panel_settings_outlined,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Answer to User Query: Host Count Explanation Banner
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ℹ️ HOST DIRECTORY EXPLANATION',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF38BDF8),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Currently, ${hosts.length} user (${hosts.isNotEmpty ? (hosts.first['email'] ?? 'you') : 'your account'}) is registered as a financial organizer with wallet credits in MPT_admin_profiles. When any registered user creates their first game or receives organizer credits, they automatically appear in the Hosts tab directory.',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                        const Text(
                          'REGISTERED ACCOUNTS DIRECTORY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (users.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No users found in database.', style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          )
                        else
                          Column(
                            children: users.take(15).map((u) {
                              final uMap = u as Map<String, dynamic>;
                              final dName = uMap['display_name'] ?? 'Player';
                              final email = uMap['email'] ?? 'Anonymous';
                              final role = (uMap['role'] ?? 'PLAYER').toString().toUpperCase();
                              final isAnon = uMap['is_anonymous'] == true;
                              final credits = uMap['credits_balance'] ?? 0;
                              final hosted = uMap['games_hosted_count'] ?? 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isAnon ? const Color(0xFF334155) : AppTheme.secondaryColor.withValues(alpha: 0.2),
                                      child: Text(
                                        dName.isNotEmpty ? dName[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isAnon ? Colors.white60 : AppTheme.secondaryColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(dName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                          Text('$email • $hosted hosted', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                        ],
                                      ),
                                    ),
                                    if (credits > 0)
                                      Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '$credits cr',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.secondaryColor),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: role == 'ADMIN'
                                            ? Colors.purpleAccent.withValues(alpha: 0.2)
                                            : role == 'HOST'
                                                ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                                                : const Color(0xFF334155),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: role == 'ADMIN'
                                              ? Colors.purpleAccent
                                              : role == 'HOST'
                                                  ? AppTheme.secondaryColor
                                                  : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.tab, size: 16, color: AppTheme.secondaryColor),
                        label: const Text('Go to Reg. Users Tab', style: TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _tabController.animateTo(3);
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // DRILLDOWN MODAL 4: BRAND OFFERS
  // ==========================================
  void _showBrandOffersDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final offers = (fullData['brand_offers'] as List?) ?? [];

    final totalOffers = metrics['total_brand_offers'] ?? offers.length;
    final activeOffers = metrics['active_brand_offers'] ?? 0;

    int totalClicks = 0;
    for (final o in offers) {
      final oMap = o as Map<String, dynamic>;
      totalClicks += (oMap['clicks_count'] as num?)?.toInt() ?? 0;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.card_giftcard,
                            color: Colors.amberAccent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Brand Offers & Marketplace Catalog',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Catalog engagement, partner discounts, and sponsor clicks',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Mini Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Offers',
                                value: '$totalOffers',
                                color: Colors.amberAccent,
                                icon: Icons.store_mall_directory_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Active in Catalog',
                                value: '$activeOffers',
                                color: const Color(0xFF10B981),
                                icon: Icons.check_circle_outline,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Clicks',
                                value: '$totalClicks',
                                color: AppTheme.secondaryColor,
                                icon: Icons.ads_click,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Text(
                          'FEATURED BRAND OFFERS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (offers.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No brand offers cataloged yet.', style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          )
                        else
                          Column(
                            children: offers.take(12).map((o) {
                              final oMap = o as Map<String, dynamic>;
                              final bName = oMap['brand_name'] ?? 'Brand';
                              final domain = oMap['brand_domain'] ?? '';
                              final title = oMap['product_title'] ?? 'Product Offer';
                              final retail = oMap['retail_price']?.toString() ?? '0';
                              final organizer = oMap['organizer_price']?.toString() ?? '0';
                              final discount = oMap['discount_percent'] ?? 0;
                              final clicks = oMap['clicks_count'] ?? 0;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('$bName • $title', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                          const SizedBox(height: 2),
                                          Text(domain, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('\$$organizer (was \$$retail)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                                        Text('$discount% OFF • $clicks clicks', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.tab, size: 16, color: AppTheme.secondaryColor),
                        label: const Text('Go to Brand Offers Tab', style: TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _tabController.animateTo(4);
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // DRILLDOWN MODAL 5: BRAND APPROVALS
  // ==========================================
  void _showBrandApprovalsDrilldownModal(Map<String, dynamic> fullData) {
    final metrics = (fullData['metrics'] as Map<String, dynamic>?) ?? {};
    final approvals = (fullData['brand_approvals'] as List?) ?? [];

    final totalApprovals = metrics['total_brand_approvals'] ?? approvals.length;
    final pendingApprovals = metrics['pending_brand_approvals'] ?? 0;

    int approvedCount = 0;
    for (final a in approvals) {
      final aMap = a as Map<String, dynamic>;
      if ((aMap['status']?.toString().toUpperCase() ?? '') == 'APPROVED') approvedCount++;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF16192E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF2E334D))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentInfo.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.verified_user,
                            color: AppTheme.accentInfo, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Brand Co-Host Sponsorship Approvals',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Corporate sponsorship verification, tokens, and audit state',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Mini Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Total Requests',
                                value: '$totalApprovals',
                                color: AppTheme.accentInfo,
                                icon: Icons.folder_shared_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Pending Review',
                                value: '$pendingApprovals',
                                color: Colors.amberAccent,
                                icon: Icons.hourglass_top,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricMiniCard(
                                label: 'Approved Co-Hosts',
                                value: '$approvedCount',
                                color: const Color(0xFF10B981),
                                icon: Icons.verified,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Text(
                          'SPONSORSHIP APPROVAL STATUS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (approvals.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No sponsorship approvals requested yet.', style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          )
                        else
                          Column(
                            children: approvals.take(12).map((a) {
                              final aMap = a as Map<String, dynamic>;
                              final org = aMap['organization_name'] ?? 'Organization';
                              final email = aMap['approver_email'] ?? 'No Email';
                              final status = (aMap['status'] ?? 'PENDING').toString().toUpperCase();
                              final isPending = status == 'PENDING';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(org, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                          const SizedBox(height: 2),
                                          Text('Approver: $email', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPending ? Colors.amber.withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isPending ? Colors.amber : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Dialog Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2238),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.tab, size: 16, color: AppTheme.secondaryColor),
                        label: const Text('Go to Brand Approvals Tab', style: TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          _tabController.animateTo(5);
                        },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricMiniCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTabState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'OPEN':
      case 'READY_TO_START':
        return AppTheme.accentSuccess;
      case 'STARTING':
      case 'IN_PROGRESS':
        return AppTheme.secondaryColor;
      case 'COMPLETED':
        return AppTheme.primaryLight;
      case 'CANCELLED':
      case 'CLOSED':
        return AppTheme.accentDanger;
      default:
        return Colors.white70;
    }
  }
}
