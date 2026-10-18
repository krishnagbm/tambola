import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../models/mpt_reward.dart';
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
  String _claimsFilter = 'claims'; // 'claims', 'unsettled', 'all'

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
      ref.invalidate(organizerAllGamesClaimsProvider);
      setState(() => _verificationResult = res);
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final claimsSummariesAsync = ref.watch(organizerAllGamesClaimsProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Verify Prize',
        showBackButton: true,
        onRefresh: () {
          ref.invalidate(organizerAllGamesClaimsProvider);
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
                Row(
                  children: [
                    const Icon(
                      Icons.playlist_add_check_circle_outlined,
                      color: AppTheme.secondaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Close Prize Claims by Hosted Game',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF94A3B8)),
                      tooltip: 'Refresh Games & Claims',
                      onPressed: () {
                        ref.invalidate(organizerAllGamesClaimsProvider);
                        ref.invalidate(myHostedGamesProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Select a game below to view winner identities and mark prize claims as settled.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),

                claimsSummariesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.accentDanger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accentDanger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Failed to load hosted game claims: $err',
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.accentDanger),
                    ),
                  ),
                  data: (allSummaries) {
                    final gamesWithClaims = allSummaries.where((g) => g.totalClaimsCount > 0).toList();
                    final gamesUnsettled = allSummaries.where((g) => g.unsettledCount > 0).toList();

                    // Sort: Unsettled claims first, then games with claims, then by date
                    final sortedAll = List<OrganizerGameClaimsSummary>.from(allSummaries)
                      ..sort((a, b) {
                        if (a.unsettledCount > 0 && b.unsettledCount == 0) return -1;
                        if (b.unsettledCount > 0 && a.unsettledCount == 0) return 1;
                        if (a.totalClaimsCount > 0 && b.totalClaimsCount == 0) return -1;
                        if (b.totalClaimsCount > 0 && a.totalClaimsCount == 0) return 1;
                        final dateA = a.gameDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final dateB = b.gameDate ?? DateTime.fromMillisecondsSinceEpoch(0);
                        return dateB.compareTo(dateA);
                      });

                    List<OrganizerGameClaimsSummary> displayedGames;
                    if (_claimsFilter == 'unsettled') {
                      displayedGames = sortedAll.where((g) => g.unsettledCount > 0).toList();
                    } else if (_claimsFilter == 'all') {
                      displayedGames = sortedAll;
                    } else {
                      // Default: games with claims
                      displayedGames = sortedAll.where((g) => g.totalClaimsCount > 0).toList();
                      // If no games have claims yet, show all
                      if (displayedGames.isEmpty && sortedAll.isNotEmpty) {
                        displayedGames = sortedAll;
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Filter Pills
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: Text(
                                  'With Claims (${gamesWithClaims.length})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _claimsFilter == 'claims' ? FontWeight.bold : FontWeight.normal,
                                    color: _claimsFilter == 'claims' ? Colors.black : Colors.white,
                                  ),
                                ),
                                selected: _claimsFilter == 'claims',
                                selectedColor: AppTheme.secondaryColor,
                                backgroundColor: AppTheme.darkSurface,
                                onSelected: (_) => setState(() => _claimsFilter = 'claims'),
                              ),
                              const SizedBox(width: 8),
                              if (gamesUnsettled.isNotEmpty) ...[
                                ChoiceChip(
                                  label: Text(
                                    'Needs Settlement (${gamesUnsettled.length})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _claimsFilter == 'unsettled' ? FontWeight.bold : FontWeight.normal,
                                      color: _claimsFilter == 'unsettled' ? Colors.black : AppTheme.accentWarning,
                                    ),
                                  ),
                                  selected: _claimsFilter == 'unsettled',
                                  selectedColor: AppTheme.accentWarning,
                                  backgroundColor: AppTheme.darkSurface,
                                  onSelected: (_) => setState(() => _claimsFilter = 'unsettled'),
                                ),
                                const SizedBox(width: 8),
                              ],
                              ChoiceChip(
                                label: Text(
                                  'All Hosted (${sortedAll.length})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _claimsFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                                    color: _claimsFilter == 'all' ? Colors.black : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                selected: _claimsFilter == 'all',
                                selectedColor: Colors.white,
                                backgroundColor: AppTheme.darkSurface,
                                onSelected: (_) => setState(() => _claimsFilter = 'all'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (displayedGames.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2E334D)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.emoji_events_outlined, size: 36, color: Color(0xFF64748B)),
                                const SizedBox(height: 8),
                                Text(
                                  _claimsFilter == 'unsettled'
                                      ? 'All prize claims have been settled! 🎉'
                                      : 'No prize claims recorded in these games yet.',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                  textAlign: TextAlign.center,
                                ),
                                if (_claimsFilter != 'all') ...[
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: () => setState(() => _claimsFilter = 'all'),
                                    child: const Text('View All Hosted Games', style: TextStyle(color: AppTheme.secondaryColor)),
                                  ),
                                ],
                              ],
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: displayedGames.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              final game = displayedGames[idx];
                              final statusUpper = game.status.toUpperCase();
                              final isScheduled = statusUpper == 'WAITING' || statusUpper == 'SCHEDULED';
                              final isLive = statusUpper == 'IN_PROGRESS';
                              final isCompleted = statusUpper == 'COMPLETED';
                              final isCancelled = statusUpper == 'CANCELLED';

                              Color statusColor = const Color(0xFF94A3B8);
                              String statusText = 'Completed';
                              if (isScheduled) {
                                statusColor = const Color(0xFF818CF8); // Indigo/Purple
                                statusText = 'Scheduled';
                              } else if (isLive) {
                                statusColor = const Color(0xFF38BDF8); // Sky blue
                                statusText = 'Live';
                              } else if (isCancelled) {
                                statusColor = AppTheme.accentDanger;
                                statusText = 'Cancelled';
                              } else if (isCompleted) {
                                statusColor = AppTheme.accentSuccess;
                                statusText = 'Completed';
                              }

                              final hasClaims = game.totalClaimsCount > 0;
                              final hasUnsettled = game.unsettledCount > 0;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: hasUnsettled
                                        ? AppTheme.accentWarning.withValues(alpha: 0.5)
                                        : const Color(0xFF2E334D),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Invite Code
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppTheme.secondaryColor.withValues(alpha: 0.4),
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

                                    // Game Title + Status + Claims Badges
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            game.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              // Status Badge (Scheduled / Live / Completed / Cancelled)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  statusText,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),

                                              // Claims Status Badge
                                              if (hasUnsettled)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.accentWarning.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppTheme.accentWarning.withValues(alpha: 0.5)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.star_rounded, size: 11, color: AppTheme.accentWarning),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        '${game.unsettledCount} Unsettled',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.accentWarning,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else if (hasClaims)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.4)),
                                                  ),
                                                  child: Text(
                                                    '✓ All ${game.settledCount} Settled',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppTheme.accentSuccess,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1E293B),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    '0 Claims',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Action Button
                                    if (hasClaims)
                                      ElevatedButton.icon(
                                        onPressed: () => OrganizerGameClaimsDialog.show(
                                          context,
                                          gameId: game.gameId,
                                          gameName: game.name,
                                          inviteCode: game.inviteCode,
                                        ),
                                        icon: Icon(
                                          hasUnsettled ? Icons.emoji_events : Icons.emoji_events_outlined,
                                          size: 15,
                                        ),
                                        label: Text(
                                          hasUnsettled ? 'Manage (${game.unsettledCount})' : 'View (${game.settledCount})',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: hasUnsettled ? AppTheme.secondaryColor : AppTheme.darkSurface,
                                          foregroundColor: hasUnsettled ? Colors.black : AppTheme.secondaryColor,
                                          side: BorderSide(
                                            color: AppTheme.secondaryColor.withValues(alpha: hasUnsettled ? 1.0 : 0.5),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isScheduled ? 'Scheduled' : '0 Claims',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
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
