import 'package:flutter/material.dart';

class AppTheme {
  // DebHousie Brand Identity ("Party Mode" Palette)
  static const Color primaryColor = Color(0xFF0B3D91);     // Navy Blue (Structural chrome)
  static const Color primaryDark = Color(0xFF072A66);      // Deep Navy
  static const Color primaryLight = Color(0xFF1B54B8);     // Lighter Navy

  static const Color secondaryColor = Color(0xFFFFC107);   // Golden Yellow (Primary Action CTA fill)
  static const Color secondaryDark = Color(0xFFE0A800);    // Darker Gold

  static const Color accentSuccess = Color(0xFF2ECC71);    // Brand Green (Game Ball / Success)
  static const Color accentDanger = Color(0xFFE63946);     // Brand Red (Game Ball / Error)
  static const Color accentPartyPurple = Color(0xFF8E44AD);// Brand Purple (Game Ball / Rotating Accent)
  static const Color accentWarning = Color(0xFFF59E0B);
  static const Color accentInfo = Color(0xFF3B82F6);

  static const Color darkBackground = Color(0xFF0F111A);
  static const Color darkCard = Color(0xFF1B1E2E);
  static const Color darkSurface = Color(0xFF262A3F);

  static const Color lightBackground = Color(0xFFF8F9FD);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFECEFF8);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: secondaryColor,
        onSecondary: primaryColor,
        surface: darkCard,
        onSurface: Colors.white,
        error: accentDanger,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF2A2E44), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryColor,
          foregroundColor: primaryDark,
          elevation: 3,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: primaryLight, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2E334D), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: secondaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFFA0AEC0)),
        hintStyle: const TextStyle(color: Color(0xFF718096)),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE2E8F0)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
      ),
    );
  }
}
