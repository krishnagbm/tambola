import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static late final String supabaseUrl;
  static late final String supabaseAnonKey;
  static late final String appBaseUrl;
  static late final String supportEmail;
  static late final String purchaseBaseUrl;
  static late final bool purchaseEnabled;
  static late final String environment;
  static late final bool enableMockCredits;

  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {
      // Local development may use .env, while hosted/CI builds use dart-define.
    }

    supabaseUrl = _value('SUPABASE_URL', 'https://placeholder.supabase.co');
    supabaseAnonKey = _value('SUPABASE_ANON_KEY', 'placeholder-key');
    appBaseUrl = _value('APP_BASE_URL', 'https://www.dabhousie.com');
    supportEmail = _value('SUPPORT_EMAIL', 'contact@dabhousie.com');
    purchaseBaseUrl = _value(
      'PURCHASE_BASE_URL',
      'https://www.dabhousie.com/#/wallet',
    );
    purchaseEnabled =
        _value('PURCHASE_ENABLED', 'true').toLowerCase() == 'true';
    environment = _value('APP_ENVIRONMENT', 'development');
    enableMockCredits =
        _value('ENABLE_MOCK_CREDITS', 'true').toLowerCase() == 'true';
  }

  static String _value(String name, String fallback) {
    final value = switch (name) {
      'SUPABASE_URL' => const String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY' => const String.fromEnvironment('SUPABASE_ANON_KEY'),
      'APP_BASE_URL' => const String.fromEnvironment('APP_BASE_URL'),
      'SUPPORT_EMAIL' => const String.fromEnvironment('SUPPORT_EMAIL'),
      'PURCHASE_BASE_URL' => const String.fromEnvironment('PURCHASE_BASE_URL'),
      'PURCHASE_ENABLED' => const String.fromEnvironment('PURCHASE_ENABLED'),
      'APP_ENVIRONMENT' => const String.fromEnvironment('APP_ENVIRONMENT'),
      'ENABLE_MOCK_CREDITS' => const String.fromEnvironment(
        'ENABLE_MOCK_CREDITS',
      ),
      _ => '',
    };
    if (value.isNotEmpty) return value;
    if (dotenv.isInitialized) {
      return dotenv.env[name] ?? fallback;
    }
    return fallback;
  }

  static bool get isProduction => environment.toLowerCase() == 'production';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      supabaseUrl != 'https://placeholder.supabase.co' &&
      supabaseAnonKey != 'placeholder-key';
}
