import 'dart:async';
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

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  List<MptReward> _remoteCodeMatches = [];
  bool _isSearchingRemote = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });

    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      setState(() {
        _remoteCodeMatches = [];
        _isSearchingRemote = false;
      });
      return;
    }

    setState(() => _isSearchingRemote = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(rewardsRepositoryProvider)
          .searchRewardsByCode(trimmed);
      if (!mounted) return;
      if (_searchQuery.trim() == trimmed) {
        setState(() {
          _remoteCodeMatches = results;
          _isSearchingRemote = false;
        });
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _remoteCodeMatches = [];
      _isSearchingRemote = false;
    });
  }

  List<MptReward> _filterAndMergeRewards(List<MptReward> myRewards) {
    final rawQ = _searchQuery.trim().toLowerCase();
    if (rawQ.isEmpty) return myRewards;
    final normalizedQ = rawQ.replaceFirst(
      RegExp(r'^mpt-(rew-)?', caseSensitive: false),
      'dab-housie-',
    );

    final filtered = myRewards.where((r) {
      final codeLower = r.claimReference.toLowerCase();
      final codeMatch =
          codeLower.contains(rawQ) || codeLower.contains(normalizedQ);
      final inviteMatch = (r.inviteCode ?? '').toLowerCase().contains(rawQ);
      final gameMatch = (r.gameName ?? '').toLowerCase().contains(rawQ);
      final prizeMatch =
          r.prizeType.toLowerCase().contains(rawQ) ||
          Formatters.formatPrizeName(r.prizeType).toLowerCase().contains(rawQ);
      final orgMatch = (r.organizerName ?? '').toLowerCase().contains(rawQ);
      return codeMatch || inviteMatch || gameMatch || prizeMatch || orgMatch;
    }).toList();

    final seenIds = filtered.map((r) => r.id).toSet();
    for (final remote in _remoteCodeMatches) {
      if (!seenIds.contains(remote.id)) {
        filtered.add(remote);
        seenIds.add(remote.id);
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final rewardsState = ref.watch(myRewardsProvider);

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'My Rewards',
        showBackButton: true,
        showRewards: false,
        onRefresh: () {
          ref.invalidate(myRewardsProvider);
          if (_searchQuery.trim().length >= 3) {
            _onSearchChanged(_searchQuery);
          }
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: rewardsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                Center(child: Text('Error loading rewards: $err')),
            data: (rewards) {
              final displayedRewards = _filterAndMergeRewards(rewards);
              final hasSearch = _searchQuery.trim().isNotEmpty;

              if (rewards.isEmpty && !hasSearch) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSearchBar(),
                        const SizedBox(height: 28),
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 64,
                          color: Color(0xFFA0AEC0),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No rewards won yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Join games and claim winning patterns to win prizes, or search above by voucher code!',
                          style: TextStyle(color: Color(0xFFA0AEC0)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        const AdBannerSlot(
                          slotId: 'DAB-REWARDS-EMPTY-01',
                          title: 'Sponsored Partner',
                          subtitle:
                              'Play live with family & friends • Instant prize claims',
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
                  const SizedBox(height: 12),
                  _buildSearchBar(),
                  const SizedBox(height: 14),
                  if (displayedRewards.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 32,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2E334D)),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 42,
                            color: Color(0xFFA0AEC0),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isSearchingRemote
                                ? 'Searching voucher code...'
                                : 'No rewards matching "${_searchQuery.trim()}"',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Check the voucher reference code (e.g. Dab-Housie-...) or clear the search filter.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFA0AEC0),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...displayedRewards.map(
                      (reward) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRewardCard(context, reward),
                      ),
                    ),
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

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      style: const TextStyle(fontSize: 13.5, color: Colors.white),
      decoration: InputDecoration(
        hintText:
            'Search by voucher code (e.g. Dab-Housie-...), game code, or prize...',
        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.secondaryColor,
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSearchingRemote)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Color(0xFFA0AEC0),
                    ),
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                  ),
                ],
              )
            : null,
        filled: true,
        fillColor: AppTheme.darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E334D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E334D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppTheme.secondaryColor,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Color(0xFFBB86FC), size: 17),
              SizedBox(width: 8),
              Text(
                'Prize Claim Notice',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFBB86FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '• Prizes must be claimed directly from your game organizer — not from DabHousie.\n'
            '• Show your QR code or voucher reference to the organizer to receive your prize.\n'
            '• DabHousie is a gameplay platform only and is not responsible for prize distribution, monetary payouts, or physical rewards.',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.amber.shade200,
              height: 1.4,
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

    Widget buildVoucherBlock() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(
              Icons.copy_rounded,
              size: 18,
              color: AppTheme.primaryLight,
            ),
            tooltip: 'Copy voucher code',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: reward.claimReference));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voucher reference copied!')),
              );
            },
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Voucher Reference Code:',
                  style: TextStyle(fontSize: 12, color: Color(0xFFA0AEC0)),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  reward.claimReference,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget buildGameDetailsColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInfoRow(
            Icons.celebration_rounded,
            'Game',
            reward.gameName ?? '—',
          ),
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
        ],
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAvailable
              ? AppTheme.accentSuccess.withValues(alpha: 0.5)
              : const Color(0xFF2E334D),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Prize Name + Claim Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: AppTheme.secondaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          Formatters.formatPrizeName(reward.prizeType),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? AppTheme.accentSuccess.withValues(alpha: 0.2)
                        : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAvailable
                          ? AppTheme.accentSuccess
                          : const Color(0xFF2E334D),
                    ),
                  ),
                  child: Text(
                    isAvailable ? 'CLAIM FROM ORGANIZER' : 'CLAIMED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isAvailable
                          ? AppTheme.accentSuccess
                          : const Color(0xFFA0AEC0),
                    ),
                  ),
                ),
              ],
            ),

            const Divider(color: Color(0xFF2E334D), height: 20),

            // Main Body: 3-Column Layout on wide screens (Game Info | Copy + Voucher Code | QR Code),
            // 2-Column Layout on narrow mobile screens
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth >= 480;

                final qrWidget = Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: reward.claimReference,
                    version: QrVersions.auto,
                    size: isWide ? 116.0 : 100.0,
                  ),
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Column: Game Details
                      Expanded(
                        flex: 5,
                        child: buildGameDetailsColumn(),
                      ),
                      const SizedBox(width: 12),
                      // Center Column: Copy Icon + Voucher Reference Code
                      Expanded(
                        flex: 4,
                        child: Center(child: buildVoucherBlock()),
                      ),
                      const SizedBox(width: 16),
                      // Right Column: QR Code
                      qrWidget,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildGameDetailsColumn(),
                          const SizedBox(height: 10),
                          buildVoucherBlock(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    qrWidget,
                  ],
                );
              },
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
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Color(0xFFA0AEC0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Show this QR or code to ${reward.organizerName ?? 'your game organizer'} to collect your prize.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFCBD5E1),
                      ),
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
        Icon(icon, size: 13.5, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
