import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tambola/core/config/app_config.dart';
import 'package:tambola/core/widgets/company_logo.dart';

void main() {
  group('CompanyLogo Unit Tests', () {
    test('cleanDomain handles emails, URLs, protocol prefixes and whitespace', () {
      expect(CompanyLogo.cleanDomain('stripe.com'), 'stripe.com');
      expect(CompanyLogo.cleanDomain('https://www.google.com/search?q=test'), 'google.com');
      expect(CompanyLogo.cleanDomain('http://github.com/orgs'), 'github.com');
      expect(CompanyLogo.cleanDomain('admin@microsoft.com'), 'microsoft.com');
      expect(CompanyLogo.cleanDomain('  WWW.AMAZON.COM  '), 'amazon.com');
      expect(CompanyLogo.cleanDomain('https://sub.domain.com/path/to/page'), 'sub.domain.com');
      expect(CompanyLogo.cleanDomain(''), '');
      expect(CompanyLogo.cleanDomain('   '), '');
    });

    test('buildLogoUrl constructs correct Logo.dev CDN URL with query parameters', () {
      final url = CompanyLogo.buildLogoUrl(
        domain: 'https://www.apple.com/iphone',
        token: 'pk_test_123',
        size: 256,
        format: 'png',
      );
      expect(url, 'https://img.logo.dev/apple.com?format=png&size=256&token=pk_test_123');

      // Test size clamping (min 16, max 800)
      final urlSmall = CompanyLogo.buildLogoUrl(
        domain: 'apple.com',
        token: 'pk_test_123',
        size: 5,
      );
      expect(urlSmall, contains('&size=16'));

      final urlLarge = CompanyLogo.buildLogoUrl(
        domain: 'apple.com',
        token: 'pk_test_123',
        size: 1200,
      );
      expect(urlLarge, contains('&size=800'));

      // Empty domain returns empty URL
      expect(CompanyLogo.buildLogoUrl(domain: ''), '');
    });

    test('buildLogoUrl falls back to AppConfig.logoDevPublishableKey if token omitted', () {
      AppConfig.logoDevPublishableKey = 'pk_config_key';
      final url = CompanyLogo.buildLogoUrl(domain: 'github.com');
      expect(url, contains('&token=pk_config_key'));

      AppConfig.logoDevPublishableKey = '';
      final urlNoKey = CompanyLogo.buildLogoUrl(domain: 'github.com');
      expect(urlNoKey.contains('&token='), isFalse);
    });

    test('CompanyLogo widget defaults and cleanDomain integration', () {
      const widget = CompanyLogo(
        domain: 'https://www.stripe.com/about',
        size: 64,
        isCommercialUse: true,
      );

      expect(widget.domain, 'https://www.stripe.com/about');
      expect(widget.size, 64);
      expect(widget.isCommercialUse, isTrue);
      expect(widget.format, 'png');
      expect(widget.fit, BoxFit.contain);
      expect(CompanyLogo.cleanDomain(widget.domain), 'stripe.com');
    });

    testWidgets('CompanyLogo renders fallback widget when domain is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompanyLogo(
              domain: '',
              size: 48,
              isCommercialUse: false,
              fallbackWidget: KeyedSubtree(
                key: Key('fallback_icon'),
                child: Icon(Icons.business),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('fallback_icon')), findsOneWidget);
    });
  });
}
