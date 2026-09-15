import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';

class DashboardFooter extends StatelessWidget {
  const DashboardFooter({super.key});

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _launchURL(AppConfig.appBaseUrl),
              child: const Text(
                'DabHousie by Digital App Studio',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFA0AEC0),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/privacy-policy.html'),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                ),
                InkWell(
                  onTap: () => _launchURL('${AppConfig.appBaseUrl}/terms-conditions.html'),
                  child: const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
