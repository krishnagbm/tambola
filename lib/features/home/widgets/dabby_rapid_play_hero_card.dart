import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_theme.dart';

// Conditionally import dart:js_interop or stub for web js call
import 'package:tambola/core/utils/web_js_helper.dart'
    if (dart.library.html) 'package:tambola/core/utils/web_js_helper_web.dart';

/// Compact Hero Card showcasing Dabby the Mascot with a Play with Dabby button.
/// Clicking launches the authentic HTML5 90-Ball Bingo popup modal seamlessly on Web,
/// or opens the standalone dedicated play page on non-web platforms.
class DabbyRapidPlayHeroCard extends StatelessWidget {
  const DabbyRapidPlayHeroCard({super.key});

  void _openPlayExperience(BuildContext context) {
    if (kIsWeb) {
      final handled = WebJsHelper.openDabbyModal();
      if (!handled) {
        launchUrl(
          Uri.parse('${AppConfig.appBaseUrl}/play-with-dabby.html'),
          webOnlyWindowName: '_blank',
        );
      }
    } else {
      launchUrl(
        Uri.parse('${AppConfig.appBaseUrl}/play-with-dabby.html'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 650;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
          width: 1.5,
        ),
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [
            const Color(0xFFF59E0B).withValues(alpha: 0.12),
            AppTheme.primaryColor.withValues(alpha: 0.22),
            AppTheme.darkCard,
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Full-Width Hero Banner (exact 3:1 ratio, 2400x800 native with clean alpha transparency)
          AspectRatio(
            aspectRatio: 3.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              alignment: Alignment.center,
              child: Image.asset(
                AppAssets.dabbyHorizontalBanner,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                alignment: Alignment.center,
                errorBuilder: (ctx, err, stack) => Image.asset(
                  AppAssets.dabbyShowcaseBanner,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),

          // 2. Warm Up with Dabby Bar below the Hero Banner
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 18 : 14,
              vertical: isWide ? 14 : 12,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            child: isWide
                ? Row(
                    children: [
                      // Badge & Icon
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          '⚡ 90-BALL BINGO RAPID PLAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFCD34D),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Play with Dabby • Free Solo Practice',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Instant 15-number rapid solo game with Dabby the mascot — practice speed & dabbing on authentic 3×9 tickets, 100% free!',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        onPressed: () => _openPlayExperience(context),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play with Dabby Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 3,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              '⚡ 90-BALL BINGO RAPID PLAY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFFCD34D),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: () => _openPlayExperience(context),
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: const Text('Play Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: const Color(0xFF0F172A),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Play with Dabby • Free Solo Practice',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Instant 15-number rapid solo game with Dabby the mascot — practice speed & dabbing on authentic 3×9 tickets, 100% free!',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
