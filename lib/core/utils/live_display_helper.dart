import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';

class LiveDisplayHelper {
  /// Resolves the absolute URL for the Live Display screen
  static String getLiveDisplayUrl(String gameId) {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/#/live-display/$gameId';
    }
    return '${AppConfig.appBaseUrl}/#/live-display/$gameId';
  }

  /// Opens the Live Projector Display in a new window/tab on Web, or external browser on mobile
  static Future<void> openInNewWindow(BuildContext context, String gameId) async {
    final liveUrl = getLiveDisplayUrl(gameId);
    final uri = Uri.parse(liveUrl);

    if (kIsWeb) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_blank');
        return;
      }
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        context.push('/live-display/$gameId');
      }
    }
  }

  /// Shows the comprehensive "Display Game on TV / Projector" modal dialog
  static void showDisplayOnTvDialog(BuildContext context, String gameId) {
    final liveUrl = getLiveDisplayUrl(gameId);
    final adminUrl = kIsWeb
        ? '${Uri.base.origin}/#/admin-lobby/$gameId'
        : '${AppConfig.appBaseUrl}/#/admin-lobby/$gameId';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.tv, color: AppTheme.secondaryColor, size: 26),
            SizedBox(width: 10),
            Text(
              'Display Game on TV / Projector',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Open the Live Display on a second screen. The TV display runs independently from the organizer\'s device — no YouTube Live or video streaming is required.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1), height: 1.45),
                ),
                const SizedBox(height: 12),

                // Primary Product Message Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, color: AppTheme.secondaryColor, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your TV does not need to mirror the organizer\'s phone. Simply open the DabHousie Live Display URL on the TV.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Dual-Screen Independent Roles
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14192B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Independent Two-Screen Setup:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFA0AEC0),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildScreenRole(
                        icon: Icons.phone_android,
                        role: 'Organizer Device',
                        desc: 'Controls game numbers, tickets & claims',
                        url: adminUrl,
                      ),
                      const SizedBox(height: 6),
                      _buildScreenRole(
                        icon: Icons.tv,
                        role: 'TV / Projector Display',
                        desc: 'Read-only real-time board for audience & players',
                        url: liveUrl,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // QR Code & Direct Link Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E334D)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: liveUrl,
                          version: QrVersions.auto,
                          size: 130.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Scan QR with Phone or Smart TV Remote',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFA0AEC0),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F36),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2E334D)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                liveUrl,
                                style: const TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                              tooltip: 'Copy Live Display Link',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: liveUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Live Display URL copied to clipboard! 📋'),
                                    backgroundColor: AppTheme.accentSuccess,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          openInNewWindow(context, gameId);
                        },
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open Live Display in New Tab'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondaryColor,
                          foregroundColor: AppTheme.primaryDark,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Method 1: Smart TV Browser (Primary / Recommended)
                _buildDisplayOption(
                  icon: Icons.tv,
                  isRecommended: true,
                  title: '1. Smart TV Browser (Recommended)',
                  description:
                      'Open the built-in web browser on your Smart TV (if your TV/device has a supported web browser) and enter the Live Display Link. The TV will display the game independently while the organizer continues controlling the game from their phone or computer.',
                ),
                const SizedBox(height: 10),

                // Method 2: HDMI / Dual Monitor
                _buildDisplayOption(
                  icon: Icons.monitor,
                  isRecommended: false,
                  title: '2. HDMI / Secondary Monitor Projection',
                  description:
                      'Connect your laptop or PC to the TV or projector with an HDMI cable, move the Live Display tab to the secondary screen, and press F11 for edge-to-edge fullscreen presentation.',
                ),
                const SizedBox(height: 10),

                // Method 3: AirPlay / Chromecast
                _buildDisplayOption(
                  icon: Icons.cast,
                  isRecommended: false,
                  title: '3. Apple AirPlay / Google Cast (Optional)',
                  description:
                      'You can cast or mirror this tab to an AirPlay 2-compatible TV, Apple TV, or Chromecast. (Note: Opening the Live Display directly on the TV browser is recommended so the organizer\'s phone remains free to run the game).',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  static Widget _buildScreenRole({
    required IconData icon,
    required String role,
    required String desc,
    required String url,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.secondaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1)),
              ),
              Text(
                url,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildDisplayOption({
    required IconData icon,
    required bool isRecommended,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isRecommended
                ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                : const Color(0xFF2E334D).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: isRecommended
                ? Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.6))
                : null,
          ),
          child: Icon(
            icon,
            color: isRecommended ? AppTheme.secondaryColor : const Color(0xFFA0AEC0),
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: isRecommended ? AppTheme.secondaryColor : Colors.white,
                      ),
                    ),
                  ),
                  if (isRecommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSuccess.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.accentSuccess.withValues(alpha: 0.6)),
                      ),
                      child: const Text(
                        'PRIMARY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentSuccess,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
