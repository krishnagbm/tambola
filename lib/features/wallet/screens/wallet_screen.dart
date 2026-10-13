import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_wallet.dart';
import '../../../providers/app_providers.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../auth/widgets/auth_dialog.dart';
import '../../home/widgets/corporate_inquiry_dialog.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isProcessing = false;
  String _ledgerFilter = 'PAID';
  final ScrollController _ledgerScrollController = ScrollController();

  @override
  void dispose() {
    _ledgerScrollController.dispose();
    super.dispose();
  }

  void _openPricingPage() {
    AuthGuard.requireHostAuth(context, ref, () {
      final user = ref.read(currentUserProvider).value;
      final wallet = ref.read(walletProvider).value;
      ref.read(walletRepositoryProvider).launchWebPurchaseHandoff(
        userId: user?.id,
        adminEmail: user?.email,
        displayName: user?.displayName,
        avatar: user?.avatar,
        balance: wallet?.availableCredits,
      );
    });
  }

  Future<void> _handleAddMockCredits(int amount) async {
    setState(() => _isProcessing = true);
    try {
      await ref.read(walletRepositoryProvider).addMockCredits(amount);
      ref.invalidate(walletProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $amount Mock Credits! 🎉'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accentDanger),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final tiersState = ref.watch(capacityTiersProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Wallet',
        showBackButton: true,
        onRefresh: () {
          ref.invalidate(walletProvider);
          ref.invalidate(creditTransactionsProvider);
          ref.invalidate(organizerAllGamesClaimsProvider);
          ref.invalidate(currentUserProvider);
        },
      ),
      body: walletState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isTwoColumn = constraints.maxWidth >= 840;

              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBalanceCard(wallet),
                  const SizedBox(height: 20),
                  _buildPurchaseActions(),
                  const SizedBox(height: 24),
                  _buildPricingTiersSection(tiersState),
                  const SizedBox(height: 24),
                  _buildPolicyNotice(),
                ],
              );

              final rightColumn = _buildTransactionsList(isTwoColumn: isTwoColumn);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isTwoColumn ? 1180 : 680),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ref.watch(currentUserProvider).value?.isRegistered != true) ...[
                          _buildGuestAccountWarning(),
                          const SizedBox(height: 20),
                        ],
                        _buildOrganizerClaimsHubBanner(),
                        const SizedBox(height: 20),
                        if (isTwoColumn)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: leftColumn),
                              const SizedBox(width: 22),
                              Expanded(flex: 6, child: rightColumn),
                            ],
                          )
                        else ...[
                          leftColumn,
                          const SizedBox(height: 24),
                          rightColumn,
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOrganizerClaimsHubBanner() {
    final claimsSummaryAsync = ref.watch(organizerAllGamesClaimsProvider);
    final gamesCount = claimsSummaryAsync.valueOrNull?.length ?? 0;
    final unsettledCount =
        claimsSummaryAsync.valueOrNull?.fold<int>(
          0,
          (sum, g) => sum + g.unsettledCount,
        ) ??
        0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF172554), Color(0xFF1A1F35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: AppTheme.secondaryColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Conducted Games Claims & Brand Gift Store',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (unsettledCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.secondaryColor.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            child: Text(
                              '$unsettledCount Unsettled Claims',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                          )
                        else if (gamesCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentSuccess.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$gamesCount Games • All Settled ✓',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentSuccess,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'View all conducted games in collapsible drawers, inspect winner details & voucher codes, offer discounted Brand Publisher gifts, and close unsettled claims.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => context.push('/wallet/claims'),
            icon: const Icon(Icons.redeem_rounded, size: 17),
            label: const Text('Open Claims & Brand Gifts'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestAccountWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppTheme.secondaryColor, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organizer Account Required',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Guests cannot hold organizer credits or host games. Sign in with Google, Apple, Microsoft, or Email OTP to unlock organizer hosting & credit purchases.',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              minimumSize: Size.zero,
            ),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(MptWallet wallet) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.5), width: 1.5),
        gradient: LinearGradient(
          colors: [AppTheme.secondaryColor.withValues(alpha: 0.12), AppTheme.darkCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars, color: AppTheme.secondaryColor, size: 24),
              SizedBox(width: 8),
              Text('AVAILABLE BALANCE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${Formatters.formatCredits(wallet.availableCredits)} Credits',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.secondaryColor),
          ),
          if (wallet.availableCredits > 0) ...[
            const SizedBox(height: 8),
            Text(
              wallet.creditsExpireAt != null
                  ? 'Valid until: ${Formatters.formatDate(wallet.creditsExpireAt!)}'
                  : 'Credits valid for 1 year from your most recent paid game.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPurchaseActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kIsWeb) ...[
          ElevatedButton.icon(
            onPressed: _openPricingPage,
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Add Credits on Web (dabhousie.com)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.secondaryColor, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Credits can be added on our website at dabhousie.com to host larger games.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFE2E8F0), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (AppConfig.enableMockCredits) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : () => _handleAddMockCredits(200),
            icon: const Icon(Icons.flash_on, color: AppTheme.secondaryColor),
            label: const Text('Add 200 Mock Credits (Testing Mode)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPricingTiersSection(AsyncValue<List<MptCapacityTier>> tiersState) {
    final tiers = tiersState.value ?? MptCapacityTier.defaultTiers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Capacity Tiers & Credit Cost', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Column(
          children: [
            ...tiers.map((tier) {
              final isFree = tier.creditsRequired == 0;
              return Card(
                color: AppTheme.darkSurface,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tier.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('${tier.minPlayers}–${tier.maxPlayers} Players', style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (isFree ? AppTheme.accentSuccess : AppTheme.secondaryColor).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (isFree ? AppTheme.accentSuccess : AppTheme.secondaryColor).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          isFree ? 'FREE (0 Credits)' : '${tier.creditsRequired} Credits',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isFree ? AppTheme.accentSuccess : AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            Card(
              color: AppTheme.darkSurface,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 420;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.corporate_fare_rounded, color: AppTheme.secondaryColor, size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Mega-X Corporate',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Custom capacity (250 to 100K+ players), dedicated server scale & volume pricing.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.35),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => CorporateInquiryDialog.show(context, initialTopic: 'Mega-X Event (250 to 100,000+ Players)'),
                              icon: const Icon(Icons.mail_outline, size: 15, color: AppTheme.secondaryColor),
                              label: const Text('Contact Us →', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold, fontSize: 12.5)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.corporate_fare_rounded, color: AppTheme.secondaryColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Mega-X Corporate (250 to 100K+ Players)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                              SizedBox(height: 2),
                              Text('Custom capacity, dedicated server scale & volume pricing', style: TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => CorporateInquiryDialog.show(context, initialTopic: 'Mega-X Event (250 to 100,000+ Players)'),
                          child: const Text('Contact Us →', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPolicyNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentInfo.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.accentInfo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info_outline, size: 16, color: AppTheme.accentInfo),
              ),
              const SizedBox(width: 10),
              const Text(
                'Credit Policy & Rules',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.accentInfo),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPolicyBullet('Credits are charged automatically at game start according to confirmed player count.'),
          const SizedBox(height: 8),
          _buildPolicyBullet('Unused credits remain in your wallet for future events.'),
          const SizedBox(height: 8),
          _buildPolicyBullet('Credits are non-refundable and expire 1 year after your most recent paid game.'),
        ],
      ),
    );
  }

  Widget _buildPolicyBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6, right: 10),
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppTheme.accentInfo,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.45),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsList({required bool isTwoColumn}) {
    final txsAsync = ref.watch(creditTransactionsProvider);

    return txsAsync.when(
      loading: () => Container(
        height: isTwoColumn ? 400 : 200,
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, stack) => const SizedBox(),
      data: (txs) {
        final paidTxs = txs.where((t) => t.amount != 0).toList();
        final freeTxs = txs.where((t) => t.amount == 0).toList();
        final displayedTxs = _ledgerFilter == 'PAID'
            ? paidTxs
            : (_ledgerFilter == 'FREE' ? freeTxs : txs);

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: AppTheme.secondaryColor, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Credit History & Ledger',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    if (txs.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '${displayedTxs.length} of ${txs.length}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF93C5FD)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildLedgerFilterChip(
                      label: 'Credit Activity',
                      count: paidTxs.length,
                      icon: Icons.payments_outlined,
                      isSelected: _ledgerFilter == 'PAID',
                      onTap: () {
                        setState(() => _ledgerFilter = 'PAID');
                        if (_ledgerScrollController.hasClients) {
                          _ledgerScrollController.jumpTo(0);
                        }
                      },
                    ),
                    _buildLedgerFilterChip(
                      label: 'Family Pack (0 Cr)',
                      count: freeTxs.length,
                      icon: Icons.family_restroom_rounded,
                      isSelected: _ledgerFilter == 'FREE',
                      onTap: () {
                        setState(() => _ledgerFilter = 'FREE');
                        if (_ledgerScrollController.hasClients) {
                          _ledgerScrollController.jumpTo(0);
                        }
                      },
                    ),
                    _buildLedgerFilterChip(
                      label: 'All Activity',
                      count: txs.length,
                      icon: Icons.list_alt_rounded,
                      isSelected: _ledgerFilter == 'ALL',
                      onTap: () {
                        setState(() => _ledgerFilter = 'ALL');
                        if (_ledgerScrollController.hasClients) {
                          _ledgerScrollController.jumpTo(0);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1E293B)),
              if (displayedTxs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _ledgerFilter == 'FREE'
                              ? Icons.family_restroom_rounded
                              : (_ledgerFilter == 'PAID'
                                  ? Icons.payments_outlined
                                  : Icons.history_toggle_off_rounded),
                          size: 38,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _ledgerFilter == 'FREE'
                              ? 'No free Family-pack games recorded.'
                              : (_ledgerFilter == 'PAID'
                                  ? (freeTxs.isNotEmpty
                                      ? 'No paid credit activity yet.'
                                      : 'No credit transactions recorded yet.')
                                  : 'No credit transactions recorded yet.'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_ledgerFilter == 'PAID' && freeTxs.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${freeTxs.length} free Family-pack ${freeTxs.length == 1 ? 'game is' : 'games are'} in the "Family Pack (0 Cr)" tab.',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        ] else if (_ledgerFilter == 'FREE') ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Games hosted for 1-5 players require 0 credits.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  height: isTwoColumn ? 680 : 380,
                  child: Scrollbar(
                    controller: _ledgerScrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _ledgerScrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: displayedTxs.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (c, idx) {
                        final tx = displayedTxs[idx];
                        final isZero = tx.amount == 0;
                        final isPositive = tx.amount > 0;
                        final Color statusColor = isZero
                            ? const Color(0xFF38BDF8)
                            : (isPositive ? AppTheme.accentSuccess : AppTheme.accentDanger);
                        final IconData statusIcon = isZero
                            ? Icons.family_restroom_rounded
                            : (isPositive ? Icons.add_circle : Icons.remove_circle);

                        return Card(
                          color: AppTheme.darkSurface,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              statusIcon,
                              color: statusColor,
                              size: 22,
                            ),
                            title: Text(
                              tx.description ?? tx.type,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  Formatters.formatShortDate(tx.createdAt),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                                if (isZero) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: const Text(
                                      'Family Pack (1-5 Players) • Free',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF38BDF8),
                                      ),
                                    ),
                                  ),
                                ] else if (isPositive && tx.expiresAt != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppTheme.secondaryColor.withValues(alpha: 0.35),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.timer_outlined,
                                          size: 11,
                                          color: AppTheme.secondaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Expires: ${Formatters.formatDate(tx.expiresAt!)}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.secondaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Text(
                              isZero
                                  ? '0 Credits'
                                  : '${isPositive ? '+' : ''}${tx.amount} Credits',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isZero ? const Color(0xFF94A3B8) : statusColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLedgerFilterChip({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryLight.withValues(alpha: 0.22)
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryLight
                : const Color(0xFF334155),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13.5,
              color: isSelected ? AppTheme.primaryLight : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryLight
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
