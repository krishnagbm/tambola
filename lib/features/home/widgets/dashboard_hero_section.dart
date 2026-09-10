import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class DashboardHeroSection extends StatelessWidget {
  const DashboardHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryLight.withOpacity(0.35)),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [
            AppTheme.primaryColor.withOpacity(0.35),
            AppTheme.darkCard,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.secondaryColor.withOpacity(0.4)),
            ),
            child: const Text(
              '🎉 Multiplayer Tambola, Housie & Bingo — Live',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Headline
          const Text(
            'Real Tambola Nights.\nZero Fuss. Zero Cheating.',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          // Subhead
          const Text(
            'DebHousie brings your Tambola, Housie & Bingo party online — host up to 250 players, call numbers live, and let the server verify every win automatically. No paper tickets. No arguments. No app download for players.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFCBD5E1),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),

          // CTAs: Host a Game (Primary) & Join (Secondary)
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 480;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.push('/create-game'),
                        child: const Text('🎟️ Host a Game — Free'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/join'),
                        child: const Text('🔑 Have a Code? Join Now'),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: () => context.push('/create-game'),
                      child: const Text('🎟️ Host a Game — Free'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => context.push('/join'),
                      child: const Text('🔑 Have a Code? Join Now'),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 18),

          // Trust Strip
          const Divider(color: Color(0xFF2E334D), height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: const [
              Text('✅ 200/200 test tickets — zero duplicates', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
              Text('·', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
              Text('🔒 Server-verified wins', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
              Text('·', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
              Text('🙅 No sign-up to play', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
              Text('·', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
              Text('🌍 Free for players, everywhere', style: TextStyle(fontSize: 11, color: Color(0xFFA0AEC0))),
            ],
          ),
        ],
      ),
    );
  }
}
