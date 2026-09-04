import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static late final String supabaseUrl;
  static late final String supabaseAnonKey;
  static late final String purchaseBaseUrl;
  static late final bool purchaseEnabled;
  static late final String environment;

  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {
      // Fallback if .env is missing in certain build environments
    }

    supabaseUrl = const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    ).isNotEmpty
        ? const String.fromEnvironment('SUPABASE_URL')
        : (dotenv.env['SUPABASE_URL'] ?? 'https://placeholder.supabase.co');

    supabaseAnonKey = const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    ).isNotEmpty
        ? const String.fromEnvironment('SUPABASE_ANON_KEY')
        : (dotenv.env['SUPABASE_ANON_KEY'] ?? 'placeholder-key');

    purchaseBaseUrl = const String.fromEnvironment(
      'PURCHASE_BASE_URL',
      defaultValue: '',
    ).isNotEmpty
        ? const String.fromEnvironment('PURCHASE_BASE_URL')
        : (dotenv.env['PURCHASE_BASE_URL'] ?? 'https://digitalappstudio.com/tambola/buy-credits');

    purchaseEnabled = (dotenv.env['PURCHASE_ENABLED'] ?? 'true').toLowerCase() == 'true';
    environment = dotenv.env['APP_ENVIRONMENT'] ?? 'development';
    enableMockCredits = (dotenv.env['ENABLE_MOCK_CREDITS'] ?? (environment.toLowerCase() != 'production' ? 'true' : 'false')).toLowerCase() == 'true';
  }

  static bool get isProduction => environment.toLowerCase() == 'production';

  static late final bool enableMockCredits;

  static bool get isConfigured =>
      supabaseUrl != 'https://placeholder.supabase.co' &&
      supabaseAnonKey != 'placeholder-key' &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;
}
