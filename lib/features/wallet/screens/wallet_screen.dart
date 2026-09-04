import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_capacity_tier.dart';
import '../../../models/mpt_wallet.dart';
import '../../../providers/app_providers.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isProcessing = false;

  Future<void> _handleWebPurchase() async {
    final success = await ref.read(walletRepositoryProvider).launchWebPurchaseHandoff();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open web checkout. URL: ${AppConfig.purchaseBaseUrl}'),
          backgroundColor: AppTheme.accentWarning,
        ),
      );
    }
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
        title: const Text('Organizer Credit Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(walletProvider);
              ref.invalidate(creditTransactionsProvider);
            },
          ),
        ],
      ),
      body: walletState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
        border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.5), width: 1.5),
        gradient: LinearGradient(
          colors: [AppTheme.secondaryColor.withOpacity(0.12), AppTheme.darkCard],
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
          onPressed: _handleWebPurchase,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Buy Credits on Web Store', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Capacity Tiers & Credit Cost', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        tiersState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Unable to load tiers'),
          data: (tiers) => Column(
            children: tiers.map((tier) {
              return Card(
                color: AppTheme.darkSurface,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(tier.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${tier.minPlayers}–${tier.maxPlayers} Players', style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    '${tier.creditsRequired} Credits',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.secondaryColor),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPolicyNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.accentInfo),
              SizedBox(width: 8),
              Text('Credit Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentInfo)),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '• Credits are charged automatically at game start according to confirmed player count.\n'
            '• Unused credits remain in your wallet for future events.\n'
            '• Credits are non-refundable and expire 1 year after your most recent paid game.',
            style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.4),
          ),
        ],
      ),
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
