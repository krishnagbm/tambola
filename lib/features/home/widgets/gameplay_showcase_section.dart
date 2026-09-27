import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class GameplayShowcaseSection extends StatefulWidget {
  const GameplayShowcaseSection({super.key});

  @override
  State<GameplayShowcaseSection> createState() => _GameplayShowcaseSectionState();
}

class _GameplayShowcaseSectionState extends State<GameplayShowcaseSection> {
  int _selectedIndex = 0;
  Timer? _autoSlideTimer;

  static const _slides = [
    {
      'title': 'Player Ticket & Instant Play',
      'tabLabel': '📱 Player Tickets',
      'badge': '100% WEB PLAY • NO APP REQUIRED',
      'image': 'assets/screenshots/screenshot_mobile_ticket.png',
      'desc': 'Crisp 3×9 digital tickets in any browser (Safari, Chrome). Players dab called numbers in real time, track drawn balls, and submit instant prize claims.',
      'aspectRatio': 1.08,
    },
    {
      'title': 'FlashHousie™ Solo Arena — Perfect 5/5 Recall (50 pts)',
      'tabLabel': '👤 Solo Q1 Perfect (50 pts)',
      'badge': 'INSTANT SOLO SKILL PRACTICE • FLASH 5 / 10 / 15 SELECTOR',
      'image': 'assets/screenshots/screenshot_flash_housie_solo_win.png',
      'desc': 'Practice anytime on mobile or desktop! Choose Flash 5 (1 Quad), Flash 10 (2 Quads), or Flash 15 (3 Quads), memorize the NeuroWave™ sweep, and track your score & reaction time.',
      'aspectRatio': 0.90,
    },
    {
      'title': 'FlashHousie™ Solo Arena — Live Ball Call & Score Tracker',
      'tabLabel': '⚡ Solo Live Call & Score',
      'badge': 'REAL-TIME BALL CALLER • +10 PTS RECALL • -3 PTS FREEZE PENALTY',
      'image': 'assets/screenshots/screenshot_flash_housie_solo_live.png',
      'desc': 'Live solo practice HUD showing drawn ball history, active quadrant (Q1 Cols 1–29), recalled count (5/5), penalty tracker, and net score in real time.',
      'aspectRatio': 0.81,
    },
    {
      'title': 'FlashHousie™ Solo Arena — Quadrant Q3 Spatial Deduction',
      'tabLabel': '🎯 Solo Q3 (Cols 7–9)',
      'badge': '3×3 QUADRANT ROTATION • COLUMN DECADE LOGIC (60–90)',
      'image': 'assets/screenshots/screenshot_flash_housie_solo_q3.png',
      'desc': 'Every solo card rotates across Q1 (1–29), Q2 (30–59), or Q3 (60–90) so players master all 9 decade columns and vertical ascending sequences.',
      'aspectRatio': 0.90,
    },
    {
      'title': 'FlashHousie™ 5 / 10 / 15 Live Recall & Round Prizes',
      'tabLabel': '⚡ FlashHousie™ Recall',
      'badge': 'DABHOUSIE™ PROPRIETARY SPECIAL • MEMORY + REASONING + SPEED',
      'image': 'assets/screenshots/screenshot_flash_housie_player.png',
      'desc': 'Memorize active 3×3 quadrants during the NeuroWave™ Spotlight sweep, then combine spatial memory & logical column reasoning to recall called balls and win Round & Full House prizes.',
      'aspectRatio': 3.35,
    },
    {
      'title': 'NeuroWave™ Spotlight & Mystery [?] Quadrant Grid',
      'tabLabel': '🧠 NeuroWave™ [?] Grid',
      'badge': 'COLUMN-BY-COLUMN SPOTLIGHT REVEAL • SYMMETRIC SKILL PLAY',
      'image': 'assets/screenshots/screenshot_flash_housie_locked.png',
      'desc': 'After the NeuroWave™ Spotlight sweeps each active column, numbers lock into [?] tiles while inactive quadrants stay locked for future rounds.',
      'aspectRatio': 3.22,
    },
    {
      'title': 'FlashHousie™ Host Control & Live Recall Leaderboard',
      'tabLabel': '🏆 FlashHousie™ Host',
      'badge': 'AUTO-SCORED ROUND WINNERS & CUMULATIVE FULL HOUSE',
      'image': 'assets/screenshots/screenshot_flash_housie_host.png',
      'desc': 'Hosts track real-time player recall accuracy, reaction speed, and live round leaderboards with automatic Round (Rx-Qx) and Full House winner crowning.',
      'aspectRatio': 2.22,
    },
    {
      'title': 'TV Screen & Projector Big Display',
      'tabLabel': '📺 TV & Projector Mode',
      'badge': 'PERFECT FOR PARTIES & 50+ PLAYER GALAS',
      'image': 'assets/screenshots/screenshot_tv_mode.png',
      'desc': 'Cast live to big screen TVs, clubhouse projectors, and auditoriums. Features glowing 1–90 board, automated audio caller, and synchronized real-time game status.',
      'aspectRatio': 1.93,
    },
    {
      'title': '50+ Player High-Capacity Multiplayer',
      'tabLabel': '👥 50+ Players Live',
      'badge': 'SCALABLE TO 250+ CONCURRENT PLAYERS',
      'image': 'assets/screenshots/screenshot_50_players.png',
      'desc': 'Battle-tested for large gatherings. Synchronized real-time dabs, instant multi-device win notifications, and guaranteed 100% unique non-duplicate tickets.',
      'aspectRatio': 2.07,
    },
    {
      'title': 'Organizer Auto-Pilot & 1–90 Board',
      'tabLabel': '🎙️ Auto-Pilot Host',
      'badge': 'AUTOMATED CALLER & MASTER BOARD',
      'image': 'assets/screenshots/screenshot_organizer_control.png',
      'desc': 'Host smooth sessions with digital countdown timer, voice caller announcements, 1–90 glowing master board, and real-time confirmed player rosters.',
      'aspectRatio': 1.86,
    },
    {
      'title': 'Live Multi-Device Claim Validation',
      'tabLabel': '⚡ Instant Win Checks',
      'badge': 'SERVER-SIDE BOGEY CLAIM VALIDATION',
      'image': 'assets/screenshots/screenshot_multiplayer_claims.png',
      'desc': 'Multiplayer live sync: instant server validation for Early 5, Lines, and Full House. Premature claims trigger smart Bogey alerts to eliminate disputes.',
      'aspectRatio': 1.67,
    },
    {
      'title': 'Private Party Single-Use Passcodes',
      'tabLabel': '🛡️ Seat Passcodes',
      'badge': 'EXCLUSIVE EVENT & PARTY SECURITY',
      'image': 'assets/screenshots/screenshot_private_passcodes.png',
      'desc': 'Generate single-use seat OTPs for private kitty parties, society clubs, and corporate galas to ensure only invited guests can join.',
      'aspectRatio': 1.01,
    },
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _slides.length;
        });
      }
    });
  }

  void _onUserSelect(int index) {
    setState(() => _selectedIndex = index);
    _startTimer(); // reset auto-advance timer on manual interaction
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    super.dispose();
  }

  void _showZoomDialog(BuildContext context, Map<String, dynamic> slide) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      slide['title'] as String,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    slide['image'] as String,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                slide['desc'] as String,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1), height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _slides[_selectedIndex];
    final isSoloCategory = _selectedIndex >= 1 && _selectedIndex <= 3;
    final isSkillMultiplayerCategory = _selectedIndex >= 4 && _selectedIndex <= 6;
    final isClassicCategory = !isSoloCategory && !isSkillMultiplayerCategory;
    final visibleIndices = isSoloCategory
        ? const <int>[1, 2, 3]
        : (isSkillMultiplayerCategory
              ? const <int>[4, 5, 6]
              : const <int>[0, 7, 8, 9, 10, 11]);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2E334D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Header + Prev/Next Controls
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.videogame_asset_outlined,
                  color: AppTheme.secondaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See DabHousie in Action',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Solo Skill Arena • Live Multiplayer • Automated Calling • Server Claim Verification',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFA0AEC0),
                      ),
                    ),
                  ],
                ),
              ),
              // Slide Counter & Prev / Next buttons
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF151C35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _onUserSelect(
                        (_selectedIndex - 1 + _slides.length) % _slides.length,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '${_selectedIndex + 1} / ${_slides.length}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _onUserSelect(
                        (_selectedIndex + 1) % _slides.length,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category Tabs (1. Classic 90-Ball | 2. FlashHousie™ Solo Arena | 3. FlashHousie™ Live Multiplayer)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              InkWell(
                onTap: () => _onUserSelect(0),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isClassicCategory
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.2)
                        : const Color(0xFF13192E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isClassicCategory
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF2E334D),
                      width: isClassicCategory ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.casino_rounded,
                        size: 15,
                        color: isClassicCategory
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '🎲 Classic 90-Ball & Live Host (6)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isClassicCategory
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isClassicCategory
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => _onUserSelect(1),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSoloCategory
                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                        : const Color(0xFF13192E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSoloCategory
                          ? const Color(0xFF10B981)
                          : const Color(0xFF2E334D),
                      width: isSoloCategory ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: isSoloCategory
                            ? const Color(0xFF34D399)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '👤 FlashHousie™ Solo Play (3)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSoloCategory
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isSoloCategory
                              ? const Color(0xFF34D399)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () => _onUserSelect(4),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSkillMultiplayerCategory
                        ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                        : const Color(0xFF13192E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSkillMultiplayerCategory
                          ? AppTheme.secondaryColor
                          : const Color(0xFF2E334D),
                      width: isSkillMultiplayerCategory ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: isSkillMultiplayerCategory
                            ? AppTheme.secondaryColor
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '🧠⚡ FlashHousie™ Live Multiplayer (3)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSkillMultiplayerCategory
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isSkillMultiplayerCategory
                              ? AppTheme.secondaryColor
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Wrapped Screen Selector Buttons (Never cuts off at right edge)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in visibleIndices)
                InkWell(
                  onTap: () => _onUserSelect(i),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: i == _selectedIndex
                          ? AppTheme.primaryLight
                          : const Color(0xFF1B223C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: i == _selectedIndex
                            ? AppTheme.secondaryColor
                            : const Color(0xFF2E334D),
                        width: i == _selectedIndex ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      _slides[i]['tabLabel'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == _selectedIndex
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == _selectedIndex
                            ? Colors.white
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Image Showcase Preview Card
          GestureDetector(
            onTap: () => _showZoomDialog(context, current),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D1226),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E334D)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Badge & Expand Prompt
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: const Color(0xFF151C35),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            current['badge'] as String,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.zoom_in_rounded, size: 14, color: Color(0xFF94A3B8)),
                            SizedBox(width: 4),
                            Text(
                              'Tap to expand',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Image Container (Constrained for neat responsive height)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          current['image'] as String,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  // Description Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFF151C35),
                    child: Text(
                      current['desc'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCBD5E1),
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
