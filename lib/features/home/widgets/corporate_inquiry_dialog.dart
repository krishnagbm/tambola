import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class CorporateInquiryDialog extends StatelessWidget {
  final String initialTopic;

  const CorporateInquiryDialog({
    super.key,
    this.initialTopic = 'Mega-X Event (250+ Players)',
  });

  static void show(BuildContext context, {String initialTopic = 'Mega-X Event (250+ Players)'}) {
    showDialog(
      context: context,
      builder: (ctx) => CorporateInquiryDialog(initialTopic: initialTopic),
    );
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@pocketbull.net',
      query: 'subject=DebHousie Corporate & Mega-X Event Inquiry: $initialTopic&body=Hi DebHousie Team,%0D%0A%0D%0AI am interested in organizing a large event with the following requirements:%0D%0A- Event Type: $initialTopic%0D%0A- Expected Player Count: %0D%0A- Event Date: %0D%0A- Custom Requirements / Winning Patterns: %0D%0A%0D%0AThanks!',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          _copyEmailToClipboard(context);
        }
      }
    } catch (_) {
      if (context.mounted) {
        _copyEmailToClipboard(context);
      }
    }
  }

  void _copyEmailToClipboard(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: 'support@pocketbull.net'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied to clipboard (support@pocketbull.net)'),
        backgroundColor: AppTheme.accentSuccess,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.primaryLight, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Badge & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.business_center_rounded, color: AppTheme.secondaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mega-X & Corporate Solutions',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Custom Packages & Tailored Features',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFFA0AEC0)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Offerings List
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E334D)),
                ),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      icon: Icons.groups_rounded,
                      color: AppTheme.secondaryColor,
                      title: 'Mega-X Scale (250 to 100,000+ Players)',
                      desc: 'Engineered for massive enterprise concurrency with 8.1 Trillion unique combinations, stress-tested to 100,000+ tickets without collisions.',
                    ),
                    const Divider(color: Color(0xFF2E334D), height: 18),
                    _buildFeatureItem(
                      icon: Icons.auto_awesome_rounded,
                      color: AppTheme.accentSuccess,
                      title: 'Custom Winning Patterns',
                      desc: 'Star, Breakfast, King/Queen, or branded corporate game formats configured on demand.',
                    ),
                    const Divider(color: Color(0xFF2E334D), height: 18),
                    _buildFeatureItem(
                      icon: Icons.tv_rounded,
                      color: AppTheme.primaryLight,
                      title: 'Big-Screen Projector & TV Cast',
                      desc: 'Auditorium live-board displays, synchronized audio calls, and instant QR prize verification.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _launchEmail(context);
                },
                icon: const Icon(Icons.mail_outline_rounded, size: 18),
                label: const Text('Contact Us for Custom Pricing', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  _copyEmailToClipboard(context);
                },
                icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFFA0AEC0)),
                label: const Text('Copy Email: support@pocketbull.net', style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: const BorderSide(color: Color(0xFF2E334D)),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close', style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
