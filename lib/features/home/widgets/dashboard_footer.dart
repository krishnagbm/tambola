import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

class DashboardFooter extends StatelessWidget {
  const DashboardFooter({super.key});

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, webOnlyWindowName: '_self');
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
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _launchURL(AppConfig.appBaseUrl),
              child: const Text(
                '© 2026 DabHousie by Digital App Studio. All rights reserved.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFA0AEC0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
