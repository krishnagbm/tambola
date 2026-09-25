import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../models/brand_offer.dart';
import '../../../models/mpt_reward.dart';
import '../../../providers/app_providers.dart';

class BrandPartnerOffer {
  final String id;
  final String brandName;
  final String productTitle;
  final String category;
  final String emoji;
  final double retailPrice;
  final double organizerPrice;
  final int discountPercent;
  final String badgeText;
  final String description;

  const BrandPartnerOffer({
    required this.id,
    required this.brandName,
    required this.productTitle,
    required this.category,
    required this.emoji,
    required this.retailPrice,
    required this.organizerPrice,
    required this.discountPercent,
    required this.badgeText,
    required this.description,
  });

  static const List<BrandPartnerOffer> catalog = [
    BrandPartnerOffer(
      id: 'sbux_10',
      brandName: 'Starbucks',
      productTitle: '\$10 Coffee & Bakery E-Gift Voucher',
      category: 'Coffee & Dining',
      emoji: '☕',
      retailPrice: 10.0,
      organizerPrice: 7.50,
      discountPercent: 25,
      badgeText: 'POPULAR FOR LINE WINNERS',
      description:
          'Instant digital café voucher redeemable at participating locations.',
    ),
    BrandPartnerOffer(
      id: 'uber_15',
      brandName: 'Uber Eats',
      productTitle: '\$15 Party Treat & Dining Pass',
      category: 'Coffee & Dining',
      emoji: '🍕',
      retailPrice: 15.0,
      organizerPrice: 11.00,
      discountPercent: 27,
      badgeText: 'INSTANT DELIVERY',
      description:
          ' Let winners order their favorite celebratory meal or dessert.',
    ),
    BrandPartnerOffer(
      id: 'amz_25',
      brandName: 'Amazon',
      productTitle: '\$25 Digital Shopping Gift Card',
      category: 'Shopping Vouchers',
      emoji: '🛍️',
      retailPrice: 25.0,
      organizerPrice: 21.50,
      discountPercent: 14,
      badgeText: 'BEST FOR FULL HOUSE',
      description:
          'Universal gift code delivered directly to the winner’s reward wallet.',
    ),
    BrandPartnerOffer(
      id: 'choco_20',
      brandName: 'Ferrero & Artisan',
      productTitle: 'Festive Gourmet Celebration Hamper',
      category: 'Gourmet Hampers',
      emoji: '🍫',
      retailPrice: 20.0,
      organizerPrice: 13.00,
      discountPercent: 35,
      badgeText: '35% PUBLISHER SPONSORSHIP',
      description:
          'Sponsored brand gift box shipped or redeemed via partner code.',
    ),
    BrandPartnerOffer(
      id: 'anker_35',
      brandName: 'Anker Soundcore',
      productTitle: 'Mini Bluetooth Party Speaker',
      category: 'Tech & Lifestyle',
      emoji: '🔊',
      retailPrice: 35.0,
      organizerPrice: 22.00,
      discountPercent: 37,
      badgeText: 'GRAND PRIZE FAVORITE',
      description:
          'Direct-from-brand promotional hardware offer for event champions.',
    ),
  ];
}

class OrganizerClaimsScreen extends ConsumerStatefulWidget {
  final String? initialGameId;

  const OrganizerClaimsScreen({super.key, this.initialGameId});

  @override
  ConsumerState<OrganizerClaimsScreen> createState() =>
      _OrganizerClaimsScreenState();
}

class _OrganizerClaimsScreenState extends ConsumerState<OrganizerClaimsScreen> {
  // All game drawers are CLOSED by default so the organizer sees all conducted games at first glance
  final Set<String> _expandedGameIds = <String>{};
  final Set<String> _closingRewardIds = <String>{};
  final Set<String> _closingAllGameIds = <String>{};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, UNSETTLED, SETTLED
  bool _showBrandCatalogBanner = true;

  @override
  void initState() {
    super.initState();
    // Keep drawers closed by default unless an explicit single game filter is searched
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(organizerAllGamesClaimsProvider);
    ref.invalidate(myRewardsProvider);
  }

  Future<void> _handleQuickCloseClaim({
    required OrganizerGameClaimsSummary game,
    required MptReward reward,
  }) async {
    setState(() => _closingRewardIds.add(reward.id));
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(
            gameId: game.gameId,
            rewardId: reward.id,
            claimId: reward.claimId,
          );
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(hostGameRewardsProvider(game.gameId));
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settled ${Formatters.formatPrizeName(reward.prizeType)} for ${reward.winnerName ?? "Player"} (${reward.claimReference})!',
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
        setState(() => _closingRewardIds.remove(reward.id));
      }
    }
  }

  Future<void> _handleCloseAllInGame(OrganizerGameClaimsSummary game) async {
    setState(() => _closingAllGameIds.add(game.gameId));
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(gameId: game.gameId, closeAll: true);
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(hostGameRewardsProvider(game.gameId));
      ref.invalidate(myRewardsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All claims for [${game.inviteCode}] ${game.name} marked as Settled!',
          ),
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
        setState(() => _closingAllGameIds.remove(game.gameId));
      }
    }
  }

  Future<void> _openBrandGiftFulfillmentDialog({
    required OrganizerGameClaimsSummary game,
    required MptReward reward,
    BrandPartnerOffer? preselectedOffer,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _BrandGiftFulfillmentDialog(
        game: game,
        reward: reward,
        preselectedOffer: preselectedOffer,
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(organizerAllGamesClaimsProvider);
      ref.invalidate(hostGameRewardsProvider(game.gameId));
      ref.invalidate(myRewardsProvider);
    }
  }

  void _openBrandPublisherVisionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.45),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: AppTheme.secondaryColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DabHousie Brand Publisher Channel',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Direct Brand-to-Organizer Sponsored Prize Marketplace',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2E334D), height: 1),
                const SizedBox(height: 16),
                _buildVisionStep(
                  number: '1',
                  title: 'Brand Publishers List Discounted Products',
                  subtitle:
                      'D2C brands, cafés, and retail sponsors publish digital gift vouchers or physical prize hampers at 15%–40% below retail to gain brand visibility across live Tambola events.',
                  icon: Icons.campaign_rounded,
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(height: 12),
                _buildVisionStep(
                  number: '2',
                  title: 'Organizers Buy & Assign Gifts When Settling Claims',
                  subtitle:
                      'Instead of manually sourcing prizes, Organizers pick discounted Brand Gifts right from their Conducted Games Claims drawer and attach them to winners (Early Five, Lines, Full House).',
                  icon: Icons.card_giftcard_rounded,
                  color: AppTheme.secondaryColor,
                ),
                const SizedBox(height: 12),
                _buildVisionStep(
                  number: '3',
                  title: 'Winners Redeem Directly in My Rewards',
                  subtitle:
                      'Once settled, the player’s My Rewards drawer updates to CLAIMED and reveals the Brand Sponsor Gift & redemption code alongside their Dab-Housie voucher.',
                  icon: Icons.verified_rounded,
                  color: AppTheme.accentSuccess,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: AppTheme.secondaryColor,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Try it now: Expand any conducted game below and click "🎁 Offer Brand Gift" on any winner to preview assigning a Brand Publisher product and settling their claim!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE2E8F0),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text(
                      'Got It, Explore Claims & Gifts',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisionStep({
    required String number,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. $title',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gamesClaimsAsync = ref.watch(organizerAllGamesClaimsProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'Claims & Gifts',
        showBackButton: true,
        onRefresh: _refreshAll,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: RefreshIndicator(
            onRefresh: () async => _refreshAll(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              children: [
                // Top Breadcrumb & Header Row
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/wallet'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Organizer Wallet'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFCBD5E1),
                            side: const BorderSide(color: Color(0xFF334155)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Organizer Prize Claims & Brand Gift Hub',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Review winner details across all conducted games, offer discounted brand gifts, and settle claims',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.push('/verify-reward'),
                          icon: const Icon(Icons.qr_code_scanner, size: 16),
                          label: const Text('Verify Code'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.secondaryColor,
                            side: BorderSide(
                              color: AppTheme.secondaryColor.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Refresh Games & Claims',
                          onPressed: _refreshAll,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Brand Publisher Discounted Gift Marketplace Showcase Section
                _buildBrandPartnerChannelCard(),
                const SizedBox(height: 18),

                // Conducted Games & Claims Content
                gamesClaimsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (err, _) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.accentDanger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.accentDanger,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Failed to load conducted games: $err',
                          style: const TextStyle(color: AppTheme.accentDanger),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _refreshAll,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                  data: (games) => _buildGamesClaimsBody(games),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPartnerChannelCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF172554), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: AppTheme.secondaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Brand Publisher Gift Store',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.secondaryColor.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: const Text(
                              'UP TO 37% ORGANIZER DISCOUNT',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.secondaryColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Brand publishers offer exclusive discounted products & e-vouchers so you can delight your game winners effortlessly.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _openBrandPublisherVisionDialog,
                    icon: const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppTheme.secondaryColor,
                    ),
                    label: const Text(
                      'How Brand Channel Works',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _showBrandCatalogBanner
                        ? 'Hide Partner Offers'
                        : 'Show Partner Offers',
                    onPressed: () => setState(
                      () => _showBrandCatalogBanner = !_showBrandCatalogBanner,
                    ),
                    icon: Icon(
                      _showBrandCatalogBanner
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_showBrandCatalogBanner) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: BrandPartnerOffer.catalog.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final offer = BrandPartnerOffer.catalog[idx];
                  return Container(
                    width: 245,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              offer.emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    offer.brandName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.secondaryColor,
                                    ),
                                  ),
                                  Text(
                                    offer.productTitle,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          offer.description,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '\$${offer.organizerPrice.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.accentSuccess,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '\$${offer.retailPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accentSuccess.withValues(
                                  alpha: 0.16,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'SAVE ${offer.discountPercent}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accentSuccess,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGamesClaimsBody(List<OrganizerGameClaimsSummary> games) {
    final totalGames = games.length;
    final totalUnsettled = games.fold<int>(
      0,
      (sum, g) => sum + g.unsettledCount,
    );
    final totalSettled = games.fold<int>(0, (sum, g) => sum + g.settledCount);
    final totalGifted = games.fold<int>(
      0,
      (sum, g) =>
          sum +
          g.rewards
              .where(
                (r) =>
                    r.fulfilledGiftTitle != null &&
                    r.fulfilledGiftTitle!.trim().isNotEmpty,
              )
              .length,
    );

    // Apply search & status filter
    final q = _searchQuery.trim().toLowerCase();
    final filteredGames = games.where((g) {
      if (_statusFilter == 'UNSETTLED' && g.unsettledCount == 0) return false;
      if (_statusFilter == 'SETTLED' &&
          (g.unsettledCount > 0 || g.totalClaimsCount == 0)) {
        return false;
      }
      if (q.isEmpty) return true;
      final matchesGame =
          g.name.toLowerCase().contains(q) ||
          g.inviteCode.toLowerCase().contains(q) ||
          (g.organizationName?.toLowerCase().contains(q) ?? false);
      final matchesWinner = g.rewards.any(
        (r) =>
            (r.winnerName?.toLowerCase().contains(q) ?? false) ||
            r.claimReference.toLowerCase().contains(q) ||
            r.prizeType.toLowerCase().contains(q) ||
            (r.fulfilledGiftTitle?.toLowerCase().contains(q) ?? false) ||
            (r.fulfilledBrandName?.toLowerCase().contains(q) ?? false),
      );
      return matchesGame || matchesWinner;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary KPI Row
        Row(
          children: [
            Expanded(
              child: _buildKpiStatCard(
                label: 'Conducted Games',
                value: '$totalGames',
                icon: Icons.videogame_asset_rounded,
                accent: const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiStatCard(
                label: 'Unsettled Claims',
                value: '$totalUnsettled',
                icon: Icons.pending_actions_rounded,
                accent: totalUnsettled > 0
                    ? AppTheme.secondaryColor
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiStatCard(
                label: 'Settled Claims',
                value: '$totalSettled',
                icon: Icons.task_alt_rounded,
                accent: AppTheme.accentSuccess,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiStatCard(
                label: 'Brand Gifts Sent',
                value: '$totalGifted',
                icon: Icons.redeem_rounded,
                accent: const Color(0xFFA855F7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Search & Filter Controls
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2E334D)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: InputDecoration(
                    hintText:
                        'Search game code (4E196B), winner (Merry Whiz), or voucher...',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: AppTheme.darkSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('ALL', 'All Games ($totalGames)'),
                  _buildFilterChip(
                    'UNSETTLED',
                    'Unsettled (${games.where((g) => g.unsettledCount > 0).length})',
                  ),
                  _buildFilterChip(
                    'SETTLED',
                    'All Settled (${games.where((g) => g.unsettledCount == 0 && g.totalClaimsCount > 0).length})',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (filteredGames.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 48,
                  color: Color(0xFF64748B),
                ),
                SizedBox(height: 12),
                Text(
                  'No Matching Conducted Games Found',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Host a game or adjust your search filter to manage winner claims and brand gifts.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          )
        else
          ...filteredGames.map(_buildCollapsibleGameDrawer),
      ],
    );
  }

  Widget _buildKpiStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final selected = _statusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = key),
      selectedColor: AppTheme.secondaryColor.withValues(alpha: 0.22),
      backgroundColor: AppTheme.darkSurface,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? AppTheme.secondaryColor : const Color(0xFFCBD5E1),
      ),
      side: BorderSide(
        color: selected
            ? AppTheme.secondaryColor.withValues(alpha: 0.6)
            : const Color(0xFF334155),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildCollapsibleGameDrawer(OrganizerGameClaimsSummary game) {
    final isExpanded = _expandedGameIds.contains(game.gameId);
    final hasUnsettled = game.unsettledCount > 0;
    final isClosingAll = _closingAllGameIds.contains(game.gameId);
    final dateStr = game.gameDate != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(game.gameDate!.toLocal())
        : 'Date N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUnsettled
              ? AppTheme.secondaryColor.withValues(alpha: 0.5)
              : const Color(0xFF2E334D),
          width: hasUnsettled ? 1.3 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Clickable Drawer Header (Default Closed)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedGameIds.remove(game.gameId);
                } else {
                  _expandedGameIds.add(game.gameId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Game Invite Code Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      game.inviteCode,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: AppTheme.secondaryColor,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Game Name & Metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                game.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (game.organizationName != null &&
                                game.organizationName!.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF334155),
                                  ),
                                ),
                                child: Text(
                                  '🏢 ${game.organizationName}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFFCBD5E1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$dateStr • ${game.playerCount} Players • ${game.totalClaimsCount} Prize Claims',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Unsettled Claims Count Badge on Drawer Heading
                  if (hasUnsettled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.notifications_active_rounded,
                            size: 13,
                            color: AppTheme.secondaryColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${game.unsettledCount} Unsettled',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (game.totalClaimsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.accentSuccess.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'All ${game.settledCount} Settled ✓',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentSuccess,
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '0 Claims',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),

          // Expanded Drawer Content
          if (isExpanded) ...[
            const Divider(color: Color(0xFF2E334D), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: game.rewards.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No approved prize claims recorded for this game yet.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Action bar inside drawer
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Winners Roster & Claim Settlement (${game.unsettledCount} Unsettled • ${game.settledCount} Settled)',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                            if (hasUnsettled)
                              ElevatedButton.icon(
                                onPressed: isClosingAll
                                    ? null
                                    : () => _handleCloseAllInGame(game),
                                icon: isClosingAll
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
                                label: const Text('Close All Unsettled Claims'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondaryColor,
                                  foregroundColor: Colors.black,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Winner Claim Rows with Full Player Details
                        ...game.rewards.map(
                          (reward) => _buildWinnerClaimRow(game, reward),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWinnerClaimRow(
    OrganizerGameClaimsSummary game,
    MptReward reward,
  ) {
    final isAvailable = reward.isAvailable;
    final isClosing = _closingRewardIds.contains(reward.id);
    final winnerName =
        (reward.winnerName != null && reward.winnerName!.trim().isNotEmpty)
        ? reward.winnerName!
        : 'Player';
    final claimedStr = reward.claimedAt != null
        ? DateFormat('dd MMM, hh:mm a').format(reward.claimedAt!.toLocal())
        : null;
    final hasGift =
        reward.fulfilledGiftTitle != null &&
        reward.fulfilledGiftTitle!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAvailable
              ? AppTheme.accentSuccess.withValues(alpha: 0.45)
              : const Color(0xFF2E334D),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          // Left: Avatar + Player Details + Prize + Voucher
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  Formatters.getAvatarEmoji(
                    reward.winnerAvatar ?? 'avatar_lion',
                  ),
                  style: const TextStyle(fontSize: 21),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Winner Name + Prize Won + Ticket #
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          winnerName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '🏆 ${Formatters.formatPrizeName(reward.prizeType)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                        if (reward.prizeValue != null &&
                            reward.prizeValue! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentSuccess.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.accentSuccess.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            child: Text(
                              '\$${reward.prizeValue!.toStringAsFixed(reward.prizeValue! % 1 == 0 ? 0 : 2)} Value',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentSuccess,
                              ),
                            ),
                          ),
                        if (reward.ticketNumber != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF334155),
                              ),
                            ),
                            child: Text(
                              'Ticket #${reward.ticketNumber}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            reward.winnerEmail != null &&
                                    reward.winnerEmail!.isNotEmpty
                                ? '✉️ ${reward.winnerEmail}'
                                : (reward.isGuest
                                      ? 'Guest Player'
                                      : 'Registered Player'),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Voucher Code + Claimed Timestamp
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: reward.claimReference),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Copied voucher ${reward.claimReference}',
                                ),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.confirmation_number_outlined,
                                size: 13,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                reward.claimReference,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.copy_rounded,
                                size: 12,
                                color: Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                        if (!isAvailable && claimedStr != null)
                          Text(
                            '• Settled $claimedStr',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentSuccess,
                            ),
                          ),
                      ],
                    ),

                    // Brand Gift Fulfillment Badge if attached
                    if (hasGift) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFA855F7,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFA855F7,
                            ).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              '🎁 Brand Gift: ${reward.fulfilledBrandName != null ? "${reward.fulfilledBrandName} • " : ""}${reward.fulfilledGiftTitle}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE9D5FF),
                              ),
                            ),
                            if (reward.fulfilledGiftCode != null &&
                                reward.fulfilledGiftCode!.trim().isNotEmpty)
                              Text(
                                '(Code: ${reward.fulfilledGiftCode})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Color(0xFFD8B4FE),
                                ),
                              ),
                            if (reward.fulfilledProductUrl != null &&
                                reward.fulfilledProductUrl!.trim().isNotEmpty)
                              InkWell(
                                onTap: () async {
                                  final uri = Uri.tryParse(
                                    reward.fulfilledProductUrl!.trim(),
                                  );
                                  if (uri != null) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                child: const Text(
                                  '🔗 View Product ↗',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF38BDF8),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Right: Action Buttons (Offer Brand Gift / Close Claim / Settled Badge)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    _openBrandGiftFulfillmentDialog(game: game, reward: reward),
                icon: const Icon(Icons.card_giftcard_rounded, size: 15),
                label: Text(
                  hasGift
                      ? 'Update Gift'
                      : (isAvailable
                            ? 'Offer Brand Gift'
                            : 'Attach Brand Gift'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondaryColor,
                  side: BorderSide(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.55),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isAvailable)
                ElevatedButton.icon(
                  onPressed: isClosing
                      ? null
                      : () => _handleQuickCloseClaim(
                          game: game,
                          reward: reward,
                        ),
                  icon: isClosing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 15),
                  label: const Text('Close Claim'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentSuccess,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
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
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSuccess.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.accentSuccess.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text(
                    '✓ CLAIMED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentSuccess,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandGiftFulfillmentDialog extends ConsumerStatefulWidget {
  final OrganizerGameClaimsSummary game;
  final MptReward reward;
  final BrandPartnerOffer? preselectedOffer;

  const _BrandGiftFulfillmentDialog({
    required this.game,
    required this.reward,
    this.preselectedOffer,
  });

  @override
  ConsumerState<_BrandGiftFulfillmentDialog> createState() =>
      _BrandGiftFulfillmentDialogState();
}

class _BrandGiftFulfillmentDialogState
    extends ConsumerState<_BrandGiftFulfillmentDialog> {
  String? _selectedOfferId;
  late final TextEditingController _brandController;
  late final TextEditingController _giftTitleController;
  late final TextEditingController _giftCodeController;
  late final TextEditingController _productUrlController;
  late final TextEditingController _prizeValueController;
  late final TextEditingController _winnerEmailController;
  late final TextEditingController _noteController;
  bool _sendEmailToWinner = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final fallback = widget.preselectedOffer ?? BrandPartnerOffer.catalog.first;
    _selectedOfferId = widget.reward.brandOfferId ?? fallback.id;
    _brandController = TextEditingController(
      text: widget.reward.fulfilledBrandName ?? fallback.brandName,
    );
    _giftTitleController = TextEditingController(
      text: widget.reward.fulfilledGiftTitle ?? fallback.productTitle,
    );
    _giftCodeController = TextEditingController(
      text:
          widget.reward.fulfilledGiftCode ??
          'GIFT-${widget.reward.claimReference.split('-').last}',
    );
    _productUrlController = TextEditingController(
      text: widget.reward.fulfilledProductUrl ?? 'https://www.starbucks.com/gift',
    );
    _prizeValueController = TextEditingController(
      text: (widget.reward.prizeValue != null && widget.reward.prizeValue! > 0)
          ? widget.reward.prizeValue!.toStringAsFixed(0)
          : fallback.retailPrice.toStringAsFixed(0),
    );
    _winnerEmailController = TextEditingController(
      text: widget.reward.winnerEmail ?? '',
    );
    _noteController = TextEditingController(
      text:
          widget.reward.fulfillmentNote ??
          'Congratulations on winning ${Formatters.formatPrizeName(widget.reward.prizeType)}!',
    );
  }

  @override
  void dispose() {
    _brandController.dispose();
    _giftTitleController.dispose();
    _giftCodeController.dispose();
    _productUrlController.dispose();
    _prizeValueController.dispose();
    _winnerEmailController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _selectLiveOffer(BrandOffer offer) {
    setState(() {
      _selectedOfferId = offer.id;
      _brandController.text = offer.brandName;
      _giftTitleController.text = offer.productTitle;
      _productUrlController.text = offer.productUrl;
      _prizeValueController.text = offer.retailPrice.toStringAsFixed(0);
      if (offer.promoCode != null && offer.promoCode!.trim().isNotEmpty) {
        _giftCodeController.text = offer.promoCode!.trim();
      }
    });
  }

  Future<void> _submitGiftAndClose() async {
    final giftTitle = _giftTitleController.text.trim();
    final brandName = _brandController.text.trim();
    final productUrl = _productUrlController.text.trim();
    final prizeVal = double.tryParse(_prizeValueController.text.trim());
    final winnerEmail = _winnerEmailController.text.trim();

    if (giftTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or enter a gift product title.'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(rewardsRepositoryProvider)
          .closeGameClaim(
            gameId: widget.game.gameId,
            rewardId: widget.reward.id,
            claimId: widget.reward.claimId,
            giftTitle: giftTitle,
            brandName: brandName.isEmpty ? null : brandName,
            giftCode: _giftCodeController.text.trim().isEmpty
                ? null
                : _giftCodeController.text.trim(),
            fulfillmentNote: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            brandOfferId: _selectedOfferId,
            productUrl: productUrl.isEmpty ? null : productUrl,
            prizeValue: prizeVal,
          );

      // Optionally send Winner Gift Email if email is provided
      if (_sendEmailToWinner &&
          winnerEmail.isNotEmpty &&
          winnerEmail.contains('@')) {
        await ref.read(rewardsRepositoryProvider).sendWinnerGiftEmail(
          toEmail: winnerEmail,
          reward: MptReward(
            id: widget.reward.id,
            gameId: widget.game.gameId,
            userId: widget.reward.userId,
            prizeType: Formatters.formatPrizeName(widget.reward.prizeType),
            claimId: widget.reward.claimId,
            claimReference: widget.reward.claimReference,
            status: 'CLAIMED',
            createdAt: widget.reward.createdAt,
            gameName: widget.game.name,
            inviteCode: widget.game.inviteCode,
            organizerName: widget.game.organizationName,
            winnerName: widget.reward.winnerName ?? 'Winner',
            prizeValue: prizeVal,
            fulfilledBrandName: brandName.isEmpty ? null : brandName,
            fulfilledGiftTitle: giftTitle,
            fulfilledGiftCode: _giftCodeController.text.trim().isEmpty
                ? null
                : _giftCodeController.text.trim(),
            fulfilledProductUrl: productUrl.isEmpty ? null : productUrl,
            fulfillmentNote: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎁 Sent "$giftTitle" to ${widget.reward.winnerName ?? "Player"} and settled claim!',
          ),
          backgroundColor: AppTheme.accentSuccess,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign gift: $e'),
          backgroundColor: AppTheme.accentDanger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final winnerName = widget.reward.winnerName ?? 'Player';
    final prizeName = Formatters.formatPrizeName(widget.reward.prizeType);
    final liveOffersAsync = ref.watch(activeBrandOffersProvider);

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.45),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modal Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.redeem_rounded,
                      color: AppTheme.secondaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Offer Discounted Brand Gift & Settle Claim',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Winner: $winnerName (Ticket #${widget.reward.ticketNumber ?? 1}) • $prizeName • ${widget.reward.claimReference}',
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2E334D), height: 1),
              const SizedBox(height: 12),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '1. Choose a Discounted Brand Publisher Product (or Customize Below)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 118,
                        child: liveOffersAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (offers) {
                            return ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: offers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (ctx, idx) {
                                final offer = offers[idx];
                                final isSelected = _selectedOfferId == offer.id;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _selectLiveOffer(offer),
                                  child: Container(
                                    width: 220,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.secondaryColor.withValues(
                                              alpha: 0.14,
                                            )
                                          : AppTheme.darkSurface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppTheme.secondaryColor
                                            : const Color(0xFF334155),
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              offer.categoryEmoji,
                                              style: const TextStyle(
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                offer.brandName,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      AppTheme.secondaryColor,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.accentSuccess
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '-${offer.discountPercent}%',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.accentSuccess,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          offer.productTitle,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              'Host: \$${offer.organizerPrice.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.accentSuccess,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '\$${offer.retailPrice.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF64748B),
                                                decoration:
                                                    TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      const Text(
                        '2. Gift, Product Link & Prize Value (Shown in My Rewards & Public Hall of Fame)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _brandController,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Brand Publisher / Sponsor Name',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _giftCodeController,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Gift Voucher / Promo Code',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _prizeValueController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.accentSuccess,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Value (\$)',
                                prefixText: '\$',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _giftTitleController,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Product / Gift Title Offered to Winner',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _productUrlController,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF38BDF8),
                        ),
                        decoration: const InputDecoration(
                          labelText:
                              'Brand Product URL (Clickable on Hall of Fame & Winner Rewards)',
                          prefixIcon: Icon(Icons.link, size: 16),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteController,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              'Personal Message / Redemption Instructions',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Checkbox(
                            value: _sendEmailToWinner,
                            activeColor: AppTheme.secondaryColor,
                            checkColor: Colors.black,
                            onChanged: (val) => setState(
                              () => _sendEmailToWinner = val ?? false,
                            ),
                          ),
                          const Text(
                            'Email Prize Voucher to Winner:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _winnerEmailController,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'winner@email.com (optional)',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitGiftAndClose,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.card_giftcard_rounded, size: 17),
                    label: const Text('Send Brand Gift & Settle Claim'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
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
