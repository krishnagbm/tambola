import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../constants/app_assets.dart';

/// Reusable widget to display company logos by domain using the Logo.dev CDN.
///
/// Canonical reference: https://www.logo.dev/docs
/// Features:
/// - Client-side auth using publishable key from [AppConfig.logoDevPublishableKey].
/// - Configurable [size] (clamped to max 800) and [format].
/// - Safe domain sanitization (strips `https://`, `http://`, `www.`, and trailing paths).
/// - Free-tier attribution link ('Powered by Logo.dev') launching https://logo.dev.
/// - Robust fallback (e.g. monogram or custom fallback) if image fails or domain is empty.
class CompanyLogo extends StatelessWidget {
  final String domain;
  final double size;
  final String format;
  final bool isCommercialUse;
  final Widget? fallbackWidget;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const CompanyLogo({
    super.key,
    required this.domain,
    this.size = 128.0,
    this.format = 'png',
    this.isCommercialUse = true, // Free tier commercial usage requires attribution
    this.fallbackWidget,
    this.borderRadius,
    this.fit = BoxFit.contain,
  });

  /// Sanitizes a raw input string (which may be a URL, email, or domain) into a clean domain.
  static String cleanDomain(String input) {
    if (input.isEmpty) return '';
    try {
      var d = input.trim();
      if (d.contains('@')) {
        final parts = d.split('@');
        if (parts.length == 2) d = parts[1];
      }
      if (d.startsWith('http://') || d.startsWith('https://')) {
        final uri = Uri.tryParse(d);
        if (uri != null && uri.host.isNotEmpty) {
          d = uri.host;
        }
      }
      return d.toLowerCase().replaceFirst(RegExp(r'^www\.'), '').split('/')[0].trim();
    } catch (_) {
      return '';
    }
  }

  /// Builds a Logo.dev image CDN URL for a given domain and publishable key.
  static String buildLogoUrl({
    required String domain,
    String? token,
    double size = 128.0,
    String format = 'png',
  }) {
    final clean = cleanDomain(domain);
    if (clean.isEmpty) return '';
    final key = (token != null && token.isNotEmpty)
        ? token
        : AppConfig.logoDevPublishableKey;
    final clampedSize = size.clamp(16.0, 800.0).toInt();
    final tokenParam = key.isNotEmpty ? '&token=$key' : '';
    return 'https://img.logo.dev/$clean?format=$format&size=$clampedSize$tokenParam';
  }

  Future<void> _openAttribution() async {
    final uri = Uri.parse('https://logo.dev');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sanitizedDomain = cleanDomain(domain);
    final fallback = fallbackWidget ??
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: borderRadius ?? BorderRadius.circular(size * 0.15),
          ),
          child: Image.asset(AppAssets.monogramDH, fit: fit),
        );

    if (sanitizedDomain.isEmpty) {
      return fallback;
    }

    final logoUrl = buildLogoUrl(
      domain: sanitizedDomain,
      size: size,
      format: format,
    );

    final imageWidget = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(size * 0.15),
      child: Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );

    if (!isCommercialUse) {
      return imageWidget;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        imageWidget,
        const SizedBox(height: 3),
        InkWell(
          onTap: _openAttribution,
          child: const Text(
            'Powered by Logo.dev',
            style: TextStyle(
              fontSize: 9.5,
              color: Color(0xFF94A3B8),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
