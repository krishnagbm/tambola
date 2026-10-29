import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

class DashboardFooter extends StatelessWidget {
  const DashboardFooter({super.key});

  Future<void> _launchURL(String url, {bool isExternal = false}) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: isExternal ? LaunchMode.externalApplication : LaunchMode.platformDefault,
        webOnlyWindowName: isExternal ? '_blank' : '_self',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              'Play • Connect • Win',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/how-it-works.html'),
                  child: const Text(
                    'How It Works',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/videos.html'),
                  child: const Text(
                    'Videos',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF43F5E),
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFF43F5E),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/recent-games.html'),
                  child: const Text(
                    'Recent Games',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/brand-partners.html'),
                  child: const Text(
                    'Brand Partners',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFBBF24),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFFBBF24),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/how-to-play-tambola.html'),
                  child: const Text(
                    'Tambola Guide',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/how-to-play-housie.html'),
                  child: const Text(
                    'Housie Guide',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/90-ball-bingo.html'),
                  child: const Text(
                    '90-Ball Bingo Guide',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/skill-games-guide.html'),
                  child: const Text(
                    'Skill Games Guide',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF34D399),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF34D399),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/pricing.html'),
                  child: const Text(
                    'Pricing',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/terms-conditions.html'),
                  child: const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/privacy-policy.html'),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBD5E1),
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Official Social Channels Bar
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildSocialChip(
                  label: 'LinkedIn',
                  icon: Icons.business_center,
                  brandColor: const Color(0xFF0A66C2),
                  url: 'https://www.linkedin.com/company/dabhousie/',
                ),
                _buildSocialChip(
                  label: 'YouTube',
                  icon: Icons.play_circle_fill,
                  brandColor: const Color(0xFFFF0000),
                  url: 'https://www.youtube.com/@DabHousie',
                ),
                _buildSocialChip(
                  label: 'Facebook',
                  icon: Icons.facebook,
                  brandColor: const Color(0xFF1877F2),
                  url: 'https://www.facebook.com/dabhousie',
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _launchURL('${AppConfig.appBaseUrl}/terms-conditions.html#intellectual-property'),
              child: const Column(
                children: [
                  Text(
                    '© 2026 DabHousie™ by Digital App Studio. All rights reserved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA0AEC0),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'MakeHousie™, FixHousie™, MathHousie™, SumHousie™, FlashHousie™, RowHousie™, FastTap™, SwapHousie™, BlastHousie™, StickHousie™ & NeuroWave™ Column Spotlight are proprietary game formats, copyrighted visual expressions, and trademarks of Digital App Studio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialChip({
    required String label,
    required IconData icon,
    required Color brandColor,
    required String url,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _launchURL(url, isExternal: true),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: brandColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
