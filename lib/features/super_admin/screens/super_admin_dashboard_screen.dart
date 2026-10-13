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

  // Games Filter States
  String _selectedTierFilter = 'ALL';
  bool _hideBelowQuorum = false;
  String _visibilityFilter = 'ALL'; // 'ALL', 'PUBLIC', 'HIDDEN'
  String _searchQuery = '';

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
                  children: [
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
                                            '${n['called_number']}',
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
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(dialogCtx);
                                    context.push('/live-display/$gameId');
                                  },
                                  icon: const Icon(Icons.tv, size: 14),
                                  label: const Text('Live TV', style: TextStyle(fontSize: 11)),
                                ),
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
