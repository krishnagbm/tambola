import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'corporate_inquiry_dialog.dart';

class DashboardHeroSection extends ConsumerWidget {
  const DashboardHeroSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              color: AppTheme.primaryLight.withValues(alpha: 0.35),
              width: 1.5,
            ),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // Eyebrow badges (Luck • Live Multiplayer • No Team Needed)
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
                          color: const Color(0xFF38BDF8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '🎲 LUCK • CLASSIC BINGO',
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
                          color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: const Text(
                          '🎉 Live Multiplayer',
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
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF38BDF8).withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        child: const Text(
                          '👤 No Team Needed',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7DD3FC),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Line 1: Tagline ("Play, Connect & Win")
              // Line 2: "Tambola, Housie & 90-Ball Bingo"
              SizedBox(
                height: isWide ? 29 : 24,
                child: Text(
                  'Play, Connect & Win',
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
                  'Tambola, Housie & 90-Ball Bingo',
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

              // Subhead (exact 38px 2-line slot on desktop, 54px 3-line slot on mobile)
              SizedBox(
                height: isWide ? 38 : 54,
                child: Text(
                  'Live multiplayer Tambola, Housie & 90-Ball Bingo for friends, family, parties, and events. Join instantly on the web — zero app download required.',
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
                  'Join as an individual, with friends, or bring your whole team — the more the merrier.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7DD3FC),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // CTAs: Join vs Host (exact 40px single row)
              SizedBox(
                height: 40,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => context.push('/join'),
                        icon: const Icon(Icons.vpn_key_rounded, size: 17),
                        label: const Text('Join a Game'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 16,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/create-game'),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Host a Game'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 16,
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
              const SizedBox(
                height: 16,
                child: Text(
                  'Free for up to 5 players • Paid hosting for larger groups',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Corporate & Mega-X Callout Button (exact 52px 2-line box)
              InkWell(
                onTap: () => CorporateInquiryDialog.show(context),
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
                      color: AppTheme.secondaryColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.business_center_rounded,
                        color: AppTheme.secondaryColor,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Planning 250 to 100K+ Guests or Custom Rules?\nContact for Enterprise Pricing →',
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
              _buildTrustStrip(isWide),
            ],
          ),
        );
  }

  Widget _buildTrustStrip(bool isWide) {
    const line1 = [
      '💃 Kitty Parties',
      '🛡️ Private Seat OTPs',
      '📺 Live Projector & TV Mode',
    ];
    const line2 = [
      '🔒 Auto server claims',
      '🙅 Zero app download',
      '✅ 100K+ Unique tickets',
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
