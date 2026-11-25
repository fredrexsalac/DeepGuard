import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepfake_flutter_app/models/gradcam_evidence.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/prediction_result.dart';
import 'package:deepfake_flutter_app/screens/about_screen.dart';
import 'package:deepfake_flutter_app/screens/result_screen.dart';
import 'package:deepfake_flutter_app/theme/app_theme.dart';
import 'package:deepfake_flutter_app/widgets/upload_confirmation_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleImg;
  late String sampleCropB64;

  setUpAll(() {
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

    tempDir = Directory.systemTemp.createTempSync('dg_gradcam_test_');
    final canvas = img.Image(width: 256, height: 256);
    img.fill(canvas, color: img.ColorRgb8(42, 86, 160));
    final png = img.encodePng(canvas);
    sampleCropB64 = base64Encode(png);
    sampleImg = File('${tempDir.path}/sample_face.png')..writeAsBytesSync(png);
  });

  tearDownAll(() {
    PaintingBinding.instance.imageCache.clear();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AboutScreen displays the original DeepGuard logo asset',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DeepGuardTheme.lightTheme,
        home: const AboutScreen(),
      ),
    );
    await tester.pump();

    final logoFinder = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/images/deepguard_logo.png',
    );
    expect(logoFinder, findsOneWidget);
  });

  testWidgets(
      'UploadConfirmationSheet shows explicit Are you sure confirmation dialog before analyzing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? sheetResult;

    await tester.pumpWidget(
      MaterialApp(
        theme: DeepGuardTheme.lightTheme,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  sheetResult = await UploadConfirmationSheet.show(
                    context: ctx,
                    filePath: sampleImg.path,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Validation Checks').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Ready for Analysis'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Authorization Confirmation'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    // Check authorization confirmation
    final authBox = find.text('Authorization Confirmation');
    expect(authBox, findsOneWidget);
    await tester.ensureVisible(authBox);
    await tester.tap(authBox);
    await tester.pumpAndSettle();

    // Tap Analyze Now -> must present explicit confirmation warning dialog
    final analyzeNow = find.text('Analyze Now');
    await tester.ensureVisible(analyzeNow);
    await tester.tap(analyzeNow);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Media Analysis'), findsOneWidget);
    expect(
      find.textContaining('Are you sure you want to analyze this image'),
      findsOneWidget,
    );

    // Confirming with "Yes, Analyze" returns true
    await tester.tap(find.text('Yes, Analyze'));
    await tester.pumpAndSettle();
    expect(sheetResult, isTrue);
  });

  test('GradCamEvidence round-trips through HistoryEntry JSON cleanly', () {
    final heatmap = List<double>.generate(64 * 64, (i) => (i % 64) / 63.0);
    final evidence = GradCamEvidence(
      targetLabel: 'A.I.',
      heatmap: heatmap,
      analyzedCropPngBase64: sampleCropB64,
      topVideoFrames: [
        VideoFrameGradCam(
          frameIndex: 2,
          totalFrames: 10,
          importanceScore: 0.42,
          heatmap: heatmap,
          thumbnailPngBase64: sampleCropB64,
        ),
        VideoFrameGradCam(
          frameIndex: 5,
          totalFrames: 10,
          importanceScore: 0.31,
          heatmap: heatmap,
          thumbnailPngBase64: sampleCropB64,
        ),
        VideoFrameGradCam(
          frameIndex: 8,
          totalFrames: 10,
          importanceScore: 0.19,
          heatmap: heatmap,
          thumbnailPngBase64: sampleCropB64,
        ),
      ],
    );

    final entry = HistoryEntry(
      id: 'gc-json-1',
      filePath: sampleImg.path,
      mediaType: 'video',
      detectionResult: 'manipulated',
      confidence: 0.89,
      timestamp: DateTime(2026, 11, 25, 18, 0),
      gradCam: evidence,
    );

    final decoded = HistoryEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.gradCam, isNotNull);
    expect(decoded.gradCam!.targetLabel, 'A.I.');
    expect(decoded.gradCam!.heatmap.length, 64 * 64);
    expect(decoded.gradCam!.topVideoFrames.length, 3);
    expect(decoded.gradCam!.topVideoFrames.first.frameIndex, 2);
  });

  testWidgets(
      'ResultScreen renders Image Grad-CAM card and Top 3 Video Key Frames with heatmap toggle',
      (tester) async {
    final heatmap = List<double>.generate(64 * 64, (i) => (i % 64) / 63.0);

    // 1. Image Grad-CAM
    await tester.pumpWidget(
      MaterialApp(
        theme: DeepGuardTheme.lightTheme,
        home: ResultScreen(
          result: PredictionResult(
            id: 'img-gc-ui',
            filePath: sampleImg.path,
            mediaType: MediaType.image,
            status: PredictionStatus.completed,
            result: DetectionResult.manipulated,
            confidence: 0.91,
            gradCam: GradCamEvidence(
              targetLabel: 'A.I.',
              heatmap: heatmap,
              analyzedCropPngBase64: sampleCropB64,
            ),
          ),
          filePath: sampleImg.path,
          onAnalyzeAnother: () {},
          onGoHome: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Grad-CAM Model Explanation'), findsOneWidget);
    expect(find.text('Heatmap On'), findsOneWidget);
    await tester.ensureVisible(find.text('Heatmap On'));
    await tester.pump();
    await tester.tap(find.text('Heatmap On'));
    await tester.pump();
    expect(find.text('Heatmap Off'), findsOneWidget);

    // 2. Video Top 3 Key Frames Grad-CAM
    await tester.pumpWidget(
      MaterialApp(
        theme: DeepGuardTheme.darkTheme,
        home: ResultScreen(
          result: PredictionResult(
            id: 'vid-gc-ui',
            filePath: '${tempDir.path}/missing_video.mp4',
            mediaType: MediaType.video,
            status: PredictionStatus.completed,
            result: DetectionResult.authentic,
            confidence: 0.84,
            gradCam: GradCamEvidence(
              targetLabel: 'REAL',
              heatmap: heatmap,
              topVideoFrames: [
                VideoFrameGradCam(
                  frameIndex: 1,
                  totalFrames: 10,
                  importanceScore: 0.55,
                  heatmap: heatmap,
                  thumbnailPngBase64: sampleCropB64,
                ),
                VideoFrameGradCam(
                  frameIndex: 4,
                  totalFrames: 10,
                  importanceScore: 0.30,
                  heatmap: heatmap,
                  thumbnailPngBase64: sampleCropB64,
                ),
                VideoFrameGradCam(
                  frameIndex: 8,
                  totalFrames: 10,
                  importanceScore: 0.15,
                  heatmap: heatmap,
                  thumbnailPngBase64: sampleCropB64,
                ),
              ],
            ),
          ),
          filePath: '${tempDir.path}/missing_video.mp4',
          onAnalyzeAnother: () {},
          onGoHome: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Key Video Frames (Grad-CAM)'), findsOneWidget);
    expect(find.text('Frame 2/10'), findsOneWidget);
    expect(find.text('Frame 5/10'), findsOneWidget);
    expect(find.text('Frame 9/10'), findsOneWidget);
    expect(find.textContaining('Top #1'), findsOneWidget);
    expect(find.textContaining('Top #2'), findsOneWidget);
    expect(find.textContaining('Top #3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
