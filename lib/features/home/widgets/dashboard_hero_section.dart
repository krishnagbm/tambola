import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'corporate_inquiry_dialog.dart';

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
                  '🎉 Multiplayer Tambola, Housie & 90-Ball Bingo — Family, Kitty Parties & Events',
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
                'Multiplayer Tambola, Housie & 90-Ball Bingo.\nAlways Free for Families, Built for Kitty Parties & Events.',
                style: TextStyle(
                  fontSize: isWide ? 24 : 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Subhead
              Text(
                'Host 100% Free Family games (1–5 players), weekly Kitty Parties (6–15), or scale to 250+ corporate events with instant digital tickets and automated server win verification.',
                style: TextStyle(
                  fontSize: isWide ? 13.5 : 12.5,
                  color: const Color(0xFFCBD5E1),
                  height: 1.38,
                ),
              ),
              const SizedBox(height: 14),

              // CTAs: Responsive 3-button layout
              if (isWide) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/create-game'),
                        icon: const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 16)),
                        label: const Text('Free Family Play (0 Credits)', overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSuccess,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/create-game'),
                        icon: const Text('🎟️', style: TextStyle(fontSize: 15)),
                        label: const Text('Host Party / Event', overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/join'),
                        icon: const Text('🔑', style: TextStyle(fontSize: 15)),
                        label: const Text('Join Game', overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/create-game'),
                        icon: const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 16)),
                        label: const Text('Free Family Play (1–5 Players · 0 Credits)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentSuccess,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/create-game'),
                            icon: const Text('🎟️', style: TextStyle(fontSize: 15)),
                            label: const Text('Host Party (6–250+)', overflow: TextOverflow.ellipsis),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryLight,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.push('/join'),
                            icon: const Text('🔑', style: TextStyle(fontSize: 15)),
                            label: const Text('Join Game', overflow: TextOverflow.ellipsis),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),

              // Corporate & Mega-X Callout Button
              InkWell(
                onTap: () => CorporateInquiryDialog.show(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.business_center_rounded, color: AppTheme.secondaryColor, size: 15),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Planning 250 to 100K+ Guests or Custom Rules? Contact for Enterprise Pricing →',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Trust Strip
              const Divider(color: Color(0xFF2E334D), height: 1),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: const [
                  Text('👨‍👩‍👧‍👦 Family Pack always free (1–5)', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('💃 Instant for Kitty Parties', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('✅ 100K+ Unique tickets (8.1T space)', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🏢 250+ to 100K enterprise scale', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🔒 Auto server claims', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                  Text('·', style: TextStyle(fontSize: 10.5, color: Color(0xFF718096))),
                  Text('🙅 Zero app download for guests', style: TextStyle(fontSize: 10.5, color: Color(0xFFA0AEC0))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
