import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class DashboardHeroSection extends StatelessWidget {
  const DashboardHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 600;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 22 : 16,
            vertical: isWide ? 20 : 16,
          ),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.35)),
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.4,
              colors: [
                AppTheme.primaryColor.withValues(alpha: 0.35),
                AppTheme.darkCard,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  '🎉 Multiplayer Tambola, Housie & Bingo — Live',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Headline
              Text(
                'Real Tambola Nights.\nZero Fuss. Zero Cheating.',
                style: TextStyle(
                  fontSize: isWide ? 26 : 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.18,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subhead
              Text(
                'Host up to 250 players online with automated server win verification. No paper tickets, no app download for guests.',
                style: TextStyle(
                  fontSize: isWide ? 13.5 : 12.5,
                  color: const Color(0xFFCBD5E1),
                  height: 1.38,
                ),
              ),
              const SizedBox(height: 14),

              // CTAs: Side-by-side or stacked cleanly
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.push('/create-game'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('🎟️ Host Free', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/join'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('🔑 Join Game', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Trust Strip
              const Divider(color: Color(0xFF2E334D), height: 1),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: const [
                  Text('✅ 0 duplicate tickets', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🔒 Auto server claims', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🙅 No sign-up for guests', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🌍 100% Free for players', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
