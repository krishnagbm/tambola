import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/mpt_reward.dart';
import '../../../providers/app_providers.dart';

class OrganizerGameClaimsDialog extends ConsumerStatefulWidget {
  final String gameId;
  final String gameName;
  final String inviteCode;

  const OrganizerGameClaimsDialog({
    super.key,
    required this.gameId,
    required this.gameName,
    required this.inviteCode,
  });

  static Future<void> show(
    BuildContext context, {
    required String gameId,
    required String gameName,
    required String inviteCode,
  }) {
    return showDialog(
      context: context,
      builder: (_) => OrganizerGameClaimsDialog(
        gameId: gameId,
        gameName: gameName,
        inviteCode: inviteCode,
      ),
    );
  }

  @override
  ConsumerState<OrganizerGameClaimsDialog> createState() =>
      _OrganizerGameClaimsDialogState();
}

class _OrganizerGameClaimsDialogState
    extends ConsumerState<OrganizerGameClaimsDialog> {
  bool _isClosingAll = false;
  final Set<String> _closingIds = <String>{};

  Future<void> _handleCloseSingle(MptReward reward) async {
    setState(() => _closingIds.add(reward.id));
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(
            gameId: widget.gameId,
            rewardId: reward.id,
            claimId: reward.claimId,
          );
      ref.invalidate(hostGameRewardsProvider(widget.gameId));
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked ${Formatters.formatPrizeName(reward.prizeType)} (${reward.winnerName ?? "Player"}) as Claimed!',
          ),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to close claim: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _closingIds.remove(reward.id));
      }
    }
  }

  Future<void> _handleCloseAll() async {
    setState(() => _isClosingAll = true);
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(gameId: widget.gameId, closeAll: true);
      ref.invalidate(hostGameRewardsProvider(widget.gameId));
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All prize claims for this game marked as Claimed!'),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to close claims: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isClosingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rewardsAsync = ref.watch(hostGameRewardsProvider(widget.gameId));

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2E334D)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      widget.inviteCode,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: AppTheme.secondaryColor,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.gameName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Organizer Prize Claims Management',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2E334D), height: 1),
              const SizedBox(height: 12),

              // Body
              Flexible(
                child: rewardsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'Error loading claims: $err',
                        style: const TextStyle(color: AppTheme.accentDanger),
                      ),
                    ),
                  ),
                  data: (rewards) {
                    if (rewards.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 36,
                          horizontal: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              size: 46,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No Prize Claims Recorded',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Approved prize winners for this game will appear here so you can mark their claims as settled.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final unclaimedCount = rewards
                        .where((r) => r.isAvailable)
                        .length;
                    final claimedCount = rewards
                        .where((r) => r.isClaimed)
                        .length;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Summary & Close All Row
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF2E334D)),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: unclaimedCount > 0
                                          ? AppTheme.accentSuccess.withValues(
                                              alpha: 0.2,
                                            )
                                          : const Color(0xFF334155),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$unclaimedCount Unclaimed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: unclaimedCount > 0
                                            ? AppTheme.accentSuccess
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '• $claimedCount Claimed',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ],
                              ),
                              if (unclaimedCount > 0)
                                ElevatedButton.icon(
                                  onPressed: _isClosingAll
                                      ? null
                                      : _handleCloseAll,
                                  icon: _isClosingAll
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.done_all_rounded,
                                          size: 16,
                                        ),
                                  label: const Text('Close All Claims'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondaryColor,
                                    foregroundColor: Colors.black,
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
                        ),
                        const SizedBox(height: 12),

                        // List of Claims
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: rewards.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, idx) {
                              final r = rewards[idx];
                              final isAvailable = r.isAvailable;
                              final isClosing = _closingIds.contains(r.id);
                              final claimedStr = r.claimedAt != null
                                  ? DateFormat(
                                      'dd MMM, hh:mm a',
                                    ).format(r.claimedAt!.toLocal())
                                  : null;

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isAvailable
                                        ? AppTheme.accentSuccess.withValues(
                                            alpha: 0.45,
                                          )
                                        : const Color(0xFF2E334D),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondaryColor
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        Formatters.getAvatarEmoji(
                                          r.winnerAvatar ?? 'avatar_lion',
                                        ),
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  Formatters.formatPrizeName(
                                                    r.prizeType,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '• ${r.winnerName ?? "Player"}',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      AppTheme.secondaryColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  Clipboard.setData(
                                                    ClipboardData(
                                                      text: r.claimReference,
                                                    ),
                                                  );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Voucher code copied!',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Text(
                                                  r.claimReference,
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontFamily: 'monospace',
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ),
                                              if (!isAvailable &&
                                                  claimedStr != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '• Claimed $claimedStr',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isAvailable)
                                      ElevatedButton.icon(
                                        onPressed: isClosing
                                            ? null
                                            : () => _handleCloseSingle(r),
                                        icon: isClosing
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.check_circle_outline,
                                                size: 15,
                                              ),
                                        label: const Text('Close Claim'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.accentSuccess,
                                          foregroundColor: Colors.white,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: const Text(
                                          '✓ CLAIMED',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
