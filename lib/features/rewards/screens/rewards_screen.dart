import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
        badgeText: 'My Rewards',
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
                        const Text(
                          'Join games and claim winning patterns to win prizes!',
                          style: TextStyle(color: Color(0xFFA0AEC0)),
                          textAlign: TextAlign.center,
                        ),
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
                  _buildDisclaimerBanner(),
                  const SizedBox(height: 16),
                  ...rewards.map((reward) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
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

  Widget _buildDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Color(0xFFBB86FC), size: 18),
              SizedBox(width: 8),
              Text(
                'Prize Claim Notice',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFBB86FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Prizes must be claimed directly from your game organizer — not from DabHousie.\n'
            '• Show your QR code or voucher reference to the organizer to receive your prize.\n'
            '• DabHousie is a gameplay platform only and is not responsible for prize distribution, monetary payouts, or physical rewards.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.amber.shade200,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard(BuildContext context, MptReward reward) {
    final isAvailable = reward.isAvailable;
    final dateStr = reward.gameDate != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(reward.gameDate!.toLocal())
        : null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAvailable
              ? AppTheme.accentSuccess.withOpacity(0.5)
              : const Color(0xFF2E334D),
          width: 1.2,
        ),
      ),
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
                    isAvailable ? 'CLAIM FROM ORGANIZER' : 'CLAIMED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isAvailable ? AppTheme.accentSuccess : const Color(0xFFA0AEC0),
                    ),
                  ),
                ),
              ],
            ),

            const Divider(color: Color(0xFF2E334D), height: 20),

            if (reward.gameName != null || reward.inviteCode != null) ...[
              _buildInfoRow(Icons.celebration_rounded, 'Game', reward.gameName ?? '—'),
              if (reward.inviteCode != null) ...[
                const SizedBox(height: 6),
                _buildInfoRow(Icons.tag_rounded, 'Game Code', reward.inviteCode!),
              ],
              if (dateStr != null) ...[
                const SizedBox(height: 6),
                _buildInfoRow(Icons.calendar_today_rounded, 'Played on', dateStr),
              ],
              const SizedBox(height: 6),
              _buildInfoRow(
                Icons.person_pin_rounded,
                'Organizer',
                reward.organizerName ?? 'Your Game Host',
              ),
              const Divider(color: Color(0xFF2E334D), height: 20),
            ],

            const Text(
              'Voucher Reference Code:',
              style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: SelectableText(
                    reward.claimReference,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryLight),
                  tooltip: 'Copy voucher code',
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
                  size: 120.0,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFA0AEC0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Show this QR or code to ${reward.organizerName ?? 'your game organizer'} to collect your prize.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
