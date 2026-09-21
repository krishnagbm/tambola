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
      'tabLabel': '📱 Player Ticket',
      'badge': '100% WEB PLAY • NO APP REQUIRED',
      'image': 'assets/screenshots/screenshot_mobile_ticket.png',
      'desc': 'Crisp 3×9 digital tickets in any mobile browser (Safari, Chrome). Players tap drawn numbers, track game progress, and claim winning prizes with zero downloads.',
      'aspectRatio': 0.65, // vertical phone screenshot
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
      'desc': 'Instant server validation for Early 5, Lines, and Full House. False or premature claims are caught instantly by the server to eliminate disputes.',
      'aspectRatio': 1.85,
    },
    {
      'title': 'Private Party Single-Use Passcodes',
      'tabLabel': '🛡️ Seat Passcodes',
      'badge': 'EXCLUSIVE EVENT & PARTY SECURITY',
      'image': 'assets/screenshots/screenshot_private_passcodes.png',
      'desc': 'Generate unique, single-use seat OTPs for private kitty parties, family reunions, and corporate galas to ensure only invited guests can join.',
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
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.videogame_asset_outlined, color: AppTheme.secondaryColor, size: 20),
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
                      'Real multiplayer screens • Automated calling • Server-side claim verification',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFA0AEC0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Tab Selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _slides.length; i++) ...[
                  InkWell(
                    onTap: () => _onUserSelect(i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          fontSize: 12.5,
                          fontWeight: i == _selectedIndex ? FontWeight.w800 : FontWeight.w500,
                          color: i == _selectedIndex ? Colors.white : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                  if (i < _slides.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
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
