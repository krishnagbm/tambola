import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ad_banner_slot.dart';
import '../../../core/widgets/dabhousie_app_bar.dart';
import '../../../models/mpt_reward.dart';
import '../../../providers/app_providers.dart';

class _ParticipatedGameGroup {
  final String gameId;
  final String gameName;
  final String inviteCode;
  final DateTime? gameDate;
  final String? organizerName;
  final List<MptReward> rewards;

  _ParticipatedGameGroup({
    required this.gameId,
    required this.gameName,
    required this.inviteCode,
    this.gameDate,
    this.organizerName,
    required this.rewards,
  });

  int get unclaimedCount => rewards.where((r) => r.isAvailable).length;
  int get claimedCount => rewards.where((r) => r.isClaimed).length;
  int get totalRewards => rewards.length;
}

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

  /// Tracks which game drawers the user has manually expanded.
  /// By default, all drawers start closed (empty set).
  final Set<String> _expandedGameIds = <String>{};

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

  List<_ParticipatedGameGroup> _buildGameGroups(
    List<MptReward> displayedRewards,
    List<Map<String, dynamic>> joinedGames,
    bool hasSearch,
  ) {
    final Map<String, _ParticipatedGameGroup> groupsById = {};
    final rawQ = _searchQuery.trim().toLowerCase();

    // 1. Group all displayed rewards by gameId
    for (final r in displayedRewards) {
      final existing = groupsById[r.gameId];
      if (existing == null) {
        groupsById[r.gameId] = _ParticipatedGameGroup(
          gameId: r.gameId,
          gameName: (r.gameName != null && r.gameName!.trim().isNotEmpty)
              ? r.gameName!
              : 'DabHousie Event',
          inviteCode: (r.inviteCode != null && r.inviteCode!.trim().isNotEmpty)
              ? r.inviteCode!
              : r.gameId.substring(0, 6).toUpperCase(),
          gameDate: r.gameDate ?? r.createdAt,
          organizerName: r.organizerName,
          rewards: [r],
        );
      } else {
        existing.rewards.add(r);
      }
    }

    // 2. Also merge games the player participated in from myJoinedGamesProvider
    for (final reg in joinedGames) {
      final gameId = (reg['game_id'] ?? '').toString();
      if (gameId.isEmpty) continue;
      final gameData = reg['game'] as Map<String, dynamic>? ?? {};
      final gameName = (gameData['name'] ?? 'DabHousie Event').toString();
      final inviteCode = (gameData['invite_code'] ?? '').toString();
      final orgMap = gameData['MPT_users'] as Map<String, dynamic>?;
      final orgName = orgMap?['display_name'] as String?;
      final rawDate =
          gameData['completed_at'] ??
          gameData['started_at'] ??
          gameData['created_at'] ??
          reg['joined_at'];
      final gameDate = rawDate != null
          ? DateTime.tryParse(rawDate.toString())
          : null;

      if (groupsById.containsKey(gameId)) {
        final existing = groupsById[gameId]!;
        groupsById[gameId] = _ParticipatedGameGroup(
          gameId: gameId,
          gameName: existing.gameName != 'DabHousie Event'
              ? existing.gameName
              : gameName,
          inviteCode: existing.inviteCode.isNotEmpty
              ? existing.inviteCode
              : (inviteCode.isNotEmpty
                    ? inviteCode
                    : gameId.substring(0, 6).toUpperCase()),
          gameDate: existing.gameDate ?? gameDate,
          organizerName: existing.organizerName ?? orgName,
          rewards: existing.rewards,
        );
      } else {
        // Only include 0-reward participated games if not filtering, OR if the game code/name matches the search query
        if (!hasSearch ||
            inviteCode.toLowerCase().contains(rawQ) ||
            gameName.toLowerCase().contains(rawQ) ||
            (orgName ?? '').toLowerCase().contains(rawQ)) {
          groupsById[gameId] = _ParticipatedGameGroup(
            gameId: gameId,
            gameName: gameName,
            inviteCode: inviteCode.isNotEmpty
                ? inviteCode
                : gameId.substring(0, 6).toUpperCase(),
            gameDate: gameDate,
            organizerName: orgName,
            rewards: [],
          );
        }
      }
    }

    final list = groupsById.values.toList();
    // Sort: games with unclaimed rewards first, then games with claimed rewards, then by date descending
    list.sort((a, b) {
      if (a.unclaimedCount != b.unclaimedCount) {
        if (a.unclaimedCount > 0 && b.unclaimedCount == 0) return -1;
        if (b.unclaimedCount > 0 && a.unclaimedCount == 0) return 1;
      }
      if (a.totalRewards != b.totalRewards) {
        if (a.totalRewards > 0 && b.totalRewards == 0) return -1;
        if (b.totalRewards > 0 && a.totalRewards == 0) return 1;
      }
      final da = a.gameDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.gameDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rewardsState = ref.watch(myRewardsProvider);
    final joinedGamesState = ref.watch(myJoinedGamesProvider);
    final joinedGames = joinedGamesState.value ?? [];

    return Scaffold(
      appBar: DabHousieAppBar(
        badgeText: 'My Rewards',
        showBackButton: true,
        showRewards: false,
        onRefresh: () {
          ref.invalidate(myRewardsProvider);
          ref.invalidate(myJoinedGamesProvider);
          if (_searchQuery.trim().length >= 3) {
            _onSearchChanged(_searchQuery);
          }
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: rewardsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) =>
                Center(child: Text('Error loading rewards: $err')),
            data: (rewards) {
              final displayedRewards = _filterAndMergeRewards(rewards);
              final hasSearch = _searchQuery.trim().isNotEmpty;
              final gameGroups = _buildGameGroups(
                displayedRewards,
                joinedGames,
                hasSearch,
              );

              if (gameGroups.isEmpty && !hasSearch) {
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
                          'No games or rewards yet',
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

              final totalUnclaimed = rewards
                  .where((r) => r.isAvailable)
                  .length;
              final allExpanded =
                  gameGroups.isNotEmpty &&
                  gameGroups.every((g) => _expandedGameIds.contains(g.gameId));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDisclaimerBanner(),
                  const SizedBox(height: 12),
                  _buildSearchBar(),
                  const SizedBox(height: 14),
                  if (gameGroups.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.layers_outlined,
                                size: 17,
                                color: AppTheme.secondaryColor,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Participated Games (${gameGroups.length}) • $totalUnclaimed Unclaimed Prize${totalUnclaimed == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (gameGroups.length > 1 && !hasSearch)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                if (allExpanded) {
                                  _expandedGameIds.clear();
                                } else {
                                  for (final g in gameGroups) {
                                    _expandedGameIds.add(g.gameId);
                                  }
                                }
                              });
                            },
                            icon: Icon(
                              allExpanded
                                  ? Icons.unfold_less_rounded
                                  : Icons.unfold_more_rounded,
                              size: 16,
                              color: AppTheme.secondaryColor,
                            ),
                            label: Text(
                              allExpanded ? 'Collapse All' : 'Expand All',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (gameGroups.isEmpty)
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
                    ...gameGroups.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildGameDrawerCard(
                          context,
                          group,
                          forceExpanded: hasSearch,
                        ),
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

  Widget _buildGameDrawerCard(
    BuildContext context,
    _ParticipatedGameGroup group, {
    required bool forceExpanded,
  }) {
    final isExpanded =
        forceExpanded || _expandedGameIds.contains(group.gameId);
    final unclaimed = group.unclaimedCount;
    final total = group.totalRewards;
    final dateStr = group.gameDate != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(group.gameDate!.toLocal())
        : null;

    Color borderColor;
    if (unclaimed > 0) {
      borderColor = AppTheme.accentSuccess.withValues(alpha: 0.65);
    } else if (total > 0) {
      borderColor = AppTheme.secondaryColor.withValues(alpha: 0.45);
    } else {
      borderColor = const Color(0xFF2E334D);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: unclaimed > 0 ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsible Drawer Header
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                if (_expandedGameIds.contains(group.gameId)) {
                  _expandedGameIds.remove(group.gameId);
                } else {
                  _expandedGameIds.add(group.gameId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Game Code Badge
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'CODE',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFA0AEC0),
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          group.inviteCode,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            color: AppTheme.secondaryColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Game Name & Subheader (Date + Organizer)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.gameName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (dateStr != null) dateStr,
                            if (group.organizerName != null &&
                                group.organizerName!.trim().isNotEmpty)
                              'Host: ${group.organizerName}',
                          ].join(' • '),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Unclaimed Prizes Count Badge on Drawer Heading
                  _buildDrawerHeadingCountBadge(unclaimed, total),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFFCBD5E1),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // Expanded Drawer Content
          if (isExpanded) ...[
            const Divider(color: Color(0xFF2E334D), height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: group.rewards.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E334D)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.confirmation_number_outlined,
                                  size: 18,
                                  color: Color(0xFF94A3B8),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Participated in this game • No prize claims won.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                context.push('/play/${group.gameId}'),
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                            ),
                            label: const Text(
                              'View Game',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.secondaryColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < group.rewards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _buildRewardCard(context, group.rewards[i]),
                        ],
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawerHeadingCountBadge(int unclaimedCount, int totalRewards) {
    if (unclaimedCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.accentSuccess.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accentSuccess),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 14,
              color: AppTheme.accentSuccess,
            ),
            const SizedBox(width: 4),
            Text(
              '$unclaimedCount Unclaimed',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentSuccess,
              ),
            ),
          ],
        ),
      );
    }

    if (totalRewards > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 13,
              color: AppTheme.secondaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              '0 Unclaimed ($totalRewards Claimed)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: const Text(
        '0 Unclaimed',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8),
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
    final claimedDateStr = reward.claimedAt != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(reward.claimedAt!.toLocal())
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                    color: isAvailable
                        ? AppTheme.secondaryColor
                        : const Color(0xFF94A3B8),
                    decoration: isAvailable
                        ? null
                        : TextDecoration.lineThrough,
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
          if (!isAvailable && claimedDateStr != null) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              Icons.verified_rounded,
              'Claimed on',
              claimedDateStr,
            ),
          ],
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAvailable
              ? AppTheme.accentSuccess.withValues(alpha: 0.5)
              : const Color(0xFF2E334D),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(14),
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
                    Icon(
                      isAvailable
                          ? Icons.emoji_events
                          : Icons.verified_rounded,
                      color: isAvailable
                          ? AppTheme.secondaryColor
                          : const Color(0xFF10B981),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        Formatters.formatPrizeName(reward.prizeType),
                        style: const TextStyle(
                          fontSize: 15.5,
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
                      : const Color(0xFF10B981).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAvailable
                        ? AppTheme.accentSuccess
                        : const Color(0xFF10B981).withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  isAvailable ? 'CLAIM FROM ORGANIZER' : '✓ CLAIMED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isAvailable
                        ? AppTheme.accentSuccess
                        : const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),

          const Divider(color: Color(0xFF2E334D), height: 18),

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
                  size: isWide ? 110.0 : 96.0,
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

          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E334D)),
            ),
            child: Row(
              children: [
                Icon(
                  isAvailable
                      ? Icons.info_outline
                      : Icons.check_circle_outline_rounded,
                  size: 14,
                  color: isAvailable
                      ? const Color(0xFFA0AEC0)
                      : const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAvailable
                        ? 'Show this QR or code to ${reward.organizerName ?? 'your game organizer'} to collect your prize.'
                        : 'This prize claim has been settled and closed by ${reward.organizerName ?? 'your game organizer'}.',
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
