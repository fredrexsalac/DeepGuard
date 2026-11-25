import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepfake_flutter_app/main.dart';
import 'package:deepfake_flutter_app/screens/profile_screen.dart';
import 'package:deepfake_flutter_app/services/profile_service.dart';
import 'package:deepfake_flutter_app/services/theme_service.dart';
import 'package:deepfake_flutter_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WCAG 2.2 Level AA Contrast Verification (Light & Dark Palettes)', () {
    Map<String, dynamic> verifyPalette(String modeName, DeepGuardPalette p) {
      final results = <Map<String, dynamic>>[];

      void checkPair(
        String label,
        Color fg,
        Color bg,
        double minRatio,
        String criterion,
      ) {
        final r = DeepGuardContrast.ratio(fg, bg);
        results.add({
          'theme': modeName,
          'pair': label,
          'foreground':
              '#${fg.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          'background':
              '#${bg.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          'measuredRatio': double.parse(r.toStringAsFixed(2)),
          'requiredFloor': minRatio,
          'criterion': criterion,
          'status': r >= minRatio ? 'PASS' : 'FAIL',
        });
        expect(
          r,
          greaterThanOrEqualTo(minRatio),
          reason:
              '[$modeName] $label ($criterion) measured ${r.toStringAsFixed(2)}:1, expected >= $minRatio:1',
        );
      }

      for (final (surfName, surf) in [
        ('backgroundPrimary', p.backgroundPrimary),
        ('backgroundSecondary', p.backgroundSecondary),
        ('surface', p.surface),
        ('surfaceElevated', p.surfaceElevated),
      ]) {
        checkPair('textPrimary on $surfName', p.textPrimary, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('textSecondary on $surfName', p.textSecondary, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('textMuted on $surfName', p.textMuted, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('primaryText on $surfName', p.primaryText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('accentText on $surfName', p.accentText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('realText on $surfName', p.realText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('aiText on $surfName', p.aiText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('warningText on $surfName', p.warningText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('errorText on $surfName', p.errorText, surf, 4.5,
            'SC 1.4.3 Normal Text');
        checkPair('controlBorder on $surfName', p.controlBorder, surf, 3.0,
            'SC 1.4.11 UI Component Boundary');
        checkPair('focusIndicator on $surfName', p.focusIndicator, surf, 3.0,
            'SC 1.4.11 Focus Indicator');
      }

      // Status container pairs
      checkPair('realText on realContainer', p.realText, p.realContainer, 4.5,
          'SC 1.4.3 Verdict Badge Text');
      checkPair('aiText on aiContainer', p.aiText, p.aiContainer, 4.5,
          'SC 1.4.3 Verdict Badge Text');
      checkPair('warningText on warningContainer', p.warningText,
          p.warningContainer, 4.5, 'SC 1.4.3 Warning Banner Text');
      checkPair('errorText on errorContainer', p.errorText, p.errorContainer,
          4.5, 'SC 1.4.3 Error Banner Text');
      checkPair('primaryText on processingContainer', p.primaryText,
          p.processingContainer, 4.5, 'SC 1.4.3 Processing Chip Text');

      // Primary, secondary & destructive button ink
      checkPair('onPrimaryButton on primaryButton', p.onPrimaryButton,
          p.primaryButton, 4.5, 'SC 1.4.3 Primary Button Label');
      checkPair('onSecondaryButton on secondaryButton', p.onSecondaryButton,
          p.secondaryButton, 4.5, 'SC 1.4.3 Secondary Button Label');
      checkPair('onDangerButton on dangerButton', p.onDangerButton,
          p.dangerButton, 4.5, 'SC 1.4.3 Destructive Button / Error Toast');

      // Graphic classification indicators on card surface (>= 3:1 SC 1.4.11)
      checkPair('realClassification graphic on surface', p.realClassification,
          p.surface, 3.0, 'SC 1.4.11 Graphic Status');
      checkPair('aiClassification graphic on surface', p.aiClassification,
          p.surface, 3.0, 'SC 1.4.11 Graphic Status');
      checkPair('accent graphic on surface', p.accent, p.surface, 3.0,
          'SC 1.4.11 Graphic Accent');

      return {'mode': modeName, 'checks': results};
    }

    test('Light Mode and Dark Mode pass all WCAG 2.2 AA contrast thresholds',
        () {
      final lightAudit = verifyPalette('Light Mode', DeepGuardPalette.light);
      final darkAudit = verifyPalette('Dark Mode', DeepGuardPalette.dark);

      final outDir = Directory('accessibility_test_evidence');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      File('accessibility_test_evidence/contrast_audit_evidence.json')
          .writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'standard': 'WCAG 2.2 Level AA (SC 1.4.3 & SC 1.4.11)',
          'lightMode': lightAudit,
          'darkMode': darkAudit,
        }),
      );
    });
  });

  group('ThemeService — Light, Dark, System Default & Persistence', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ThemeService().resetForTesting();
      await ProfileService().init();
      await ThemeService().init();
    });

    test('defaults to ThemeMode.system and persists Light and Dark choices',
        () async {
      final svc = ThemeService();
      expect(svc.themeMode, ThemeMode.system);

      await svc.setThemeMode(ThemeMode.light);
      expect(svc.themeMode, ThemeMode.light);

      // Simulate cold restart
      svc.resetForTesting();
      await svc.init();
      expect(svc.themeMode, ThemeMode.light);

      await svc.setThemeMode(ThemeMode.dark);
      svc.resetForTesting();
      await svc.init();
      expect(svc.themeMode, ThemeMode.dark);

      await svc.setThemeMode(ThemeMode.system);
      svc.resetForTesting();
      await svc.init();
      expect(svc.themeMode, ThemeMode.system);
    });

    testWidgets(
        'switching theme in ProfileScreen updates MaterialApp immediately without restart',
        (tester) async {
      await ThemeService().setOnboardingCompleted(true);
      await tester.pumpWidget(const DeepGuardApp());
      // Advance splash animation (950ms + transition)
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      // Navigate to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      // Select Light Mode
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(ThemeService().themeMode, ThemeMode.light);
      MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);

      // Select Dark Mode
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(ThemeService().themeMode, ThemeMode.dark);
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      // Select System Default
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(ThemeService().themeMode, ThemeMode.system);
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
    });

    testWidgets('System Default follows platform brightness changes',
        (tester) async {
      await ThemeService().setOnboardingCompleted(true);
      await ThemeService().setThemeMode(ThemeMode.system);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const DeepGuardApp());
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      BuildContext innerCtx = tester.element(find.text('DEEPGUARD'));
      expect(Theme.of(innerCtx).brightness, Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      innerCtx = tester.element(find.text('DEEPGUARD'));
      expect(Theme.of(innerCtx).brightness, Brightness.dark);
    });
  });
}
