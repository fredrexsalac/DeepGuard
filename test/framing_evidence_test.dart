/// Tests for the framing-evidence feature.
///
/// Everything here is verifiable without a device: the geometry is plain
/// integers, the serialisation has to survive a legacy record that predates the
/// feature, and the legend carries the sentence that stops a face rectangle
/// being read as a manipulation location. That sentence is a product constraint,
/// so it is pinned rather than trusted.
///
/// The numbers come from a real capture on an Infinix X6885, 2026-10-24 12:56,
/// logged as:
///   [FACE-CROP] faces=1 faceBox=[483,1237 1316x1755] frame=2160x3840
///               -> crop=[0,1035 2160x2160] coverage=56.3%
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepfake_flutter_app/models/analysis_framing.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/widgets/framing_evidence_overlay.dart';

final _cropCase = AnalysisFraming(
  frameWidth: 2160,
  frameHeight: 3840,
  faceCount: 1,
  faceRect: const BoxRect(483, 1237, 1316, 1755),
  analysedRect: const BoxRect(0, 1035, 2160, 2160),
  note: 'face region analysed',
);

final _noFaceCase = AnalysisFraming(
  frameWidth: 2160,
  frameHeight: 3840,
  faceCount: 0,
  note: 'no face detected; whole frame analysed',
);

void main() {
  group('AnalysisFraming geometry', () {
    test('reproduces the coverage measured on device', () {
      expect(_cropCase.cropApplied, isTrue);
      expect(_cropCase.faceFound, isTrue);
      // 2160*2160 / (2160*3840) = 0.5625, logged as 56.3%.
      expect(_cropCase.coveragePercent, closeTo(56.25, 0.01));
      expect(_cropCase.summary, contains('FACE CROP'));
    });

    test('a whole-frame result reports the entire frame as analysed', () {
      // The 12:50 capture: no face, so the model saw the desk as well as the
      // subject. Coverage must be 100%, not zero — the frame IS the input.
      expect(_noFaceCase.cropApplied, isFalse);
      expect(_noFaceCase.faceFound, isFalse);
      expect(_noFaceCase.analysedBox.width, 2160);
      expect(_noFaceCase.analysedBox.height, 3840);
      expect(_noFaceCase.coveragePercent, closeTo(100.0, 0.01));
      expect(_noFaceCase.summary, contains('WHOLE FRAME'));
    });

    test('survives a JSON round trip through the real encoder', () {
      final decoded =
          AnalysisFraming.fromJson(jsonDecode(jsonEncode(_cropCase.toJson()))
              as Map<String, dynamic>);
      expect(decoded.frameHeight, 3840);
      expect(decoded.faceCount, 1);
      expect(decoded.analysedRect!.top, 1035);
      expect(decoded.analysedRect!.height, 2160);
      expect(decoded.faceRect!.left, 483);
      expect(decoded.cropApplied, isTrue);
    });
  });

  group('HistoryEntry persistence', () {
    test('framing round-trips with the stored record', () {
      final stored = HistoryEntry(
        id: 'x1',
        filePath: '/tmp/a.jpg',
        mediaType: 'image',
        detectionResult: 'manipulated',
        confidence: 0.732608,
        timestamp: DateTime.utc(2026, 10, 24, 12, 56),
        framing: _cropCase,
      );
      final restored = HistoryEntry.fromJson(
          jsonDecode(jsonEncode(stored.toJson())) as Map<String, dynamic>);
      expect(restored.framing, isNotNull);
      expect(restored.framing!.analysedRect!.top, 1035);
      expect(restored.framing!.faceCount, 1);
    });

    test('a legacy record yields null rather than an invented box', () {
      // Records saved before this feature carry no 'framing' key at all. The
      // UI must draw nothing rather than guess where a face was.
      final legacy = HistoryEntry.fromJson({
        'id': 'old',
        'mediaType': 'image',
        'detectionResult': 'authentic',
        'confidence': 0.99,
        'timestamp': DateTime.utc(2026, 10, 1).toIso8601String(),
      });
      expect(legacy.framing, isNull);
    });

    test('copyWith preserves framing when overriding provenance', () {
      final stored = HistoryEntry(
        id: 'x2',
        mediaType: 'image',
        confidence: 0.5,
        timestamp: DateTime.utc(2026, 10, 24),
        framing: _cropCase,
      );
      expect(stored.copyWith().framing, isNotNull);
    });
  });

  group('FramingEvidenceOverlay', () {
    Future<int> painterCount(WidgetTester t, AnalysisFraming? f) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 180,
            child: FramingEvidenceOverlay(
              framing: f,
              child: const ColoredBox(
                color: Colors.blue,
                child: Text('media', key: Key('media')),
              ),
            ),
          ),
        ),
      ));
      return find.byType(CustomPaint).evaluate().length;
    }

    // Measured against the no-framing case rather than against zero: Material
    // and Scaffold install their own CustomPaint, so an absolute count is a
    // property of the framework, not of this widget.
    testWidgets('draws nothing it has no geometry for', (t) async {
      final bare = await painterCount(t, null);
      expect(find.byKey(const Key('media')), findsOneWidget);
      expect(t.takeException(), isNull);

      final framed = await painterCount(t, _cropCase);
      expect(framed, greaterThan(bare));
    });

    testWidgets('paints a real crop without throwing', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 180,
            child: FramingEvidenceOverlay(
              framing: _cropCase,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('a whole-frame result paints without throwing either',
        (t) async {
      // The 12:50 shape of the problem: no crop, so the scrim must cover
      // nothing and the border must land exactly on the image edge.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 180,
            child: FramingEvidenceOverlay(
              framing: _noFaceCase,
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  });

  group('FramingEvidenceLegend', () {
    Future<void> pumpLegend(WidgetTester t, AnalysisFraming f) =>
        t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FramingEvidenceLegend(
                  framing: f, mutedColor: Colors.grey),
            ),
          ),
        ));

    testWidgets('states that the marks do not locate manipulation', (t) async {
      await pumpLegend(t, _cropCase);
      expect(find.textContaining('They do not locate'), findsOneWidget);
      expect(find.textContaining('region analysed'), findsOneWidget);
      expect(find.textContaining('face located'), findsOneWidget);
    });

    testWidgets('the no-face case names the whole frame explicitly', (t) async {
      await pumpLegend(t, _noFaceCase);
      expect(find.textContaining('No face was found'), findsOneWidget);
      expect(find.textContaining('2160x3840'), findsOneWidget);
    });

    testWidgets('draws nothing when the record has no framing', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FramingEvidenceLegend(framing: null, mutedColor: Colors.grey),
        ),
      ));
      expect(find.textContaining('They do not locate'), findsNothing);
    });
  });
}
