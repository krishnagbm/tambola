import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

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
}
