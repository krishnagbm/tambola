import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_wallet.dart';
import '../../../providers/app_providers.dart';
import '../../home/widgets/corporate_inquiry_dialog.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isProcessing = false;

  Future<void> _handleDirectPurchase(String plan) async {
    AuthGuard.requireHostAuth(context, ref, () async {
      setState(() => _isProcessing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('Connecting to Stripe Checkout...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );

      try {
        final success = await ref.read(walletRepositoryProvider).startDirectStripeCheckout(plan: plan);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open Stripe checkout. Please try again or open ${AppConfig.purchaseBaseUrl}'),
              backgroundColor: AppTheme.accentWarning,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Checkout Error: $e'), backgroundColor: AppTheme.accentDanger),
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    });
  }

  void _showPurchasePacksDialog() {
    AuthGuard.requireHostAuth(context, ref, () {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Credit Pack',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose a pack to open secure Stripe Hosted Checkout:',
                  style: TextStyle(fontSize: 13, color: Color(0xFFA0AEC0)),
                ),
                const SizedBox(height: 16),
                _buildPackTile(
                  title: 'Starter Pack',
                  credits: '+50 Credits',
                  price: '\$5',
                  plan: 'starter',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _handleDirectPurchase('starter');
                  },
                ),
                const SizedBox(height: 8),
                _buildPackTile(
                  title: 'Family & Party Pack',
                  credits: '+150 Credits',
                  price: '\$12',
                  plan: 'family',
                  isFeatured: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _handleDirectPurchase('family');
                  },
                ),
                const SizedBox(height: 8),
                _buildPackTile(
                  title: 'Pro Host Pack',
                  credits: '+300 Credits',
                  price: '\$20',
                  plan: 'pro',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _handleDirectPurchase('pro');
                  },
                ),
                const SizedBox(height: 8),
                _buildPackTile(
                  title: 'Mega Gala Pack',
                  credits: '+750 Credits',
                  price: '\$45',
                  plan: 'mega',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _handleDirectPurchase('mega');
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ref.read(walletRepositoryProvider).launchWebPurchaseHandoff();
                  },
                  child: const Text('View Full Web Store →', style: TextStyle(color: AppTheme.secondaryColor)),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildPackTile({
    required String title,
    required String credits,
    required String price,
    required String plan,
    required VoidCallback onTap,
    bool isFeatured = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isFeatured ? AppTheme.secondaryColor.withValues(alpha: 0.12) : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFeatured ? AppTheme.secondaryColor : Colors.white12,
            width: isFeatured ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                      if (isFeatured) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Popular', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(credits, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentSuccess)),
                ],
              ),
            ),
            Text(price, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
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
      appBar: AppBar(
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              AppAssets.horizontalLogo,
              height: 38,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.6)),
              ),
              child: const Text(
                'Wallet',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Balance',
            onPressed: () {
              ref.invalidate(walletProvider);
              ref.invalidate(creditTransactionsProvider);
            },
          ),
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined, size: 18, color: AppTheme.secondaryColor),
            label: const Text('Home', style: TextStyle(color: AppTheme.secondaryColor, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: walletState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Wallet Balance Card
                    _buildBalanceCard(wallet),
                    const SizedBox(height: 20),

                    // Web Purchase & Mock Buttons
                    _buildPurchaseActions(),
                    const SizedBox(height: 24),

                    // Pricing & Capacity Tiers
                    _buildPricingTiersSection(tiersState),
                    const SizedBox(height: 24),

                    // Credit Validity & Policy Notice
                    _buildPolicyNotice(),
                    const SizedBox(height: 24),

                    // Transaction Ledger
                    _buildTransactionsList(),
                  ],
                ),
              ),
            ),
          );
        },
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
          const SizedBox(height: 8),
          Text(
            wallet.creditsExpireAt != null
                ? 'Valid until: ${Formatters.formatDate(wallet.creditsExpireAt!)}'
                : 'Credits valid for 1 year from your most recent paid game.',
            style: const TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _showPurchasePacksDialog,
          icon: const Icon(Icons.shopping_cart_checkout),
          label: const Text('Buy Credits (Instant Delivery)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
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

  Widget _buildTransactionsList() {
    final txsAsync = ref.watch(creditTransactionsProvider);

    return txsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const SizedBox(),
      data: (txs) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Credit History & Ledger', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (txs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('No credit transactions recorded yet.')),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: txs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (c, idx) {
                  final tx = txs[idx];
                  final isPositive = tx.amount > 0;
                  return Card(
                    color: AppTheme.darkSurface,
                    child: ListTile(
                      leading: Icon(
                        isPositive ? Icons.add_circle : Icons.remove_circle,
                        color: isPositive ? AppTheme.accentSuccess : AppTheme.accentDanger,
                      ),
                      title: Text(tx.description ?? tx.type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(Formatters.formatShortDate(tx.createdAt), style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        '${isPositive ? '+' : ''}${tx.amount} Credits',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPositive ? AppTheme.accentSuccess : AppTheme.accentDanger,
                        ),
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
}
