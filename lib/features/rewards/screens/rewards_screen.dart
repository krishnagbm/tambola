import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../models/mpt_reward.dart';
import '../../../providers/app_providers.dart';

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewardsState = ref.watch(myRewardsProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Rewards',
        showBackButton: true,
        showRewards: false,
        onRefresh: () => ref.invalidate(myRewardsProvider),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: rewardsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading rewards: $err')),
            data: (rewards) {
              if (rewards.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events_outlined, size: 64, color: Color(0xFFA0AEC0)),
                        const SizedBox(height: 16),
                        const Text('No rewards won yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('Join games and claim winning patterns to win prizes!', style: TextStyle(color: Color(0xFFA0AEC0))),
                        const SizedBox(height: 32),
                        const AdBannerSlot(
                          slotId: 'DAB-REWARDS-EMPTY-01',
                          title: 'Sponsored Partner',
                          subtitle: 'Play live with family & friends • Instant prize claims',
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.secondaryColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Rewards Claim Notice: Prizes must be claimed directly from your game organizer by presenting your voucher reference or QR code. DabHousie is a gameplay platform and is not responsible for physical or monetary prize distributions.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade200,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...rewards.map((reward) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRewardCard(context, reward),
                      )),
                  const SizedBox(height: 12),
                  const AdBannerSlot(
                    slotId: 'DAB-REWARDS-BOTTOM-01',
                    title: 'Sponsored Partner',
                    subtitle: 'Exclusive partner offers & event perks',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRewardCard(BuildContext context, MptReward reward) {
    final isAvailable = reward.isAvailable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events, color: AppTheme.secondaryColor, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      Formatters.formatPrizeName(reward.prizeType),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAvailable ? AppTheme.accentSuccess.withOpacity(0.2) : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isAvailable ? AppTheme.accentSuccess : const Color(0xFF2E334D)),
                  ),
                  child: Text(
                    isAvailable ? 'AVAILABLE TO CLAIM' : 'CLAIMED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAvailable ? AppTheme.accentSuccess : const Color(0xFFA0AEC0),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 20),
            const Text('Verification Reference Code:', style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0))),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SelectableText(
                  reward.claimReference,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.secondaryColor),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryLight),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: reward.claimReference));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Voucher reference copied!')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: reward.claimReference,
                  version: QrVersions.auto,
                  size: 110.0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Show this QR or verification code to your Game Admin to receive your prize.',
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
