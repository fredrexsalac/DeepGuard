import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// DeepGuard centralized semantic color tokens for Light Mode and Dark Mode.
///
/// Every text token is validated against WCAG 2.2 Level AA (>= 4.5:1 for normal
/// text, >= 3.0:1 for large text) across primary background, secondary
/// background, card surface, and elevated/tinted containers. Interactive
/// control borders and graphical status indicators clear >= 3.0:1 (SC 1.4.11).
@immutable
class DeepGuardPalette extends ThemeExtension<DeepGuardPalette> {
  final Brightness brightness;

  // Brand & Surfaces
  final Color brandNavy;
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceElevated;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Actions & Accents
  final Color primary;
  final Color primaryText;
  final Color primaryButton;
  final Color onPrimaryButton;
  final Color secondaryButton;
  final Color onSecondaryButton;
  final Color accent;
  final Color accentText;

  // Borders & Focus
  final Color border;
  final Color controlBorder;
  final Color focusIndicator;

  // Status & Classification (REAL / A.I.)
  final Color realClassification;
  final Color realText;
  final Color realContainer;

  final Color aiClassification;
  final Color aiText;
  final Color aiContainer;

  final Color success;
  final Color successText;
  final Color successContainer;

  final Color warning;
  final Color warningText;
  final Color warningContainer;

  final Color error;
  final Color errorText;
  final Color errorContainer;
  final Color dangerButton;
  final Color onDangerButton;

  final Color processingStatus;
  final Color processingText;
  final Color processingContainer;

  // Disabled
  final Color disabledControl;
  final Color disabledText;

  const DeepGuardPalette({
    required this.brightness,
    required this.brandNavy,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryText,
    required this.primaryButton,
    required this.onPrimaryButton,
    required this.secondaryButton,
    required this.onSecondaryButton,
    required this.accent,
    required this.accentText,
    required this.border,
    required this.controlBorder,
    required this.focusIndicator,
    required this.realClassification,
    required this.realText,
    required this.realContainer,
    required this.aiClassification,
    required this.aiText,
    required this.aiContainer,
    required this.success,
    required this.successText,
    required this.successContainer,
    required this.warning,
    required this.warningText,
    required this.warningContainer,
    required this.error,
    required this.errorText,
    required this.errorContainer,
    required this.dangerButton,
    required this.onDangerButton,
    required this.processingStatus,
    required this.processingText,
    required this.processingContainer,
    required this.disabledControl,
    required this.disabledText,
  });

  bool get isDark => brightness == Brightness.dark;

  List<Color> get allSurfaces => [
        backgroundPrimary,
        backgroundSecondary,
        surface,
        surfaceElevated,
      ];

  /// Light Mode semantic palette (Phase 3.1 validated for WCAG 2.2 Level AA).
  static const DeepGuardPalette light = DeepGuardPalette(
    brightness: Brightness.light,
    brandNavy: Color(0xFF101C36),
    backgroundPrimary: Color(0xFFFFFFFF),
    backgroundSecondary: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEAF0F8),
    textPrimary: Color(0xFF172033), // 16.01:1 on #FFFFFF, 14.78:1 on #F3F6FA
    textSecondary: Color(0xFF475569), // 7.58:1 on #FFFFFF, 7.00:1 on #F3F6FA
    textMuted: Color(0xFF596579), // 5.98:1 on #FFFFFF, 5.52:1 on #F3F6FA
    primary: Color(0xFF2457C5), // 6.47:1 on #FFFFFF, 5.97:1 on #F3F6FA
    primaryText: Color(0xFF1E4BB2), // 7.51:1 on #FFFFFF, 6.55:1 on #EAF0F8
    primaryButton: Color(0xFF2457C5),
    onPrimaryButton: Color(0xFFFFFFFF), // 6.47:1 on #2457C5
    secondaryButton: Color(0xFFEAF0F8),
    onSecondaryButton: Color(0xFF172033), // 14.08:1 on #EAF0F8
    accent: Color(0xFF089BB8), // 3.29:1 on #FFFFFF, 3.03:1 on #F3F6FA (non-text)
    accentText: Color(0xFF06748B), // 5.36:1 on #FFFFFF, 4.68:1 on #EAF0F8
    border: Color(0xFFDCE3EC), // decorative card divider
    controlBorder: Color(0xFF64748B), // 4.76:1 on #FFFFFF, 4.15:1 on #EAF0F8 (>= 3:1)
    focusIndicator: Color(0xFF2457C5), // 6.47:1 (>= 3:1)
    realClassification: Color(0xFF16865A), // 4.57:1 on #FFFFFF, 4.22:1 on #F3F6FA
    realText: Color(0xFF117A50), // 5.38:1 on #FFFFFF, 4.97:1 on #F3F6FA
    realContainer: Color(0xFFECF9F3),
    aiClassification: Color(0xFFD64B55), // 4.20:1 on #FFFFFF, 3.88:1 on #F3F6FA
    aiText: Color(0xFFB82E38), // 5.92:1 on #FFFFFF, 5.46:1 on #F3F6FA
    aiContainer: Color(0xFFFDF1F2),
    success: Color(0xFF16865A),
    successText: Color(0xFF117A50),
    successContainer: Color(0xFFECF9F3),
    warning: Color(0xFFC26A0A), // 3.96:1 on #FFFFFF (>= 3:1 graphic)
    warningText: Color(0xFF9A4D00), // 6.25:1 on #FFFFFF, 5.77:1 on #F3F6FA
    warningContainer: Color(0xFFFFF8EB),
    error: Color(0xFFD64B55),
    errorText: Color(0xFFB82E38),
    errorContainer: Color(0xFFFDF1F2),
    dangerButton: Color(0xFFB82E38),
    onDangerButton: Color(0xFFFFFFFF), // 5.92:1 on #B82E38
    processingStatus: Color(0xFF2457C5),
    processingText: Color(0xFF1E4BB2),
    processingContainer: Color(0xFFEBF2FC),
    disabledControl: Color(0xFFE2E8F0),
    disabledText: Color(0xFF64748B),
  );

  /// Dark Mode semantic palette (Phase 3.2 validated for WCAG 2.2 Level AA).
  static const DeepGuardPalette dark = DeepGuardPalette(
    brightness: Brightness.dark,
    brandNavy: Color(0xFF101C36),
    backgroundPrimary: Color(0xFF101827),
    backgroundSecondary: Color(0xFF172338),
    surface: Color(0xFF1B2A40),
    surfaceElevated: Color(0xFF22344F),
    textPrimary: Color(0xFFF4F7FC), // 13.33:1 on #1B2A40, 11.62:1 on #22344F
    textSecondary: Color(0xFFB8C5D8), // 8.11:1 on #1B2A40, 7.07:1 on #22344F
    textMuted: Color(0xFF9BB0C9), // 6.33:1 on #1B2A40, 5.51:1 on #22344F
    primary: Color(0xFF5988F5), // 5.15:1 on #101827, >= 3.7:1 graphic everywhere
    primaryText: Color(0xFF7FA6FB), // 6.08:1 on #1B2A40, 5.30:1 on #22344F
    primaryButton: Color(0xFF5988F5),
    onPrimaryButton: Color(0xFF0B1324), // 5.51:1 dark ink on #5988F5
    secondaryButton: Color(0xFF22344F),
    onSecondaryButton: Color(0xFFF4F7FC), // 11.62:1 on #22344F
    accent: Color(0xFF35C9E2), // 7.32:1 on #1B2A40
    accentText: Color(0xFF35C9E2), // 7.32:1 on #1B2A40, 6.38:1 on #22344F
    border: Color(0xFF34445B), // decorative card divider
    controlBorder: Color(0xFF69809E), // 3.55:1 on #1B2A40, 3.10:1 on #22344F (>= 3:1)
    focusIndicator: Color(0xFF35C9E2), // 7.32:1 (>= 3:1)
    realClassification: Color(0xFF16865A), // 3.13:1 on #1B2A40 (>= 3:1 graphic)
    realText: Color(0xFF36CA8D), // 7.28:1 on #1B2A40, 6.35:1 on #22344F
    realContainer: Color(0xFF132E2B),
    aiClassification: Color(0xFFD64B55), // 3.40:1 on #1B2A40 (>= 3:1 graphic)
    aiText: Color(0xFFF47881), // 5.31:1 on #1B2A40, 4.63:1 on #22344F
    aiContainer: Color(0xFF321C25),
    success: Color(0xFF24A872), // 4.78:1 on #1B2A40
    successText: Color(0xFF36CA8D),
    successContainer: Color(0xFF132E2B),
    warning: Color(0xFFF59E0B), // 6.80:1 on #1B2A40
    warningText: Color(0xFFFBBF24), // 8.52:1 on #1B2A40
    warningContainer: Color(0xFF302617),
    error: Color(0xFFD64B55),
    errorText: Color(0xFFF47881),
    errorContainer: Color(0xFF321C25),
    dangerButton: Color(0xFFF47881),
    onDangerButton: Color(0xFF0B1324), // 7.01:1 dark ink on #F47881
    processingStatus: Color(0xFF35C9E2),
    processingText: Color(0xFF56D4EA),
    processingContainer: Color(0xFF162B44),
    disabledControl: Color(0xFF253349),
    disabledText: Color(0xFF7B8EA8),
  );

  /// Resolves the active [DeepGuardPalette] from [context].
  static DeepGuardPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<DeepGuardPalette>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.light ? light : dark;
  }

  /// Returns a text-safe shade of [color] guaranteed to clear [floor] against
  /// every surface in this theme.
  Color textSafe(Color color, {double floor = 4.5}) {
    if (color == realClassification || color == success) return realText;
    if (color == aiClassification || color == error) return aiText;
    if (color == warning) return warningText;
    if (color == primary) return primaryText;
    if (color == accent) return accentText;
    return DeepGuardContrast.textSafeForSurfaces(
      color,
      surfaces: allSurfaces,
      targetText: textPrimary,
      floor: floor,
    );
  }

  @override
  DeepGuardPalette copyWith({
    Brightness? brightness,
    Color? brandNavy,
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? primaryText,
    Color? primaryButton,
    Color? onPrimaryButton,
    Color? secondaryButton,
    Color? onSecondaryButton,
    Color? accent,
    Color? accentText,
    Color? border,
    Color? controlBorder,
    Color? focusIndicator,
    Color? realClassification,
    Color? realText,
    Color? realContainer,
    Color? aiClassification,
    Color? aiText,
    Color? aiContainer,
    Color? success,
    Color? successText,
    Color? successContainer,
    Color? warning,
    Color? warningText,
    Color? warningContainer,
    Color? error,
    Color? errorText,
    Color? errorContainer,
    Color? dangerButton,
    Color? onDangerButton,
    Color? processingStatus,
    Color? processingText,
    Color? processingContainer,
    Color? disabledControl,
    Color? disabledText,
  }) {
    return DeepGuardPalette(
      brightness: brightness ?? this.brightness,
      brandNavy: brandNavy ?? this.brandNavy,
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primaryText: primaryText ?? this.primaryText,
      primaryButton: primaryButton ?? this.primaryButton,
      onPrimaryButton: onPrimaryButton ?? this.onPrimaryButton,
      secondaryButton: secondaryButton ?? this.secondaryButton,
      onSecondaryButton: onSecondaryButton ?? this.onSecondaryButton,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      border: border ?? this.border,
      controlBorder: controlBorder ?? this.controlBorder,
      focusIndicator: focusIndicator ?? this.focusIndicator,
      realClassification: realClassification ?? this.realClassification,
      realText: realText ?? this.realText,
      realContainer: realContainer ?? this.realContainer,
      aiClassification: aiClassification ?? this.aiClassification,
      aiText: aiText ?? this.aiText,
      aiContainer: aiContainer ?? this.aiContainer,
      success: success ?? this.success,
      successText: successText ?? this.successText,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningText: warningText ?? this.warningText,
      warningContainer: warningContainer ?? this.warningContainer,
      error: error ?? this.error,
      errorText: errorText ?? this.errorText,
      errorContainer: errorContainer ?? this.errorContainer,
      dangerButton: dangerButton ?? this.dangerButton,
      onDangerButton: onDangerButton ?? this.onDangerButton,
      processingStatus: processingStatus ?? this.processingStatus,
      processingText: processingText ?? this.processingText,
      processingContainer: processingContainer ?? this.processingContainer,
      disabledControl: disabledControl ?? this.disabledControl,
      disabledText: disabledText ?? this.disabledText,
    );
  }

  @override
  DeepGuardPalette lerp(ThemeExtension<DeepGuardPalette>? other, double t) {
    if (other is! DeepGuardPalette) return this;
    return DeepGuardPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      brandNavy: Color.lerp(brandNavy, other.brandNavy, t)!,
      backgroundPrimary:
          Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      backgroundSecondary:
          Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      primaryButton: Color.lerp(primaryButton, other.primaryButton, t)!,
      onPrimaryButton: Color.lerp(onPrimaryButton, other.onPrimaryButton, t)!,
      secondaryButton: Color.lerp(secondaryButton, other.secondaryButton, t)!,
      onSecondaryButton:
          Color.lerp(onSecondaryButton, other.onSecondaryButton, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      border: Color.lerp(border, other.border, t)!,
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
      focusIndicator: Color.lerp(focusIndicator, other.focusIndicator, t)!,
      realClassification:
          Color.lerp(realClassification, other.realClassification, t)!,
      realText: Color.lerp(realText, other.realText, t)!,
      realContainer: Color.lerp(realContainer, other.realContainer, t)!,
      aiClassification:
          Color.lerp(aiClassification, other.aiClassification, t)!,
      aiText: Color.lerp(aiText, other.aiText, t)!,
      aiContainer: Color.lerp(aiContainer, other.aiContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      dangerButton: Color.lerp(dangerButton, other.dangerButton, t)!,
      onDangerButton: Color.lerp(onDangerButton, other.onDangerButton, t)!,
      processingStatus:
          Color.lerp(processingStatus, other.processingStatus, t)!,
      processingText: Color.lerp(processingText, other.processingText, t)!,
      processingContainer:
          Color.lerp(processingContainer, other.processingContainer, t)!,
      disabledControl: Color.lerp(disabledControl, other.disabledControl, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
    );
  }
}

/// Brand & default dark-token constants retained for model helpers while
/// aligning with the unified navy, blue, and cyan color family.
class DeepGuardColors {
  static const Color deepNavy = Color(0xFF101C36);
  static const Color brandBlue = Color(0xFF2457C5);
  static const Color brandCyan = Color(0xFF20B8D5);

  // Default tokens (aligned to Dark palette for non-BuildContext model getters;
  // UI widgets should always read `DeepGuardPalette.of(context)`).
  static const Color primary = Color(0xFF5988F5);
  static const Color primaryDark = Color(0xFF2457C5);
  static const Color secondary = Color(0xFF35C9E2);
  static const Color accent = Color(0xFF20B8D5);

  static const Color background = Color(0xFF101827);
  static const Color surfaceDark = Color(0xFF172338);
  static const Color surfaceCard = Color(0xFF1B2A40);
  static const Color surfaceLight = Color(0xFF22344F);

  static const Color textPrimary = Color(0xFFF4F7FC);
  static const Color textSecondary = Color(0xFFB8C5D8);
  static const Color textMuted = Color(0xFF9BB0C9);

  // Classification tokens (REAL #16865A / A.I. #D64B55)
  static const Color authentic = Color(0xFF16865A);
  static const Color fake = Color(0xFFD64B55);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF2457C5);

  static const Color authenticText = Color(0xFF36CA8D);
  static const Color fakeText = Color(0xFFF47881);
  static const Color infoText = Color(0xFF7FA6FB);
  static const Color accentText = Color(0xFF35C9E2);
  static const Color cyanBright = Color(0xFF35C9E2);

  static const Color glassLight = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0xFF34445B);
  static Color glassBg = const Color(0xFF1B2A40);

  static const List<Color> primaryGradient = [Color(0xFF2457C5), Color(0xFF089BB8)];
  static const List<Color> dangerGradient = [Color(0xFFD64B55), Color(0xFFB82E38)];
  static const List<Color> successGradient = [Color(0xFF16865A), Color(0xFF117A50)];
  static const List<Color> backgroundGradient = [
    Color(0xFF101827),
    Color(0xFF172338),
    Color(0xFF101827),
  ];
  static const List<Color> cardGradient = [Color(0xFF1B2A40), Color(0xFF172338)];

  static Color textSafeFor(Color token, {Brightness brightness = Brightness.dark}) {
    final palette =
        brightness == Brightness.light ? DeepGuardPalette.light : DeepGuardPalette.dark;
    return palette.textSafe(token);
  }
}

/// WCAG 2.2 relative-luminance and contrast utilities.
class DeepGuardContrast {
  static const List<Color> surfaces = [
    DeepGuardColors.background,
    DeepGuardColors.surfaceDark,
    DeepGuardColors.surfaceCard,
    DeepGuardColors.surfaceLight,
  ];

  static double _channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

  static double luminance(Color c) =>
      0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

  /// WCAG 2.2 relative-luminance contrast ratio between two opaque colors.
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static Color textSafeForSurfaces(
    Color color, {
    required List<Color> surfaces,
    required Color targetText,
    double floor = 4.5,
  }) {
    for (var step = 0.0; step <= 1.0; step += 0.04) {
      final candidate = Color.lerp(color, targetText, step)!;
      if (surfaces.every((s) => ratio(candidate, s) >= floor)) {
        return candidate;
      }
    }
    return targetText;
  }

  static Color textSafeOn(
    Color color, {
    double floor = 4.5,
    Brightness brightness = Brightness.dark,
  }) {
    final palette =
        brightness == Brightness.light ? DeepGuardPalette.light : DeepGuardPalette.dark;
    return textSafeForSurfaces(
      color,
      surfaces: palette.allSurfaces,
      targetText: palette.textPrimary,
      floor: floor,
    );
  }

  static Color inkOn(Color fill, {double floor = 4.5}) =>
      inkOnAll([fill], floor: floor);

  static Color inkOnAll(List<Color> fills, {double floor = 4.5}) {
    double worst(Color ink) =>
        fills.map((f) => ratio(ink, f)).reduce((a, b) => a < b ? a : b);
    const dark = Color(0xFF0B1324);
    const light = Color(0xFFFFFFFF);
    if (worst(light) >= floor && worst(light) >= worst(dark)) return light;
    if (worst(dark) >= floor) return dark;
    if (worst(light) >= floor) return light;
    return worst(dark) > worst(light) ? dark : light;
  }
}

/// Reduced-motion helper respecting device accessibility preferences.
bool shouldReduceMotion(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// DeepGuard centralized Material 3 Light and Dark themes.
class DeepGuardTheme {
  static ThemeData get lightTheme => _buildTheme(DeepGuardPalette.light);
  static ThemeData get darkTheme => _buildTheme(DeepGuardPalette.dark);

  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isLight
          ? DeepGuardPalette.light.surface
          : DeepGuardPalette.dark.backgroundSecondary,
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
    );
  }

  static ThemeData _buildTheme(DeepGuardPalette p) {
    final isLight = p.brightness == Brightness.light;
    final colorScheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primaryButton,
      onPrimary: p.onPrimaryButton,
      primaryContainer: p.processingContainer,
      onPrimaryContainer: p.textPrimary,
      secondary: p.accent,
      onSecondary: DeepGuardContrast.inkOn(p.accent),
      secondaryContainer: p.surfaceElevated,
      onSecondaryContainer: p.textPrimary,
      tertiary: p.brandNavy,
      onTertiary: Colors.white,
      error: p.errorText,
      onError: DeepGuardContrast.inkOn(p.errorText),
      errorContainer: p.errorContainer,
      onErrorContainer: p.textPrimary,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: p.controlBorder,
      outlineVariant: p.border,
      shadow: Colors.black.withValues(alpha: isLight ? 0.08 : 0.30),
      scrim: Colors.black54,
    );

    final textTheme = TextTheme(
      // Main screen titles (24–30 logical px)
      displayLarge: TextStyle(
        color: p.textPrimary,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: -0.4,
      ),
      displayMedium: TextStyle(
        color: p.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.22,
        letterSpacing: -0.3,
      ),
      headlineLarge: TextStyle(
        color: p.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
      ),
      // Section headings (18–22 logical px)
      headlineMedium: TextStyle(
        color: p.textPrimary,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        color: p.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        color: p.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      // Body & Input labels (14–18 logical px)
      titleMedium: TextStyle(
        color: p.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        color: p.textSecondary,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      bodyLarge: TextStyle(
        color: p.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: p.textSecondary,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      // Secondary descriptions (13–14 logical px)
      bodySmall: TextStyle(
        color: p.textMuted,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      // Button & Control labels (15–16 logical px)
      labelLarge: TextStyle(
        color: p.textPrimary,
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0.2,
      ),
      labelMedium: TextStyle(
        color: p.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
      labelSmall: TextStyle(
        color: p.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      scaffoldBackgroundColor: p.backgroundSecondary,
      primaryColor: p.primaryButton,
      colorScheme: colorScheme,
      textTheme: textTheme,
      focusColor: p.focusIndicator.withValues(alpha: 0.18),
      splashColor: p.primary.withValues(alpha: 0.10),
      highlightColor: p.primary.withValues(alpha: 0.06),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: overlayStyleFor(p.brightness),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: p.primaryText, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primaryButton.withValues(alpha: isLight ? 0.14 : 0.22),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? p.primaryText : p.textMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.primaryText : p.textMuted,
            size: 24,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primaryText,
        unselectedItemColor: p.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isLight ? 0 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryButton,
          foregroundColor: p.onPrimaryButton,
          disabledBackgroundColor: p.disabledControl,
          disabledForegroundColor: p.disabledText,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primaryButton,
          foregroundColor: p.onPrimaryButton,
          disabledBackgroundColor: p.disabledControl,
          disabledForegroundColor: p.disabledText,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          disabledForegroundColor: p.disabledText,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: p.controlBorder, width: 1.25),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primaryText,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.primaryText,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primaryButton;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(p.onPrimaryButton),
        side: BorderSide(color: p.controlBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.backgroundSecondary,
        labelStyle: TextStyle(color: p.textSecondary, fontSize: 15),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.controlBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.controlBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.focusIndicator, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.errorText, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: p.textSecondary,
          fontSize: 15,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.brandNavy,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          height: 1.4,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
        space: 24,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.processingStatus,
        linearTrackColor: p.surfaceElevated,
        circularTrackColor: p.surfaceElevated,
      ),
    );
  }
}
