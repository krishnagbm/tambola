import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _openSettleClaimDialog(MptReward reward) async {
    final defaultVal = (reward.prizeValue != null && reward.prizeValue! > 0)
        ? (reward.prizeValue! % 1 == 0
            ? reward.prizeValue!.toInt().toString()
            : reward.prizeValue!.toString())
        : '10';
    final prizeController = TextEditingController(text: defaultVal);
    final noteController = TextEditingController();
    String selectedMethod = '💵 Direct Cash / Transfer';

    final methods = [
      '💵 Direct Cash / Transfer',
      '📱 Venmo / Zelle / UPI',
      '🎁 DabHousie Event Credits',
      '🛍️ Amazon / Brand Gift Card',
      '🏆 Physical Trophy / Goodie',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgContext) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return Dialog(
              backgroundColor: AppTheme.darkCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E334D)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppTheme.accentSuccess.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.verified_rounded,
                                color: AppTheme.accentSuccess,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Settle Prize Claim',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '${Formatters.formatPrizeName(reward.prizeType)} • ${reward.winnerName ?? "Player"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.secondaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () => Navigator.pop(dlgContext, false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFF2E334D), height: 1),
                        const SizedBox(height: 14),

                        // Winner Verification Badge
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    Formatters.getAvatarEmoji(
                                      reward.winnerAvatar ?? 'avatar_lion',
                                    ),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Winner: ${reward.winnerName ?? "Player"} (${reward.isGuest ? "Guest Player" : (reward.winnerEmail ?? "Registered")})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (reward.ticketNumber != null)
                                    Text(
                                      'Ticket #${reward.ticketNumber}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Text(
                                    'Voucher Code: ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    reward.claimReference,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.secondaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Prize Value ($)
                        const Text(
                          'Prize Value (\$ / Credits)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: prizeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.attach_money_rounded,
                              color: AppTheme.accentSuccess,
                              size: 18,
                            ),
                            hintText: '10.00',
                            hintStyle: const TextStyle(
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: AppTheme.darkSurface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppTheme.accentSuccess,
                              ),
                            ),
                          ),
                          onChanged: (_) => setDlgState(() {}),
                        ),
                        const SizedBox(height: 6),
                        // Quick chips for $5, $10, $15, $20, $25, $50
                        Wrap(
                          spacing: 6,
                          children: ['5', '10', '15', '20', '25', '50'].map((
                            val,
                          ) {
                            final isSel = prizeController.text.trim() == val;
                            return InkWell(
                              onTap: () {
                                setDlgState(() {
                                  prizeController.text = val;
                                });
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? AppTheme.accentSuccess.withValues(
                                          alpha: 0.25,
                                        )
                                      : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSel
                                        ? AppTheme.accentSuccess
                                        : const Color(0xFF334155),
                                  ),
                                ),
                                child: Text(
                                  '\$$val',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSel
                                        ? AppTheme.accentSuccess
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Fulfillment Method
                        const Text(
                          'Settlement Method',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedMethod,
                              dropdownColor: AppTheme.darkCard,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Color(0xFF94A3B8),
                              ),
                              items: methods.map((m) {
                                return DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    m,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDlgState(() => selectedMethod = val);
                                }
                              },
                            ),
                          ),
                        ),
                        if (selectedMethod == '🎁 DabHousie Event Credits')
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.secondaryColor.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: AppTheme.secondaryColor,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'How DabHousie Credits work:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.secondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  reward.isGuest
                                      ? '• Winner is currently a Guest without an account.\n• Provide a voucher/promo code (e.g. sponsored DABFREE10) in the note below. Once the winner signs in to host, they can redeem it for event hosting credits.'
                                      : '• DabHousie Event Credits are hosting credits. Enter a promo code (e.g. DABFREE10) or reference note below for the player to use when hosting games.',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFFCBD5E1),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Settlement Note
                        const Text(
                          'Settlement Note / Voucher Details (Optional)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: noteController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                selectedMethod == '🎁 DabHousie Event Credits'
                                ? 'e.g. Voucher code DABFREE10 or credit promo code for winner'
                                : 'e.g. Sent \$10 via Venmo / Handed cash in person / Gift code #...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: AppTheme.darkSurface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Platform Notice
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: Color(0xFF94A3B8),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'DabHousie verifies winning ticket claims and does not distribute prizes or collect commissions. Prize fulfillment is completely the host\'s responsibility. Transaction references or notes are optional and recorded solely for host records.',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF94A3B8),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dlgContext, false),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Color(0xFF94A3B8)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pop(dlgContext, true),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: const Text('Mark as Settled'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentSuccess,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
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
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final parsedPrizeValue =
        double.tryParse(prizeController.text.trim()) ??
        reward.prizeValue ??
        10.0;
    final note = noteController.text.trim();

    setState(() => _closingIds.add(reward.id));
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(
            gameId: widget.gameId,
            rewardId: reward.id,
            claimId: reward.claimId,
            prizeValue: parsedPrizeValue,
            giftTitle: selectedMethod,
            fulfillmentNote:
                note.isNotEmpty ? note : 'Settled via $selectedMethod',
          );
      ref.invalidate(hostGameRewardsProvider(widget.gameId));
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settled ${Formatters.formatPrizeName(reward.prizeType)} (\$${parsedPrizeValue.toStringAsFixed(parsedPrizeValue % 1 == 0 ? 0 : 2)}) for ${reward.winnerName ?? "Player"}!',
          ),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to settle claim: $e'),
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
      ref.invalidate(organizerAllGamesClaimsProvider);
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
                        const SizedBox(height: 8),

                        // Winner Recognition / Verification Guidance Banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E293B,
                            ).withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: AppTheme.secondaryColor,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Winner Verification: Signed-in players show their email/account. Guest players match the Ticket # and Voucher Code shown on their winning ticket screen.',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF94A3B8),
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

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
                                          Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                Formatters.formatPrizeName(
                                                  r.prizeType,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              if (r.prizeValue != null &&
                                                  r.prizeValue! > 0)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF10B981,
                                                    ).withValues(alpha: 0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          5,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF10B981,
                                                      ).withValues(alpha: 0.45),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '💰 \$${r.prizeValue!.toStringAsFixed(r.prizeValue! % 1 == 0 ? 0 : 2)} Value',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Color(0xFF10B981),
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                '• ${r.winnerName ?? "Player"}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      AppTheme.secondaryColor,
                                                ),
                                              ),
                                              if (r.ticketNumber != null)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF1E293B,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          5,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF334155,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Ticket #${r.ticketNumber}',
                                                    style: const TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFFCBD5E1),
                                                    ),
                                                  ),
                                                ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF1E293B,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: Text(
                                                  r.winnerEmail != null &&
                                                          r
                                                              .winnerEmail!
                                                              .isNotEmpty
                                                      ? r.winnerEmail!
                                                      : (r.isGuest
                                                            ? 'Guest'
                                                            : 'Registered'),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
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
                                                  '• Settled $claimedStr',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (r.fulfilledGiftTitle != null &&
                                              r.fulfilledGiftTitle!
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '🎁 ${r.fulfilledBrandName != null ? "${r.fulfilledBrandName}: " : ""}${r.fulfilledGiftTitle}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFD8B4FE),
                                              ),
                                            ),
                                          ],
                                          if (r.fulfillmentNote != null &&
                                              r.fulfillmentNote!
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '📝 ${r.fulfillmentNote}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isAvailable)
                                      ElevatedButton.icon(
                                        onPressed: isClosing
                                            ? null
                                            : () => _openSettleClaimDialog(r),
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
                                                Icons.verified_outlined,
                                                size: 15,
                                              ),
                                        label: const Text('Settle Prize'),
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
                                        child: Text(
                                          r.prizeValue != null &&
                                                  r.prizeValue! > 0
                                              ? '✓ SETTLED (\$${r.prizeValue!.toStringAsFixed(r.prizeValue! % 1 == 0 ? 0 : 2)})'
                                              : '✓ SETTLED',
                                          style: const TextStyle(
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
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2E334D), height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'Want to offer discounted Brand Publisher gifts to winners?',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/wallet/claims');
                    },
                    icon: const Icon(
                      Icons.redeem_rounded,
                      size: 15,
                      color: AppTheme.secondaryColor,
                    ),
                    label: const Text(
                      'Open Claims & Brand Gift Hub →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
