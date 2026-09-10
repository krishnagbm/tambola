import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';

class OpeningScreen extends StatefulWidget {
  const OpeningScreen({super.key});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen> with SingleTickerProviderStateMixin {
  int _activeDotIndex = 0;
  int _currentTipIndex = 0;
  Timer? _dotTimer;
  Timer? _tipTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _partyColors = [
    AppTheme.secondaryColor,      // Yellow
    AppTheme.accentDanger,        // Red
    AppTheme.accentSuccess,       // Green
    AppTheme.accentPartyPurple,   // Purple
  ];

  static const _tips = [
    'Every ticket is checked for uniqueness before you play.',
    'Host up to 250 players in a single live game.',
    'Server-verified wins — zero paper, zero cheating.',
    'No app download or account needed for your guests.',
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Pulse through 4 party dots every 350ms
    _dotTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (mounted) {
        setState(() {
          _activeDotIndex = (_activeDotIndex + 1) % _partyColors.length;
        });
      }
    });

    // Cycle helpful tips every 2.5s
    _tipTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
      if (mounted) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % _tips.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _tipTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Main Branded Logo
                Image.asset(
                  AppAssets.mainLogo,
                  height: 180,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 16),

                // Fade-in Tagline
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Text(
                    'Play • Connect • Win',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // 4-Dot Pulsing Party Animation
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_partyColors.length, (index) {
                    final isActive = index == _activeDotIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: isActive ? 14 : 9,
                      height: isActive ? 14 : 9,
                      decoration: BoxDecoration(
                        color: isActive ? _partyColors[index] : _partyColors[index].withOpacity(0.35),
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: _partyColors[index].withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // Cycling USP Tip Line
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    _tips[_currentTipIndex],
                    key: ValueKey<int>(_currentTipIndex),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.3,
                    ),
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
