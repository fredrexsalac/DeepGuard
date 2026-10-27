import 'dart:math' show pow;

import 'package:flutter/material.dart';

/// Palette, with the measured WCAG 2.x contrast ratio of each token against
/// the four surfaces it can land on — background, surfaceDark, surfaceCard,
/// surfaceLight. The WORST case is the number that governs, because a token
/// has to survive every card it is dropped onto.
///
/// Text tokens carry a 4.5:1 floor (AA, normal size). Chrome tokens carry 3:1
/// (SC 1.4.11, non-text). Ratios are sRGB relative luminance — exact on paper,
/// so the floors keep visible headroom rather than sitting on 4.50.
///
/// Two rules follow from this and are worth keeping: never dim text with
/// withAlpha(), because the ramp has no passing step below the named tokens
/// (textMuted already fails at alpha 224); and never read a status colour out
/// of the saturated originals — they are tuned for fills, icons and gradients,
/// and their text-safe variants exist for that.
class DeepGuardColors {
  // Core palette
  static const Color primary = Color(0xFF00D4FF); //  7.33:1 · AAA
  static const Color primaryDark = Color(0xFF0099CC); //  4.76:1 on surfaceCard
  // Was 0xFF7B2FF7, which measured 2.66:1 on surfaceCard — it failed both as
  // the icon tint on the pipeline stages and as a gradient stop you had to read.
  static const Color secondary = Color(0xFFA78BFA); //  4.77:1 · AA
  static const Color accent = Color(0xFFFF2D95); //  3.75:1 · fills and icons only

  // Background
  static const Color background = Color(0xFF0A0E27);
  static const Color surfaceDark = Color(0xFF111537);
  static const Color surfaceCard = Color(0xFF1A1F4E);
  static const Color surfaceLight = Color(0xFF24296E);

  // Text. Three steps, all of which clear 4.5:1 on every surface.
  static const Color textPrimary = Color(0xFFF0F4FF); // 11.80:1 · AAA
  // Was 0xFF8892B0 — 4.20:1 on surfaceLight, i.e. it failed on the lightest
  // card while passing on the other three, which is easy to miss in review.
  static const Color textSecondary = Color(0xFFA8B2CE); //  6.14:1 · AA
  // Was 0xFF565F89 at 2.10–3.07:1 — it failed on all four surfaces and was
  // bound to bodyMedium, so ordinary 14px body text was sub-AA by design.
  static const Color textMuted = Color(0xFF9AA3BE); //  5.17:1 · AA

  // Status. The originals are the classification identity and stay unchanged;
  // the *Text variants are for when a status colour has to be read as words,
  // which is where the originals fall off on a card.
  static const Color authentic = Color(0xFF00E676); //  7.78:1 · AAA
  static const Color fake = Color(0xFFFF1744); //  4.94:1 bg, 3.37:1 worst
  static const Color warning = Color(0xFFFFAB00); //  6.85:1 · AA
  static const Color info = Color(0xFF448AFF); //  5.72:1 bg, 3.91:1 worst

  // Text-safe status variants.
  static const Color fakeText = Color(0xFFFF6B84); //    4.75:1 · AA
  static const Color infoText = Color(0xFF7FB3FF); //   6.06:1 · AA
  static const Color accentText = Color(0xFFFF6BB0); // 4.94:1 · AA

  // A cyan that is not the brand primary, used where two cyans side by side
  // would read as one colour (the Camera Capture tile next to Image Detect).
  // Tuned, not sampled: this clears 8.44:1 on the lightest card.
  static const Color cyanBright = Color(0xFF00E5FF); //  8.44:1 worst · AA

  // Glass. glassBorder was 0x4DFFFFFF, which measured 2.62:1 against the page
  // background — under the 3:1 non-text floor. 0x56 is the minimum that clears
  // it; 0x66 leaves headroom. glassLight is a decorative fill, not an edge.
  static const Color glassLight = Color(0x33FFFFFF);
  static const Color glassBorder = Color(0x66FFFFFF); //  3.77:1 · non-text pass
  static Color glassBg = const Color(0x14FFFFFF);

  // Gradients
  static const List<Color> primaryGradient = [primary, secondary];
  static const List<Color> dangerGradient = [accent, Color(0xFFFF6B35)];
  static const List<Color> successGradient = [Color(0xFF00E676), Color(0xFF00BFA5)];
  static const List<Color> backgroundGradient = [Color(0xFF0A0E27), Color(0xFF0D1635), Color(0xFF0A0E27)];
  static const List<Color> cardGradient = [Color(0xFF1A1F4E), Color(0xFF111537)];

  /// The text-safe twin of a status or accent token, for the common case of a
  /// widget that receives an accent as a parameter and paints both a mark and a
  /// word with it. Tiles, stat boxes and step cards pass [primary], [fake],
  /// [warning] and friends straight through here: the fill keeps the identity
  /// colour, the label keeps something that can be read.
  static Color textSafeFor(Color token) => switch (token) {
        fake => fakeText,
        info => infoText,
        DeepGuardColors.accent => accentText,
        _ => DeepGuardContrast.textSafeOn(token),
      };
}

/// Colour utilities used where a hue is fixed by something outside the palette
/// — a vendor's brand colour, a metadata-derived identity — and still has to be
/// readable as text. The named tokens above are the answer for everything the
/// app itself colours; this is the answer for everything it cannot rename.
class DeepGuardContrast {
  static const List<Color> surfaces = [
    DeepGuardColors.background,
    DeepGuardColors.surfaceDark,
    DeepGuardColors.surfaceCard,
    DeepGuardColors.surfaceLight,
  ];

  static double _channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();

  static double _luminance(Color c) => 0.2126 * _channel(c.r) +
      0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

  /// WCAG 2.x relative-luminance contrast ratio between two opaque colours.
  static double ratio(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// [color] lifted toward [DeepGuardColors.textPrimary] until it clears
  /// [floor] against every surface it could land on, so the hue still reads as
  /// the same hue but is no longer painted at 3.5:1 on the lightest card. A
  /// colour that already passes is returned untouched.
  static Color textSafeOn(Color color, {double floor = 4.5}) {
    for (var step = 0.0; step <= 1.0; step += 0.05) {
      final candidate = Color.lerp(color, DeepGuardColors.textPrimary, step)!;
      if (surfaces.every((s) => ratio(candidate, s) >= floor)) {
        return candidate;
      }
    }
    return DeepGuardColors.textPrimary;
  }

  /// Ink for text or an icon sitting ON TOP of [fill] rather than on a page
  /// surface — a gradient button, a tinted chip, a saturated badge. Chooses
  /// whichever end of the ramp survives: near-black over the bright cyans and
  /// ambers, near-white over the deep navy and the dark reds.
  ///
  /// This exists because 'ANALYSE FILE' was white on the primary→secondary
  /// gradient at 1.88:1. White text on a coloured fill reads as a designer's
  /// default rather than a measured value, and the default fails.
  static Color inkOn(Color fill, {double floor = 4.5}) =>
      inkOnAll([fill], floor: floor);

  /// As [inkOn], for a fill that is not one colour: a gradient, or a chip that
  /// may be dropped on any card. The candidate that wins is the one whose
  /// worst stop is least bad, because a label sitting over the bright half of
  /// a gradient is judged by the bright half.
  static Color inkOnAll(List<Color> fills, {double floor = 4.5}) {
    double worst(Color ink) =>
        fills.map((f) => ratio(ink, f)).reduce((a, b) => a < b ? a : b);
    const dark = DeepGuardColors.background;
    const light = DeepGuardColors.textPrimary;
    if (worst(dark) >= floor) return dark;
    if (worst(light) >= floor) return light;
    return worst(dark) > worst(light) ? dark : light;
  }
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
        // Error text is rendered small, on a field's own surface, so it uses
        // the text-safe red. The saturated `fake` stays reserved for
        // classification output, where the colour is the verdict's identity.
        error: DeepGuardColors.fakeText,
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