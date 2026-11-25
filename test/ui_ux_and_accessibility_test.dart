import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepfake_flutter_app/models/analysis_framing.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/prediction_result.dart';
import 'package:deepfake_flutter_app/screens/about_screen.dart';
import 'package:deepfake_flutter_app/screens/home_screen.dart';
import 'package:deepfake_flutter_app/screens/onboarding_screen.dart';
import 'package:deepfake_flutter_app/screens/processing_screen.dart';
import 'package:deepfake_flutter_app/screens/profile_screen.dart';
import 'package:deepfake_flutter_app/screens/result_screen.dart';
import 'package:deepfake_flutter_app/screens/upload_screen.dart';
import 'package:deepfake_flutter_app/services/ai_service.dart';
import 'package:deepfake_flutter_app/services/profile_service.dart';
import 'package:deepfake_flutter_app/services/theme_service.dart';
import 'package:deepfake_flutter_app/theme/app_theme.dart';

Future<void> _loadRealFontsIfAvailable() async {
  try {
    final robotoLoader = FontLoader('Roboto');
    bool addedAny = false;
    for (final path in [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\seguisb.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
      r'C:\Windows\Fonts\segoeuil.ttf',
    ]) {
      final f = File(path);
      if (f.existsSync()) {
        final bytes = f.readAsBytesSync();
        robotoLoader.addFont(Future.value(ByteData.sublistView(bytes)));
        addedAny = true;
      }
    }
    if (addedAny) {
      await robotoLoader.load();
    }

    final iconsFont = File(
      r'C:\Users\user\Documents\Flutter\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );
    if (iconsFont.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      final iconBytes = iconsFont.readAsBytesSync();
      iconLoader.addFont(Future.value(ByteData.sublistView(iconBytes)));
      await iconLoader.load();
    }
  } catch (_) {}
}

Widget _themedHarness({
  required Widget child,
  required ThemeData theme,
  double textScale = 1.0,
  bool disableAnimations = false,
  GlobalKey? boundaryKey,
}) {
  final robotoTheme = theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle:
          theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: robotoTheme,
    builder: (context, inner) {
      final mq = MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      );
      return MediaQuery(data: mq, child: inner!);
    },
    home: child,
  );
  if (boundaryKey != null) {
    app = RepaintBoundary(key: boundaryKey, child: app);
  }
  return app;
}

Future<void> _capturePng(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  await tester.runAsync(() async {
    final dir = Directory('accessibility_test_evidence');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      File('accessibility_test_evidence/$fileName')
          .writeAsBytesSync(bytes.buffer.asUint8List());
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleImgFile;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['none'],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
    await _loadRealFontsIfAvailable();
    tempDir = Directory.systemTemp.createTempSync('dg_ui_test_');
    sampleImgFile = File('${tempDir.path}/sample_face.png');
    final canvasImg = img.Image(width: 256, height: 256);
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        canvasImg.setPixelRgb(x, y, 40 + (x ~/ 3), 75 + (y ~/ 4), 140);
      }
    }
    sampleImgFile.writeAsBytesSync(img.encodePng(canvasImg));
  });

  tearDownAll(() {
    PaintingBinding.instance.imageCache.clear();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ThemeService().resetForTesting();
    await ProfileService().init();
    await ThemeService().init();
  });

  group('Phase 5 — Homepage Simplification & Removal of Model Accuracy', () {
    testWidgets(
        'Homepage displays clean workflow CTAs and omits all accuracy percentages',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool imageTapped = false;
      bool videoTapped = false;
      bool analyzeTapped = false;

      final lightKey = GlobalKey();
      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.lightTheme,
          boundaryKey: lightKey,
          child: HomeScreen(
            onAnalyzeTap: () => analyzeTapped = true,
            onUploadImageTap: () => imageTapped = true,
            onUploadVideoTap: () => videoTapped = true,
          ),
        ),
      );
      await tester.pump();
      await _capturePng(tester, lightKey, 'home_light_mode.png');

      // Required identity & primary actions
      expect(find.text('DEEPGUARD'), findsOneWidget);
      expect(find.text('AI-Powered Deepfake Detection'), findsOneWidget);
      expect(
        find.text('Analyze images and videos to assess their authenticity.'),
        findsOneWidget,
      );
      expect(find.text('Upload Image'), findsOneWidget);
      expect(find.text('Upload Video'), findsOneWidget);
      expect(find.text('Analyze Media'), findsOneWidget);

      // Strictly forbidden on homepage
      expect(find.textContaining('84.82'), findsNothing);
      expect(find.textContaining('71.67'), findsNothing);
      expect(find.textContaining('MODEL TEST ACCURACY'), findsNothing);
      expect(find.textContaining('deepguard --detect'), findsNothing);

      await tester.tap(find.text('Upload Image'));
      await tester.pump();
      expect(imageTapped, isTrue);

      await tester.tap(find.text('Upload Video'));
      await tester.pump();
      expect(videoTapped, isTrue);

      await tester.tap(find.text('Analyze Media'));
      await tester.pump();
      expect(analyzeTapped, isTrue);

      // Dark mode screenshot verification
      final darkKey = GlobalKey();
      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.darkTheme,
          boundaryKey: darkKey,
          child: HomeScreen(onAnalyzeTap: () {}),
        ),
      );
      await tester.pump();
      await _capturePng(tester, darkKey, 'home_dark_mode.png');
    });
  });

  group('Phase 7 — Truthful Image (6) & Video (9) Processing Stages', () {
    testWidgets(
        'Image processing advances strictly through all 6 real stages with indeterminate bar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final completers = List.generate(6, (_) => Completer<void>());
      PredictionResult? completedResult;
      final imgProcKey = GlobalKey();

      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.lightTheme,
          disableAnimations: true,
          boundaryKey: imgProcKey,
          child: ProcessingScreen(
            filePath: sampleImgFile.path,
            mediaType: 'image',
            source: MediaSource.gallery,
            onComplete: (r) => completedResult = r,
            customRunner: ({
              required id,
              required filePath,
              required mediaType,
              required source,
              required onProgress,
            }) async {
              for (int i = 0; i < AIService.imageStages.length; i++) {
                final (title, detail) = AIService.imageStages[i];
                await onProgress(
                  AnalysisProgressUpdate(
                    stageIndex: i,
                    stageTitle: title,
                    stageDetail: detail,
                  ),
                );
                await completers[i].future;
              }
              return PredictionResult(
                id: id,
                filePath: filePath,
                mediaType: MediaType.image,
                status: PredictionStatus.completed,
                result: DetectionResult.authentic,
                confidence: 0.94,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      const expectedImageStages = [
        'Preparing image',
        'Checking image quality',
        'Detecting human faces',
        'Extracting visual features',
        'Evaluating authenticity',
        'Preparing results',
      ];

      for (int i = 0; i < expectedImageStages.length; i++) {
        expect(find.text('Stage ${i + 1} of 6'), findsOneWidget);
        expect(find.text(expectedImageStages[i]), findsWidgets);
        // Progress bar must be indeterminate (value == null) when no measurable units exist
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, isNull);

        if (i == 2) {
          await _capturePng(
            tester,
            imgProcKey,
            'processing_image_light_mode.png',
          );
        }

        completers[i].complete();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pump(const Duration(milliseconds: 50));
      expect(completedResult, isNotNull);
      expect(completedResult!.resultLabel, 'REAL');
    });

    testWidgets(
        'Video processing advances through all 9 stages and shows percentage ONLY during frame extraction',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final stageGate = List.generate(9, (_) => Completer<void>());
      PredictionResult? completedResult;
      final vidProcKey = GlobalKey();

      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.darkTheme,
          disableAnimations: true,
          boundaryKey: vidProcKey,
          child: ProcessingScreen(
            filePath: '${tempDir.path}/clip.mp4',
            mediaType: 'video',
            source: MediaSource.gallery,
            onComplete: (r) => completedResult = r,
            customRunner: ({
              required id,
              required filePath,
              required mediaType,
              required source,
              required onProgress,
            }) async {
              for (int i = 0; i < AIService.videoStages.length; i++) {
                final (title, detail) = AIService.videoStages[i];
                await onProgress(
                  AnalysisProgressUpdate(
                    stageIndex: i,
                    stageTitle: title,
                    stageDetail: detail,
                    completedUnits: i == 2 ? 4 : null,
                    totalUnits: i == 2 ? 10 : null,
                  ),
                );
                await stageGate[i].future;
              }
              return PredictionResult(
                id: id,
                filePath: filePath,
                mediaType: MediaType.video,
                status: PredictionStatus.completed,
                result: DetectionResult.manipulated,
                confidence: 0.82,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      const expectedVideoStages = [
        'Preparing video',
        'Decoding video',
        'Extracting frames',
        'Filtering unsuitable frames',
        'Detecting human faces',
        'Extracting spatial features',
        'Analyzing temporal features',
        'Evaluating authenticity',
        'Preparing results',
      ];

      for (int i = 0; i < expectedVideoStages.length; i++) {
        expect(find.text(expectedVideoStages[i]), findsWidgets);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        if (i == 2) {
          // Stage 3 (Extracting frames) has measurable 4/10 -> 40%
          expect(bar.value, closeTo(0.4, 0.01));
          expect(find.text('40%'), findsOneWidget);
          expect(find.text('4/10 frames'), findsOneWidget);
          await _capturePng(
            tester,
            vidProcKey,
            'processing_video_dark_mode.png',
          );
        } else {
          // Non-measurable stages use indeterminate loading
          expect(bar.value, isNull);
        }
        stageGate[i].complete();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pump(const Duration(milliseconds: 50));
      expect(completedResult, isNotNull);
      expect(completedResult!.resultLabel, 'A.I.');
    });

    testWidgets(
        'Cancel Analysis cleanly aborts UI flow without invoking onComplete',
        (tester) async {
      final gate = Completer<void>();
      bool completedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: DeepGuardTheme.lightTheme,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ProcessingScreen(
                        filePath: sampleImgFile.path,
                        mediaType: 'image',
                        source: MediaSource.gallery,
                        onComplete: (_) => completedCalled = true,
                        customRunner: ({
                          required id,
                          required filePath,
                          required mediaType,
                          required source,
                          required onProgress,
                        }) async {
                          await onProgress(
                            const AnalysisProgressUpdate(
                              stageIndex: 1,
                              stageTitle: 'Checking image quality',
                              stageDetail: 'Decoding image…',
                            ),
                          );
                          await gate.future;
                          return PredictionResult(
                            id: id,
                            filePath: filePath,
                            mediaType: MediaType.image,
                            status: PredictionStatus.completed,
                            result: DetectionResult.authentic,
                            confidence: 0.9,
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open Processing'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Processing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cancel Analysis'), findsOneWidget);

      await tester.ensureVisible(find.text('Cancel Analysis'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Cancel Analysis'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Complete background worker after cancel; onComplete must remain false
      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(completedCalled, isFalse);
      expect(find.text('Open Processing'), findsOneWidget);
    });
  });

  group('Phase 8 — REAL and A.I. Result Presentation & Model Confidence', () {
    testWidgets(
        'REAL and A.I. results display clear labels, icons, and Model Confidence in Light & Dark modes',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final realResult = PredictionResult(
        id: 'res-real-1',
        filePath: sampleImgFile.path,
        mediaType: MediaType.image,
        status: PredictionStatus.completed,
        result: DetectionResult.authentic,
        confidence: 0.926,
        framing: const AnalysisFraming(
          frameWidth: 256,
          frameHeight: 256,
          faceCount: 1,
          faceRect: BoxRect(40, 36, 176, 184),
          note: 'face already fills the frame',
        ),
      );

      final realKey = GlobalKey();
      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.lightTheme,
          boundaryKey: realKey,
          child: ResultScreen(
            result: realResult,
            filePath: sampleImgFile.path,
            onAnalyzeAnother: () {},
            onGoHome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _capturePng(tester, realKey, 'result_real_light_mode.png');

      expect(find.text('REAL'), findsOneWidget);
      expect(find.text('REAL (Real)'), findsOneWidget);
      expect(find.text('Model Confidence'), findsWidgets);
      expect(find.text('92.6%'), findsWidgets);
      expect(find.textContaining('Prediction\nConfidence'), findsNothing);

      // Now verify A.I. result in Dark Mode
      final aiResult = PredictionResult(
        id: 'res-ai-1',
        filePath: sampleImgFile.path,
        mediaType: MediaType.image,
        status: PredictionStatus.completed,
        result: DetectionResult.manipulated,
        confidence: 0.874,
      );

      final aiKey = GlobalKey();
      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.darkTheme,
          boundaryKey: aiKey,
          child: ResultScreen(
            result: aiResult,
            filePath: sampleImgFile.path,
            onAnalyzeAnother: () {},
            onGoHome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _capturePng(tester, aiKey, 'result_ai_dark_mode.png');

      expect(find.text('A.I.'), findsOneWidget);
      expect(find.text('A.I. (Fake)'), findsOneWidget);
      expect(find.text('87.4%'), findsWidgets);
    });
  });

  group('Phase 9 — WCAG 2.2 AA Touch Targets, Semantics, 200% Text Scaling & Landscape', () {
    testWidgets(
        'All core screens meet Android 48dp / iOS 44pt / Labeled Tap Target guidelines and survive 200% font scaling & landscape rotation',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {

      // Seed one history item so ProfileScreen exercises populated history controls
      final profile = ProfileService().activeProfile!;
      await ProfileService().saveHistoryEntry(
        profile.id,
        HistoryEntry(
          id: 'hist-1',
          filePath: sampleImgFile.path,
          mediaType: 'image',
          detectionResult: 'manipulated',
          confidence: 0.88,
          timestamp: DateTime(2026, 11, 25, 8, 30),
        ),
      );

      final screens = <(String, Widget)>[
        ('onboarding', OnboardingScreen(onDone: () {})),
        ('home', HomeScreen(onAnalyzeTap: () {})),
        ('upload', UploadScreen(onFileSelected: (_, __, ___) {})),
        ('about', const AboutScreen()),
        ('settings', const ProfileScreen()),
      ];

      // 1. Standard 390x844 mobile viewport in Light & Dark modes: check guidelines + capture screenshots
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final (name, widget) in screens) {
        for (final (modeLabel, theme) in [
          ('light', DeepGuardTheme.lightTheme),
          ('dark', DeepGuardTheme.darkTheme),
        ]) {
          final snapKey = GlobalKey();
          await tester.pumpWidget(
            _themedHarness(
              theme: theme,
              boundaryKey: snapKey,
              child: widget,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$name ($modeLabel) threw during render');

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          if (name == 'upload' || name == 'about' || name == 'settings') {
            await _capturePng(tester, snapKey, '${name}_${modeLabel}_mode.png');
          }
        }
      }

      // 2. 200% Dynamic System Font Scaling (WCAG 1.4.4) — zero RenderFlex overflow
      for (final (name, widget) in screens) {
        final scaleKey = name == 'home' ? GlobalKey() : null;
        await tester.pumpWidget(
          _themedHarness(
            theme: DeepGuardTheme.lightTheme,
            textScale: 2.0,
            boundaryKey: scaleKey,
            child: widget,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$name overflowed at 200% system text scale',
        );
        if (scaleKey != null) {
          await _capturePng(tester, scaleKey, 'home_200pct_text_scale.png');
        }
      }

      // Also verify ResultScreen at 200% text scale
      await tester.pumpWidget(
        _themedHarness(
          theme: DeepGuardTheme.darkTheme,
          textScale: 2.0,
          child: ResultScreen(
            result: PredictionResult(
              id: 'scale-r1',
              filePath: sampleImgFile.path,
              mediaType: MediaType.image,
              status: PredictionStatus.completed,
              result: DetectionResult.authentic,
              confidence: 0.91,
            ),
            filePath: sampleImgFile.path,
            onAnalyzeAnother: () {},
            onGoHome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      // 3. Landscape Orientation 844x390 (WCAG 1.3.4) — zero overflow
      await tester.binding.setSurfaceSize(const Size(844, 390));
      for (final (name, widget) in screens) {
        await tester.pumpWidget(
          _themedHarness(
            theme: DeepGuardTheme.darkTheme,
            child: widget,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$name overflowed in 844x390 landscape orientation',
        );
      }
      } finally {
        handle.dispose();
      }
    });
  });
}
