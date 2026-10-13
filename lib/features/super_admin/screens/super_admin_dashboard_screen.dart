import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/app_providers.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        final brandOffers = (data['brand_offers'] as List?) ?? [];
        final brandApprovals = (data['brand_approvals'] as List?) ?? [];

        return Column(
          children: [
            // Top Executive KPI Strip
            _buildExecutiveSummaryHeader(metrics, adminEmail),

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
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Reg. Users',
                  value: '${m['total_registered_users'] ?? 0}',
                  subText: '${m['total_users'] ?? 0} total player profiles',
                  icon: Icons.people,
                  color: AppTheme.accentSuccess,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Tickets & Claims',
                  value: '${m['total_tickets'] ?? 0}',
                  subText: '${m['total_claims'] ?? 0} verified claims',
                  icon: Icons.confirmation_number_outlined,
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Brand Offers',
                  value: '${m['total_brand_offers'] ?? 0}',
                  subText: '${m['active_brand_offers'] ?? 0} active in catalog',
                  icon: Icons.card_giftcard,
                  color: Colors.amberAccent,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Brand Approvals',
                  value: '${m['total_brand_approvals'] ?? 0}',
                  subText: '${m['pending_brand_approvals'] ?? 0} pending review',
                  icon: Icons.verified_user,
                  color: AppTheme.accentInfo,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: 'Stripe Payments',
                  value: '${m['total_payments_count'] ?? 0}',
                  subText: '\$${((m['total_revenue_amount'] ?? 0) as num).toStringAsFixed(2)} volume',
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF10B981),
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
  }) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2238),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E334D)),
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
              Icon(icon, size: 16, color: color),
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
          const SizedBox(height: 2),
          Text(
            subText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: RECENT GAMES
  // ==========================================
  Widget _buildGamesTab(List games) {
    if (games.isEmpty) {
      return _buildEmptyTabState(
        'No games found',
        'Games will appear here once organizers create them.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: games.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final g = games[i] as Map<String, dynamic>;
        final status = g['status'] as String? ?? 'OPEN';
        final statusColor = _getStatusColor(status);

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
                        g['name'] as String? ?? 'Untitled Game',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                    const SizedBox(width: 12),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '👥 ${g['player_count'] ?? 0} Players  •  🏆 ${g['claims_count'] ?? 0} Claims  •  Cap: ${g['initial_funded_capacity'] ?? 25}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                    if (g['created_at'] != null)
                      Text(
                        Formatters.formatShortDate(DateTime.parse(g['created_at'])),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          final gameId = g['id'] as String?;
                          if (gameId != null) {
                            context.push('/game-status/$gameId');
                          }
                        },
                        icon: const Icon(Icons.visibility_outlined, size: 14),
                        label: const Text('Status Screen', style: TextStyle(fontSize: 11)),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          final gameId = g['id'] as String?;
                          if (gameId != null) {
                            context.push('/live-display/$gameId');
                          }
                        },
                        icon: const Icon(Icons.tv, size: 14),
                        label: const Text('Live TV Display', style: TextStyle(fontSize: 11)),
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
  // TAB 2: REGISTERED HOSTS
  // ==========================================
  Widget _buildHostsTab(List hosts) {
    if (hosts.isEmpty) {
      return _buildEmptyTabState(
        'No Host Profiles Found',
        'Organizers who register with contact info or make purchases will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: hosts.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final h = hosts[i] as Map<String, dynamic>;
        final role = h['role'] as String? ?? 'HOST';
        final isAdmin = role.toUpperCase() == 'ADMIN';

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
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🎮 ${h['games_created_count'] ?? 0} games created  •  💳 ${h['available_credits'] ?? 0} credits',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                          if (h['created_at'] != null)
                            Text(
                              Formatters.formatShortDate(DateTime.parse(h['created_at'])),
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                            ),
                        ],
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
