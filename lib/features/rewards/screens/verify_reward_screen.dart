import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../providers/app_providers.dart';
import '../widgets/organizer_game_claims_dialog.dart';

class VerifyRewardScreen extends ConsumerStatefulWidget {
  const VerifyRewardScreen({super.key});

  @override
  ConsumerState<VerifyRewardScreen> createState() => _VerifyRewardScreenState();
}

class _VerifyRewardScreenState extends ConsumerState<VerifyRewardScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  Map<String, dynamic>? _verificationResult;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _verificationResult = null;
    });

    try {
      final res = await ref.read(rewardsRepositoryProvider).verifyReward(code);
      ref.invalidate(myRewardsProvider);
      setState(() => _verificationResult = res);
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostedGamesAsync = ref.watch(myHostedGamesProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Verify Prize',
        showBackButton: true,
        onRefresh: () {
          ref.invalidate(myHostedGamesProvider);
          ref.invalidate(myRewardsProvider);
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the voucher code shown on the winner’s phone:',
                  style: TextStyle(fontSize: 14, color: Color(0xFFA0AEC0)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Dab-Housie-7K9Q-X4M2',
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isVerifying ? null : _handleVerify,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Verify & Close'),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentDanger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentDanger),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppTheme.accentDanger),
                    ),
                  ),
                ],
                if (_verificationResult != null) ...[
                  const SizedBox(height: 20),
                  _buildResultCard(_verificationResult!),
                ],
                const SizedBox(height: 26),

                // Hosted Games Claims Management Section
                const Row(
                  children: [
                    Icon(
                      Icons.playlist_add_check_circle_outlined,
                      color: AppTheme.secondaryColor,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Close Prize Claims by Hosted Game',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select any of your hosted games below to view winners and mark individual or all prize claims as settled.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),
                hostedGamesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => Text('Error: $err'),
                  data: (games) {
                    final relevant = games
                        .where((g) => !g.isCancelled)
                        .toList();
                    if (relevant.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2E334D)),
                        ),
                        child: const Text(
                          'No hosted games found.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: relevant.map((game) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2E334D)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppTheme.secondaryColor.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  game.inviteCode,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                    color: AppTheme.secondaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  game.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                  size: 15,
                                ),
                                label: const Text('Manage Claims'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.darkSurface,
                                  foregroundColor: AppTheme.secondaryColor,
                                  side: BorderSide(
                                    color: AppTheme.secondaryColor.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 24),
                const AdBannerSlot(
                  slotId: 'DAB-VERIFY-REWARD-01',
                  title: 'Sponsored Partner',
                  subtitle:
                      'Host live multiplayer Tambola & Housie with DabHousie',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> res) {
    final status = res['status'] as String? ?? 'UNKNOWN';
    final isSuccess = status == 'CLAIMED_SUCCESSFULLY';

    return Card(
      color: isSuccess
          ? AppTheme.accentSuccess.withValues(alpha: 0.15)
          : AppTheme.accentWarning.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSuccess ? AppTheme.accentSuccess : AppTheme.accentWarning,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  color: isSuccess
                      ? AppTheme.accentSuccess
                      : AppTheme.accentWarning,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  isSuccess ? 'VERIFIED & CLAIMED!' : status,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSuccess
                        ? AppTheme.accentSuccess
                        : AppTheme.accentWarning,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2E334D), height: 24),
            if (res['player_display_name'] != null)
              Text(
                'Winner: ${res['player_display_name']}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            const SizedBox(height: 6),
            if (res['prize_type'] != null)
              Text(
                'Prize: ${Formatters.formatPrizeName(res['prize_type'])}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.secondaryColor,
                ),
              ),
            const SizedBox(height: 6),
            if (res['message'] != null)
              Text(
                '${res['message']}',
                style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
              ),
          ],
        ),
      ),
    );
  }
}
