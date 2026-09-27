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
  final String levelTag;
  final String heading;
  final String description;
  final String categoryLabel;
  final String playModes;
  final String controls;
  final String unlockRequirement;
  final bool isUnlocked;

  const _SkillLevelItem({
    required this.id,
    required this.levelTag,
    required this.heading,
    required this.description,
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
  bool _level1Completed = false;
  int _level1BestScore = 0;

  static const List<_SkillLevelItem> _levels = [
    _SkillLevelItem(
      id: 'level_1_flash',
      levelTag: 'LEVEL 1 • OPEN NOW',
      heading: '⚡ Level 1: FlashHousie™ 5 • 10 • 15',
      description:
          'Memorize your 3×3 quadrant during the live NeuroWave™ Spotlight sweep, then combine spatial memory, logical column reasoning & speed to recall called balls! Wrong guesses deduct score.',
      categoryLabel: '🧠 Memory & Logic',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocked Now — Complete Level 1 to unlock Level 2',
      isUnlocked: true,
    ),
    _SkillLevelItem(
      id: 'level_2_row',
      levelTag: 'LEVEL 2 • LOCKED',
      heading: '📏 Level 2: RowHousie™ 1 • 2 • 3',
      description:
          'Horizontal 1–90 Row Memory & Reasoning! Memorize 5 numbers and 4 blanks across full 9-column rows (R1, R2, R3, pairs, or all 3 rows) on the same 3×9 grid.',
      categoryLabel: '🧠 Memory & Logic',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 1 (FlashHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_3a_fasttap',
      levelTag: 'LEVEL 3A • LOCKED',
      heading: '⚡ Level 3A: FastTap™ Housie (Fastest Finger)',
      description:
          'High-speed reflex showdown! All players receive the exact same visible 3×9 ticket and race to tap called numbers first for Fastest 5, 10, 15 & Full House.',
      categoryLabel: '⚡ Speed & Reflex',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Touch • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 2 (RowHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_3b_blast',
      levelTag: 'LEVEL 3B • LOCKED',
      heading: '🎯 Level 3B: BlastHousie™ (45° Arcade Shooter)',
      description:
          'Slide your horizontal turret & tilt ±45° to blast called numbers! Bigger numbers in bottom rows block smaller top numbers — snipe through blank lanes or clear blockers first.',
      categoryLabel: '🎯 Speed & Arcade',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '⌨️ Keys • 🎮 Controller • 👆 Touch',
      unlockRequirement: 'Unlocks after completing Level 3A (FastTap™)',
    ),
    _SkillLevelItem(
      id: 'level_4_swap',
      levelTag: 'LEVEL 4 • LOCKED',
      heading: '🧩 Level 4: SwapHousie™ (Shuffle & Swap)',
      description:
          'All 15 balls and 12 empty spaces are scrambled across the 3×9 grid. Drag & swap balls or blanks to restore valid column decades, ascending order & 5-per-row balance.',
      categoryLabel: '🧩 Logic & Puzzle',
      playModes: '👤 Solo • 👥 Multiplayer',
      controls: '👆 Drag-Drop • 🖱️ Mouse • ⌨️ Keys',
      unlockRequirement: 'Unlocks after completing Level 3B (BlastHousie™)',
    ),
    _SkillLevelItem(
      id: 'level_5_stick',
      levelTag: 'LEVEL 5 • LOCKED',
      heading: '🏗️ Level 5: StickHousie™ (Gravity & Team Co-Op)',
      description:
          'Balls roll into the pool! Stack 15 number balls + 12 structural dummy boxes without letting bigger balls pluck smaller ones. Supports 3–6 player Team Play (2 per quadrant)!',
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

  void _showUpcomingLevelsPopup(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _UpcomingLevelsDialog(
        levels: _levels,
        onPlayLevel1Solo: () {
          Navigator.of(ctx).pop();
          FlashHousieSoloDialog.show(
            context,
            onLevelCompleted: _loadSoloProgress,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 480;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eyebrow badges (No "Part 2" — just Skill)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '🧠⚡ SKILL • DABHOUSIE™ SPECIALS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Text(
                          _level1Completed
                              ? '🏆 Lvl 1 Cleared ($_level1BestScore pts)'
                              : '🔓 Level 1 Open Now',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF34D399),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 2-Line Headline matching Left Card
                  Text(
                    'Memorize, Reason & Win',
                    style: TextStyle(
                      fontSize: isWide ? 24 : 20,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.secondaryColor,
                      height: 1.18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'FlashHousie™ 5 • 10 • 15',
                    style: TextStyle(
                      fontSize: isWide ? 22 : 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Concise Subhead matching Left Card length
                  Text(
                    'Spot your 3×3 quadrant during the live NeuroWave™ sweep, then combine memory, column logic & speed to recall called balls across 1–3 rounds.',
                    style: TextStyle(
                      fontSize: isWide ? 13 : 12.5,
                      color: const Color(0xFFCBD5E1),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // CTAs: Play Solo + Join + Host
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => FlashHousieSoloDialog.show(
                          context,
                          onLevelCompleted: _loadSoloProgress,
                        ),
                        icon: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 18,
                        ),
                        label: const Text('Play Solo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 18,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/join'),
                        icon: const Text('🔑', style: TextStyle(fontSize: 15)),
                        label: const Text('Join a Game'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 18,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/create-game'),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Host a Game'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 18,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Levels open one after another • Solo, Multiplayer & Team modes',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Upcoming Sequential Levels Popup Trigger (matches Enterprise bar on Left Card)
                  InkWell(
                    onTap: () => _showUpcomingLevelsPopup(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
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
                            size: 15,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Upcoming Sequential Levels (Lvl 2–5): RowHousie™ • FastTap™ • Blast™ • Swap™ • Stick™ →',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.secondaryColor,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF2E334D), height: 1),
                  const SizedBox(height: 10),
                  _buildSkillTrustStrip(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkillTrustStrip() {
    const line1 = [
      '⚡ NeuroWave™ Spotlight',
      '🧠 Memory & Column Logic',
      '🏆 Live Round Leaderboards',
    ];
    const line2 = [
      '🔓 Sequential Level Unlocks',
      '👤 Instant Solo Practice',
      '⌨️ Touch, Mouse & Keys',
    ];

    Widget buildLine(List<String> items) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            Text(
              items[i],
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFA0AEC0),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (i < items.length - 1)
              const Text(
                '•',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF718096),
                ),
              ),
          ],
        ],
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
  final VoidCallback onPlayLevel1Solo;

  const _UpcomingLevelsDialog({
    required this.levels,
    required this.onPlayLevel1Solo,
  });

  @override
  State<_UpcomingLevelsDialog> createState() => _UpcomingLevelsDialogState();
}

class _UpcomingLevelsDialogState extends State<_UpcomingLevelsDialog> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
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
        constraints: const BoxConstraints(maxWidth: 560),
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
                      'DabHousie™ Skill Levels (1–5)',
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
                '🔗 Levels open one after another! Tap any level heading below to toggle details.',
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
                                        item.heading,
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
                                        item.levelTag,
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
                                    item.description,
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
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _buildTag(item.categoryLabel),
                                      _buildTag(item.playModes),
                                      _buildTag(item.controls),
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.onPlayLevel1Solo,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text(
                      'Play Level 1 Solo',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
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
