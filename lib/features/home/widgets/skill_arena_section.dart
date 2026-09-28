import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import 'dashboard_hero_section.dart';
import 'flash_housie_solo_dialog.dart';

/// Responsive Two-Column Dashboard Arena:
/// - Desktop (>= 860px): Equal-height 2-column split (Left: Luck • Classic Bingo, Right: Skill • DabHousie™ Specials)
/// - Mobile / Tablet (< 860px): Stacked cleanly
class TwoPartDashboardArena extends StatelessWidget {
  const TwoPartDashboardArena({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSideBySide = constraints.maxWidth >= 860;
        if (isSideBySide) {
          return const IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: DashboardHeroSection(),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: SkillArenaSection(),
                ),
              ],
            ),
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
  final String category;
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
  int _level0ClearedCount = 0;
  bool _level1Completed = false;
  int _level1BestScore = 0;

  static const List<_SkillLevelItem> _levels = [
    _SkillLevelItem(
      id: 'level_0a_make',
      levelBadge: 'LEVEL 0A • OPEN NOW',
      title: '🎓 Level 0A: MakeHousie™ (Ticket Rule Builder)',
      subtitle:
          'Natural Step 1 — Grab mystery balls (?) to reveal their numbers and spontaneously drag & drop them into valid 3×9 column decades (1–9 … 80–90) and vertical ascending order!',
      category: 'foundation',
      categoryLabel: '🎓 Rules & Drag-Drop',
      playModes: '👤 Solo • 👥 Multi Race',
      controls: '👆 Drag-Drop • 🖱️ Mouse',
      unlockRequirement: 'Open Now for Solo Play — Natural Foundation Step 1',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_0b_fix',
      levelBadge: 'LEVEL 0B • OPEN NOW',
      title: '🔍 Level 0B: FixHousie™ (Spot the Mistake)',
      subtitle:
          'Natural Step 2 — Inspect a pre-filled 3×9 ticket and spot 1, 3, or 5 intentional rule bugs: wrong column decade, flipped vertical sequence, duplicate numbers, or >90 balls! Scored on speed & accuracy.',
      category: 'foundation',
      categoryLabel: '🔍 Audit & Logic',
      playModes: '👤 Solo • 👥 Multi Race',
      controls: '👆 Touch • 🖱️ Mouse',
      unlockRequirement: 'Open Now for Solo Play — Natural Foundation Step 2',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_0c_math',
      levelBadge: 'LEVEL 0C • OPEN NOW',
      title: '➕ Level 0C: MathHousie™ (Formula-to-Grid Hunt)',
      subtitle:
          'Natural Step 3 — Mental math meets 3×9 column logic! Solve the live formula above the board (e.g. 67 + 3 = ??, 14 × 5 = ??), jump straight to the right decade column, and tap the answer on the grid.',
      category: 'math',
      categoryLabel: '➕ Mental Math & Hunt',
      playModes: '👤 Solo • 👥 Multi Race',
      controls: '👆 Touch • 🖱️ Mouse',
      unlockRequirement: 'Open Now for Solo Play — Natural Foundation Step 3',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_0d_sum',
      levelBadge: 'LEVEL 0D • OPEN NOW',
      title: '🧮 Level 0D: SumHousie™ (Quadrant Rapid Sum)',
      subtitle:
          'Natural Step 4 — Add all 5 numbers inside an active 3×3 quadrant (Q1, Q2, or Q3) before the timer runs out and pick the exact total from 4 smart multiple-choice options (with same-last-digit decoys)!',
      category: 'math',
      categoryLabel: '🧮 Rapid Addition MCQ',
      playModes: '👤 Solo • 👥 Fastest Finger',
      controls: '👆 Touch • 🖱️ Mouse',
      unlockRequirement:
          'Open Now for Solo Play — Natural Foundation Step 4 (Leads into Level 1 FlashHousie™)',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_1_flash',
      levelBadge: 'LEVEL 1 • OPEN NOW',
      title: '⚡ Level 1: FlashHousie™ 5 • 10 • 15',
      subtitle:
          'Playable Now! Memorize your 3×3 quadrant during the live NeuroWave™ Spotlight sweep, then combine spatial memory, logical column reasoning & speed to recall called balls! Wrong guesses deduct score.',
      category: 'memory',
      categoryLabel: '🧠 Memory & Logic',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Open Now for Solo & Live Play — Unlocks Level 2 (RowHousie™)',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_2_row',
      levelBadge: 'LEVEL 2 • LOCKED',
      title: '📏 Level 2: RowHousie™ 1 • 2 • 3',
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
      title: '⚡ Level 3A: FastTap™ Housie (Fastest Finger)',
      subtitle:
          'High-speed reflex showdown! All players receive the exact same visible 3×9 ticket and race to tap called numbers first for Fastest 5, 10, 15 & Full House.',
      category: 'speed',
      categoryLabel: '⚡ Speed & Reflex',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 2 (RowHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_3b_swap',
      levelBadge: 'LEVEL 3B • LOCKED',
      title: '🧩 Level 3B: SwapHousie™ (Shuffle & Swap)',
      subtitle:
          'All 15 balls and 12 empty spaces are scrambled across the 3×9 grid. Drag & swap balls or blanks to restore valid column decades, ascending order & 5-per-row balance.',
      category: 'puzzle',
      categoryLabel: '🧩 Logic & Puzzle',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Drag-Drop • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 3A (FastTap™)',
    ),
    _SkillLevelItem(
      id: 'level_4_blast',
      levelBadge: 'LEVEL 4 • LOCKED',
      title: '🎯 Level 4: BlastHousie™ (45° Arcade Shooter)',
      subtitle:
          'Slide your horizontal turret & tilt ±45° to blast called numbers! Bigger numbers in bottom rows block smaller top numbers — snipe through blank lanes or clear blockers first.',
      category: 'speed',
      categoryLabel: '🎯 Speed & Arcade',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '⌨️ Keys • 🎮 Controller • 👆 Touch',
      unlockRequirement: 'Unlocks after completing Level 3B (SwapHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_5_stick',
      levelBadge: 'LEVEL 5 • LOCKED',
      title: '🏗️ Level 5: StickHousie™ (Gravity & Team Co-Op)',
      subtitle:
          'Balls roll into the pool! Stack 15 number balls + 12 structural dummy boxes without letting bigger balls pluck smaller ones. Supports 3–6 player Team Play (2 per quadrant)!',
      category: 'puzzle',
      categoryLabel: '🏗️ Physics & Team Co-Op',
      playModes: '👤 Solo • 👥 Multi • 🤝 3–6 Team',
      controls: '👆 Drag-Drop • 🎮 Controller',
      unlockRequirement: 'Unlocks after completing Level 4 (BlastHousie™)',
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
      int l0Count = 0;
      for (final id in const [
        'level_0a_make',
        'level_0b_fix',
        'level_0c_math',
        'level_0d_sum',
      ]) {
        if (prefs.getBool('dabhousie_skill_${id}_completed') ?? false) {
          l0Count++;
        }
      }
      setState(() {
        _level0ClearedCount = l0Count;
        _level1Completed =
            prefs.getBool('dabhousie_skill_level_1_completed') ?? false;
        _level1BestScore =
            prefs.getInt('dabhousie_skill_level_1_best_score') ?? 0;
      });
    } catch (_) {}
  }

  void _showUpcomingLevelsPopup(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _UpcomingLevelsDialog(
        levels: _levels,
        onPlayLevel: (gameId, {bool withFriends = false}) {
          Navigator.of(ctx).pop();
          FlashHousieSoloDialog.show(
            context,
            initialGameId: gameId,
            initialFriendMode: withFriends,
            onLevelCompleted: _loadSoloProgress,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 20 : 16,
        vertical: isWide ? 18 : 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [
            AppTheme.secondaryColor.withValues(alpha: 0.16),
            AppTheme.primaryColor.withValues(alpha: 0.28),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Eyebrow badges (Skill • Solo · Multiplayer · Team)
          SizedBox(
            height: 26,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '🧠⚡ SKILL • DABHOUSIE™',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      '👤 Solo',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text(
                      '👥 Multiplayer',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA855F7).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text(
                      '🤝 Team',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD8B4FE),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2-Line Headline matching Left Card (locked height)
          SizedBox(
            height: isWide ? 29 : 24,
            child: Text(
              'Memorize, Reason & Win',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isWide ? 24 : 20,
                fontWeight: FontWeight.w900,
                color: AppTheme.secondaryColor,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: isWide ? 27 : 22,
            child: Text(
              'FlashHousie™ & Skill Specials',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isWide ? 22 : 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Concise Subhead matching Left Card (exact 38px 2-line slot on desktop, 54px 3-line slot on mobile)
          SizedBox(
            height: isWide ? 38 : 54,
            child: Text(
              'Playable 3×9 skill games — MakeHousie™, FixHousie™, MathHousie™, SumHousie™, FlashHousie™ (5•10•15) & upcoming Levels 2–5.',
              maxLines: isWide ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isWide ? 13 : 12.5,
                color: const Color(0xFFCBD5E1),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            height: 18,
            child: Text(
              'Play solo, share a code with up to 4 friends free (no host needed), or host a skill playlist.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF34D399),
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // CTAs: Play Solo + Play with Friends + Host a Game (exact 40px single row)
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => FlashHousieSoloDialog.show(
                      context,
                      initialFriendMode: false,
                      onLevelCompleted: _loadSoloProgress,
                    ),
                    icon: const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 17,
                    ),
                    label: const Text('Play Solo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => FlashHousieSoloDialog.show(
                      context,
                      initialFriendMode: true,
                      onLevelCompleted: _loadSoloProgress,
                    ),
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: const Text('Play with Friends'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/create-game'),
                    icon: const Icon(Icons.add_circle_outline, size: 17),
                    label: const Text('Host a Game'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: Text(
              '🔓 Lvl 0 (Make • Fix • Math • Sum${_level0ClearedCount > 0 ? " $_level0ClearedCount/4✓" : ""}) & Lvl 1 Flash™${_level1Completed ? " ($_level1BestScore pts)" : " Open Now"} • 🔒 Lvl 2–5',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Upcoming Sequential Levels Popup Trigger (exact 52px 2-line box)
          InkWell(
            onTap: () => _showUpcomingLevelsPopup(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              height: 52,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    color: AppTheme.secondaryColor,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Skill Levels (0→5): Make™ • Fix™ • Math™ • Sum™ → Flash™\nRowHousie™ • FastTap™ • Swap™ • Blast™ • Stick™ →',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryColor,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2E334D), height: 1),
          const SizedBox(height: 10),
          _buildSkillTrustStrip(isWide),
        ],
      ),
    );
  }

  Widget _buildSkillTrustStrip(bool isWide) {
    const line1 = [
      '⚡ NeuroWave™ Spotlight',
      '🧠 Memory & Column Logic',
      '🏆 Live Leaderboards',
    ];
    const line2 = [
      '🔓 Lvl 0→5 Progression',
      '👥 Free 5-Player Friend Code',
      '⌨️ Touch, Mouse & Keys',
    ];

    Widget buildLine(List<String> items) {
      return SizedBox(
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              Flexible(
                child: Text(
                  items[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA0AEC0),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (i < items.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF718096),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildLine(line1),
        const SizedBox(height: 5),
        buildLine(line2),
      ],
    );
  }
}

/// Popup Dialog showing only level headings at a glance, with click-to-toggle descriptions.
class _UpcomingLevelsDialog extends StatefulWidget {
  final List<_SkillLevelItem> levels;
  final void Function(String gameId, {bool withFriends}) onPlayLevel;

  const _UpcomingLevelsDialog({
    required this.levels,
    required this.onPlayLevel,
  });

  @override
  State<_UpcomingLevelsDialog> createState() => _UpcomingLevelsDialogState();
}

class _UpcomingLevelsDialogState extends State<_UpcomingLevelsDialog> {
  String? _expandedId = 'level_0a_make';

  @override
  Widget build(BuildContext context) {
    final selectedUnlockedId =
        (_expandedId != null &&
            widget.levels.any((l) => l.id == _expandedId && l.isUnlocked))
        ? _expandedId!
        : 'level_1_flash';

    return Dialog(
      backgroundColor: AppTheme.darkCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppTheme.secondaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'DabHousie™ Skill Levels (Levels 0–5)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '🎓 Natural Path: Level 0 (Make • Fix • Math • Sum, Open Now) → Level 1 (FlashHousie™, Open Now) → Levels 2–5. Tap any level to toggle.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.secondaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: widget.levels.map((item) {
                      final isExpanded = _expandedId == item.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _expandedId = isExpanded ? null : item.id;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: item.isUnlocked
                                  ? const Color(0xFF132238)
                                  : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: item.isUnlocked
                                    ? const Color(0xFF10B981)
                                    : (isExpanded
                                          ? AppTheme.secondaryColor
                                          : const Color(0xFF2E3A59)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Heading row only at a glance
                                Row(
                                  children: [
                                    Icon(
                                      item.isUnlocked
                                          ? Icons.lock_open_rounded
                                          : Icons.lock_outline_rounded,
                                      size: 16,
                                      color: item.isUnlocked
                                          ? const Color(0xFF34D399)
                                          : AppTheme.secondaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.isUnlocked
                                            ? const Color(0xFF10B981)
                                            : AppTheme.secondaryColor
                                                  .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        item.levelBadge,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          color: item.isUnlocked
                                              ? Colors.black
                                              : AppTheme.secondaryColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                  ],
                                ),
                                // Toggleable details
                                if (isExpanded) ...[
                                  const SizedBox(height: 8),
                                  const Divider(
                                    color: Color(0xFF2E3A59),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.subtitle,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFCBD5E1),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '🔗 ${item.unlockRequirement}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            _buildTag(item.categoryLabel),
                                            _buildTag(item.playModes),
                                            _buildTag(item.controls),
                                          ],
                                        ),
                                      ),
                                      if (item.isUnlocked) ...[
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          onPressed: () => widget.onPlayLevel(
                                            item.id,
                                            withFriends: false,
                                          ),
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'Play Solo',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF10B981,
                                            ),
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        ElevatedButton.icon(
                                          onPressed: () => widget.onPlayLevel(
                                            item.id,
                                            withFriends: true,
                                          ),
                                          icon: const Icon(
                                            Icons.groups_rounded,
                                            size: 15,
                                          ),
                                          label: const Text(
                                            'Friends',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppTheme.secondaryColor,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '© 2026 DabHousie™ by Digital App Studio. MakeHousie™, FixHousie™, MathHousie™, SumHousie™, FlashHousie™, RowHousie™, FastTap™, SwapHousie™, BlastHousie™, StickHousie™ & NeuroWave™ are proprietary skill formats, copyrighted UI expressions, and trademarks. All rights reserved.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onPlayLevel(
                      selectedUnlockedId,
                      withFriends: false,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text(
                      'Play Solo',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.black,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onPlayLevel(
                      selectedUnlockedId,
                      withFriends: true,
                    ),
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: const Text(
                      'Play with Friends',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: Colors.black,
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

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
