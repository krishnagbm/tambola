import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import 'dashboard_hero_section.dart';
import 'flash_housie_solo_dialog.dart';

/// Responsive Two-Part Dashboard Arena:
/// - Desktop (>= 880px): Side-by-side 2-column split
///   - Left Column: Part 1 — Classic 90-Ball Bingo, Tambola & Housie (Luck-Based Party Hub)
///   - Right Column: Part 2 — DabHousie™ Skill Arena (Sequential Levels 1–5 & Filters)
/// - Mobile / Tablet (< 880px): Stacked cleanly
class TwoPartDashboardArena extends StatelessWidget {
  const TwoPartDashboardArena({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSideBySide = constraints.maxWidth >= 880;
        if (isSideBySide) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: DashboardHeroSection(),
              ),
              SizedBox(width: 16),
              Expanded(
                flex: 13,
                child: SkillArenaSection(),
              ),
            ],
          );
        }

        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardHeroSection(),
            SizedBox(height: 14),
            SkillArenaSection(),
          ],
        );
      },
    );
  }
}

class _SkillLevelItem {
  final String id;
  final String levelBadge;
  final String title;
  final String subtitle;
  final String category; // 'memory', 'speed', 'puzzle'
  final String categoryLabel;
  final String playModes;
  final String controls;
  final String unlockRequirement;
  final bool isUnlocked;

  const _SkillLevelItem({
    required this.id,
    required this.levelBadge,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.categoryLabel,
    required this.playModes,
    required this.controls,
    required this.unlockRequirement,
    this.isUnlocked = false,
  });
}

class SkillArenaSection extends StatefulWidget {
  const SkillArenaSection({super.key});

  @override
  State<SkillArenaSection> createState() => _SkillArenaSectionState();
}

class _SkillArenaSectionState extends State<SkillArenaSection> {
  String _selectedFilter = 'all';
  bool _showAllLockedLevels = false;
  bool _level1Completed = false;
  int _level1BestScore = 0;

  static const List<_SkillLevelItem> _levels = [
    _SkillLevelItem(
      id: 'level_1_flash',
      levelBadge: 'LEVEL 1 • UNLOCKED',
      title: '⚡ FlashHousie™ 5 • 10 • 15',
      subtitle:
          'Memorize your 3×3 quadrant during the live NeuroWave™ Spotlight sweep, then combine spatial memory, logical column reasoning & speed to recall called balls! Wrong guesses deduct score.',
      category: 'memory',
      categoryLabel: '🧠 Memory & Logic',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Open Now — Complete Level 1 to unlock Level 2!',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_2_row',
      levelBadge: 'LEVEL 2 • LOCKED',
      title: '📏 RowHousie™ 1 • 2 • 3',
      subtitle:
          'Horizontal 1–90 Row Memory & Reasoning! Memorize 5 numbers and 4 blanks across full 9-column rows (R1, R2, R3, pairs, or all 3 rows) on the same 3×9 grid.',
      category: 'memory',
      categoryLabel: '🧠 Memory & Logic',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 1 (FlashHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_3a_fasttap',
      levelBadge: 'LEVEL 3A • LOCKED',
      title: '⚡ FastTap™ Housie (Fastest Finger)',
      subtitle:
          'High-speed reflex showdown! All players receive the exact same visible 3×9 ticket and race to tap called numbers first for Fastest 5, 10, 15 & Full House.',
      category: 'speed',
      categoryLabel: '⚡ Speed & Reflex',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 2 (RowHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_3b_blast',
      levelBadge: 'LEVEL 3B • LOCKED',
      title: '🎯 BlastHousie™ (45° Arcade Shooter)',
      subtitle:
          'Slide your horizontal turret & tilt ±45° to blast called numbers! Bigger numbers in bottom rows block smaller top numbers — snipe through blank lanes or clear blockers first.',
      category: 'speed',
      categoryLabel: '🎯 Speed & Arcade',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '⌨️ Keys • 🎮 Controller • 👆 Touch',
      unlockRequirement: 'Unlocks after completing Level 3A (FastTap™)',
    ),
    _SkillLevelItem(
      id: 'level_4_swap',
      levelBadge: 'LEVEL 4 • LOCKED',
      title: '🧩 SwapHousie™ (Shuffle & Swap)',
      subtitle:
          'All 15 balls and 12 empty spaces are scrambled across the 3×9 grid. Drag & swap balls or blanks to restore valid column decades, ascending order & 5-per-row balance.',
      category: 'puzzle',
      categoryLabel: '🧩 Logic & Puzzle',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Drag-Drop • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 3B (BlastHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_5_stick',
      levelBadge: 'LEVEL 5 • LOCKED',
      title: '🏗️ StickHousie™ (Gravity & Team Co-Op)',
      subtitle:
          'Balls roll into the pool! Stack 15 number balls + 12 structural dummy boxes without letting bigger balls pluck smaller ones. Supports 3–6 player Team Play (2 per quadrant)!',
      category: 'puzzle',
      categoryLabel: '🏗️ Physics & Team Co-Op',
      playModes: '👤 Solo • 👥 Multi • 🤝 3–6 Team',
      controls: '👆 Drag-Drop • 🎮 Controller',
      unlockRequirement: 'Unlocks after completing Level 4 (SwapHousie™)',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSoloProgress();
  }

  Future<void> _loadSoloProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _level1Completed =
            prefs.getBool('dabhousie_skill_level_1_completed') ?? false;
        _level1BestScore =
            prefs.getInt('dabhousie_skill_level_1_best_score') ?? 0;
      });
    } catch (_) {}
  }

  void _showLockedLevelDialog(BuildContext context, _SkillLevelItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.5),
          ),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.lock_clock_rounded,
              color: AppTheme.secondaryColor,
              size: 26,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    color: AppTheme.secondaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sequential Unlock Rule: Levels open one after another! (${item.unlockRequirement})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              item.subtitle,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFFE2E8F0),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildMiniMetaBadge(item.categoryLabel, const Color(0xFF38BDF8)),
                _buildMiniMetaBadge(item.playModes, const Color(0xFF69F0AE)),
                _buildMiniMetaBadge(item.controls, const Color(0xFFFBBF24)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got It'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              FlashHousieSoloDialog.show(
                context,
                onLevelCompleted: _loadSoloProgress,
              );
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text(
              'Play Level 1 Now',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetaBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredLevels = _levels.where((lvl) {
      if (_selectedFilter == 'all') return true;
      return lvl.category == _selectedFilter;
    }).toList();

    final lockedItems = filteredLevels.where((l) => !l.isUnlocked).toList();
    final visibleLockedItems = (_selectedFilter != 'all' || _showAllLockedLevels)
        ? lockedItems
        : lockedItems.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.secondaryColor.withValues(alpha: 0.13),
            AppTheme.primaryColor.withValues(alpha: 0.24),
            AppTheme.darkCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Eyebrow & Sequential Rule Banner
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '🧠⚡ PART 2 • DABHOUSIE™ SKILL SPECIALS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.45),
                  ),
                ),
                child: const Text(
                  '👤 Solo • 👥 Multiplayer • 🤝 Team Play',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF69F0AE),
                  ),
                ),
              ),
              if (_level1Completed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981)),
                  ),
                  child: Text(
                    '🏆 Lvl 1 Cleared (Best: $_level1BestScore pts)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Sequential Level Chain Callout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.secondaryColor.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.lock_open_rounded,
                      size: 15,
                      color: AppTheme.secondaryColor,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sequential Level Progression — Levels open one after another!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChainStep('🔓 Lvl 1: FlashHousie™', true),
                      _buildChainArrow(),
                      _buildChainStep('🔒 Lvl 2: RowHousie™', false),
                      _buildChainArrow(),
                      _buildChainStep('🔒 Lvl 3: FastTap™ & Blast™', false),
                      _buildChainArrow(),
                      _buildChainStep('🔒 Lvl 4: SwapHousie™', false),
                      _buildChainArrow(),
                      _buildChainStep('🔒 Lvl 5: StickHousie™', false),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'All Skill Levels (5)'),
                const SizedBox(width: 6),
                _buildFilterChip('memory', '🧠 Memory & Logic'),
                const SizedBox(width: 6),
                _buildFilterChip('speed', '⚡ Speed & Arcade'),
                const SizedBox(width: 6),
                _buildFilterChip('puzzle', '🧩 Puzzle & Physics'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Level 1 Unlocked Featured Card (if matches filter)
          if (filteredLevels.any((l) => l.isUnlocked)) ...[
            _buildUnlockedLevel1Card(
              context,
              filteredLevels.firstWhere((l) => l.isUnlocked),
            ),
            const SizedBox(height: 10),
          ],

          // Sequential Locked Levels Preview List
          if (visibleLockedItems.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔒 UPCOMING SEQUENTIAL LEVELS (OPEN ONE BY ONE)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5,
                  ),
                ),
                if (_selectedFilter == 'all' && lockedItems.length > 2)
                  InkWell(
                    onTap: () => setState(
                      () => _showAllLockedLevels = !_showAllLockedLevels,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        _showAllLockedLevels
                            ? 'Show Compact ▲'
                            : 'View All ${lockedItems.length} Levels ▼',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...visibleLockedItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildLockedLevelCard(context, item),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChainStep(String label, bool unlocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: unlocked
            ? AppTheme.secondaryColor.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: unlocked
              ? AppTheme.secondaryColor
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: unlocked ? AppTheme.secondaryColor : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildChainArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 13,
        color: Color(0xFF64748B),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.secondaryColor
              : const Color(0xFF0F172A).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.secondaryColor
                : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockedLevel1Card(BuildContext context, _SkillLevelItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B36),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '🔓 LEVEL 1 • OPEN NOW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
              _buildMiniMetaBadge(item.categoryLabel, AppTheme.secondaryColor),
              _buildMiniMetaBadge(item.playModes, const Color(0xFF38BDF8)),
              _buildMiniMetaBadge(item.controls, const Color(0xFFA78BFA)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFE2E8F0),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => FlashHousieSoloDialog.show(
                  context,
                  onLevelCompleted: _loadSoloProgress,
                ),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 17),
                label: const Text(
                  'Play Solo (Instant)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/join'),
                icon: const Icon(Icons.vpn_key_rounded, size: 16),
                label: const Text(
                  'Join Room',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/create-game'),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text(
                  'Host Room',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryLight,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLockedLevelCard(BuildContext context, _SkillLevelItem item) {
    return InkWell(
      onTap: () => _showLockedLevelDialog(context, item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E3A59)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppTheme.secondaryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Text(
                          item.levelBadge,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        size: 13,
                        color: Color(0xFFFBBF24),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.unlockRequirement,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFBBF24),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        item.controls,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
