import 'package:flutter/material.dart';

class DeepGuardColors {
  // Core palette
  static const Color primary = Color(0xFF00D4FF);
  static const Color primaryDark = Color(0xFF0099CC);
  static const Color secondary = Color(0xFF7B2FF7);
  static const Color accent = Color(0xFFFF2D95);

  // Background
  static const Color background = Color(0xFF0A0E27);
  static const Color surfaceDark = Color(0xFF111537);
  static const Color surfaceCard = Color(0xFF1A1F4E);
  static const Color surfaceLight = Color(0xFF24296E);

  // Text
  static const Color textPrimary = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8892B0);
  static const Color textMuted = Color(0xFF565F89);

  // Status
  static const Color authentic = Color(0xFF00E676);
  static const Color fake = Color(0xFFFF1744);
  static const Color warning = Color(0xFFFFAB00);
  static const Color info = Color(0xFF448AFF);

  // Glass
  static const Color glassLight = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x4DFFFFFF);
  static Color glassBg = const Color(0x14FFFFFF);

  // Gradients
  static const List<Color> primaryGradient = [primary, secondary];
  static const List<Color> dangerGradient = [accent, Color(0xFFFF6B35)];
  static const List<Color> successGradient = [Color(0xFF00E676), Color(0xFF00BFA5)];
  static const List<Color> backgroundGradient = [Color(0xFF0A0E27), Color(0xFF0D1635), Color(0xFF0A0E27)];
  static const List<Color> cardGradient = [Color(0xFF1A1F4E), Color(0xFF111537)];
}

class DeepGuardTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DeepGuardColors.background,
      primaryColor: DeepGuardColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: DeepGuardColors.primary,
        secondary: DeepGuardColors.secondary,
        surface: DeepGuardColors.surfaceDark,
        error: DeepGuardColors.fake,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
        iconTheme: IconThemeData(color: DeepGuardColors.primary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DeepGuardColors.surfaceDark,
        selectedItemColor: DeepGuardColors.primary,
        unselectedItemColor: DeepGuardColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        headlineMedium: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: TextStyle(
          color: DeepGuardColors.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyLarge: TextStyle(
          color: DeepGuardColors.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: DeepGuardColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: DeepGuardColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}