import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../constants/app_assets.dart';

/// Reusable widget to display company logos by domain using the Logo.dev CDN,
/// with automatic whitespace/transparent border trimming so padded logos fill their container.
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
  /// Defaults to at least 256px CDN resolution so cropped/scaled logos stay crisp.
  static String buildLogoUrl({
    required String domain,
    String? token,
    double size = 256.0,
    String format = 'png',
  }) {
    final clean = cleanDomain(domain);
    if (clean.isEmpty) return '';
    final key = (token != null && token.isNotEmpty)
        ? token
        : AppConfig.logoDevPublishableKey;
    final clampedSize = math.max(size, 256.0).clamp(64.0, 800.0).toInt();
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
      size: math.max(size * 4, 256.0),
      format: format,
    );

    final imageWidget = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(size * 0.15),
      child: SizedBox(
        width: size,
        height: size,
        child: AutoTrimmedNetworkLogo(
          imageUrl: logoUrl,
          fit: fit,
          fallback: fallback,
        ),
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

/// Loads a network logo image and automatically crops surrounding transparent or
/// near-white padding so that padded corporate logos fill their badge cleanly.
class AutoTrimmedNetworkLogo extends StatefulWidget {
  final String imageUrl;
  final String? fallbackUrl;
  final BoxFit fit;
  final Widget fallback;

  const AutoTrimmedNetworkLogo({
    super.key,
    required this.imageUrl,
    this.fallbackUrl,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  @override
  State<AutoTrimmedNetworkLogo> createState() => _AutoTrimmedNetworkLogoState();
}

class _AutoTrimmedNetworkLogoState extends State<AutoTrimmedNetworkLogo> {
  static final Map<String, Rect> _cropCache = {};

  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  ui.Image? _resolvedImage;
  Rect? _cropRect;
  bool _hasError = false;
  bool _triedFallbackUrl = false;

  String get _effectiveUrl {
    final raw = (_triedFallbackUrl && widget.fallbackUrl != null)
        ? widget.fallbackUrl!
        : widget.imageUrl;
    // Upgrade small Logo.dev size params so cropped emblem remains sharp
    if (raw.contains('img.logo.dev')) {
      return raw.replaceAll(RegExp(r'size=\d+'), 'size=256');
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant AutoTrimmedNetworkLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.fallbackUrl != widget.fallbackUrl) {
      _triedFallbackUrl = false;
      _hasError = false;
      _resolvedImage = null;
      _cropRect = null;
      _resolveImage();
    }
  }

  void _unsubscribe() {
    if (_imageStream != null && _listener != null) {
      _imageStream!.removeListener(_listener!);
    }
    _imageStream = null;
    _listener = null;
  }

  void _resolveImage() {
    _unsubscribe();
    final url = _effectiveUrl.trim();
    if (url.isEmpty) {
      setState(() => _hasError = true);
      return;
    }

    final provider = NetworkImage(url);
    final stream = provider.resolve(ImageConfiguration.empty);
    _imageStream = stream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        _onImageLoaded(url, info.image);
      },
      onError: (Object exception, StackTrace? stackTrace) {
        if (!_triedFallbackUrl && widget.fallbackUrl != null && widget.fallbackUrl!.isNotEmpty) {
          _triedFallbackUrl = true;
          _resolveImage();
        } else if (mounted) {
          setState(() => _hasError = true);
        }
      },
    );
    stream.addListener(_listener!);
  }

  Future<void> _onImageLoaded(String url, ui.Image image) async {
    if (!mounted) return;
    if (_cropCache.containsKey(url)) {
      setState(() {
        _resolvedImage = image;
        _cropRect = _cropCache[url];
        _hasError = false;
      });
      return;
    }

    Rect computedRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        final w = image.width;
        final h = image.height;
        int minX = w, minY = h, maxX = -1, maxY = -1;

        for (int y = 0; y < h; y++) {
          final rowOffset = y * w * 4;
          for (int x = 0; x < w; x++) {
            final idx = rowOffset + (x * 4);
            final r = bytes[idx];
            final g = bytes[idx + 1];
            final b = bytes[idx + 2];
            final a = bytes[idx + 3];
            if (a < 25) continue;
            if (r > 242 && g > 242 && b > 242) continue;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }

        if (maxX >= minX && maxY >= minY) {
          final contentW = maxX - minX + 1;
          final contentH = maxY - minY + 1;
          final pad = math.max(2, (math.max(contentW, contentH) * 0.06).round());
          final left = math.max(0, minX - pad).toDouble();
          final top = math.max(0, minY - pad).toDouble();
          final right = math.min(w, maxX + 1 + pad).toDouble();
          final bottom = math.min(h, maxY + 1 + pad).toDouble();
          if (right > left && bottom > top) {
            computedRect = Rect.fromLTRB(left, top, right, bottom);
          }
        }
      }
    } catch (_) {
      // Fallback to full image rect if pixel access is restricted
    }

    _cropCache[url] = computedRect;
    if (mounted) {
      setState(() {
        _resolvedImage = image;
        _cropRect = computedRect;
        _hasError = false;
      });
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback;
    }
    if (_resolvedImage != null && _cropRect != null) {
      return CustomPaint(
        painter: _CroppedLogoPainter(
          image: _resolvedImage!,
          srcRect: _cropRect!,
          fit: widget.fit,
        ),
      );
    }
    return Image.network(
      _effectiveUrl,
      fit: widget.fit,
      errorBuilder: (_, _, _) => widget.fallback,
    );
  }
}

class _CroppedLogoPainter extends CustomPainter {
  final ui.Image image;
  final Rect srcRect;
  final BoxFit fit;

  _CroppedLogoPainter({
    required this.image,
    required this.srcRect,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || srcRect.isEmpty) return;
    final fitted = applyBoxFit(fit, srcRect.size, size);
    final dstRect = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(covariant _CroppedLogoPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.srcRect != srcRect ||
        oldDelegate.fit != fit;
  }
}

