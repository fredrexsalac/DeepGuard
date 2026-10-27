import 'package:deepfake_flutter_app/models/analysis_outcome.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/provenance_snapshot.dart';
import 'package:deepfake_flutter_app/widgets/outcome_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The provenance cross-check: a saved verdict compared against what the file's
/// own embedded metadata says, with no human input at any point.
///
/// These tests exist to pin the honesty rules, not just the arithmetic. The
/// dangerous failure modes are a flag raised on absence of evidence, and a
/// weak attribution source (a filename, a beauty-filter tag) being allowed to
/// call a verdict wrong.
ProvenanceSnapshot _ai({String app = 'ChatGPT / DALL-E (OpenAI)'}) =>
    ProvenanceSnapshot(
      sourceApp: app,
      category: 'Generative AI',
      isAiGenerated: true,
      isCameraOriginal: false,
    );

ProvenanceSnapshot _camera({String hardware = 'SAMSUNG'}) => ProvenanceSnapshot(
      sourceApp: 'SAMSUNG Camera Capture',
      category: 'Camera Hardware',
      isAiGenerated: false,
      isCameraOriginal: true,
      cameraHardware: hardware,
    );

ProvenanceSnapshot _silent() => const ProvenanceSnapshot(
      sourceApp: 'No Recognizable Metadata',
      category: 'Web / Social Media',
      isAiGenerated: false,
      isCameraOriginal: false,
    );

void main() {
  group('crossCheckOutcome — the two flaggable directions', () {
    test('AI signature called AUTHENTIC is False-Authentic', () {
      final flag = crossCheckOutcome(
        detectionResult: 'authentic',
        provenance: _ai(),
      );
      expect(flag, isNotNull);
      expect(flag!.outcome, AnalysisOutcome.falseNegative);
      expect(flag.outcome.uiTag, 'False-Authentic');
      // The evidence travels with the outcome: the badge cannot assert a
      // disagreement without naming what the file claimed.
      expect(flag.evidence, 'ChatGPT / DALL-E (OpenAI)');
    });

    test('camera tag called MANIPULATED is False-Manipulated', () {
      final flag = crossCheckOutcome(
        detectionResult: 'manipulated',
        provenance: _camera(),
      );
      expect(flag!.outcome, AnalysisOutcome.falsePositive);
      expect(flag.outcome.uiTag, 'False-Manipulated');
      expect(flag.evidence, 'SAMSUNG');
    });

    test('agreements resolve to a cell but are not disagreements', () {
      final caught = crossCheckOutcome(
        detectionResult: 'manipulated',
        provenance: _ai(),
      );
      expect(caught!.outcome, AnalysisOutcome.truePositive);
      expect(caught.outcome.isDisagreement, isFalse);

      final cleared = crossCheckOutcome(
        detectionResult: 'authentic',
        provenance: _camera(),
      );
      expect(cleared!.outcome, AnalysisOutcome.trueNegative);
      expect(cleared.outcome.isDisagreement, isFalse);
    });
  });

  group('crossCheckOutcome — what must never raise a flag', () {
    test('absent metadata is not evidence of anything', () {
      expect(
        crossCheckOutcome(
            detectionResult: 'authentic', provenance: _silent()),
        isNull,
      );
      expect(
        crossCheckOutcome(
            detectionResult: 'manipulated', provenance: _silent()),
        isNull,
      );
    });

    test('no snapshot at all resolves to nothing', () {
      expect(
        crossCheckOutcome(detectionResult: 'authentic', provenance: null),
        isNull,
      );
    });

    test('an error verdict has nothing to check', () {
      for (final verdict in [null, 'error', '']) {
        expect(
          crossCheckOutcome(
              detectionResult: verdict, provenance: _ai()),
          isNull,
          reason: 'verdict "$verdict" must not be scored',
        );
      }
    });

    test('filename-only attribution is too weak to call a verdict wrong', () {
      // The scanner labels this "weak attribution, not a verified origin":
      // renaming a file must not be able to move a result.
      expect(
        crossCheckOutcome(
          detectionResult: 'authentic',
          provenance: _ai(app: 'Midjourney (filename heuristic)'),
        ),
        isNull,
      );
    });

    test('a beauty filter on a real photo is not a manipulated face', () {
      expect(
        crossCheckOutcome(
          detectionResult: 'authentic',
          provenance: _ai(app: 'FaceApp (AI Face Filter)'),
        ),
        isNull,
      );
    });

    test('an AI flag outside the Generative AI category does not fire', () {
      expect(
        crossCheckOutcome(
          detectionResult: 'authentic',
          provenance: ProvenanceSnapshot(
            sourceApp: 'Adobe Photoshop',
            category: 'Image Editor',
            isAiGenerated: true,
            isCameraOriginal: false,
          ),
        ),
        isNull,
      );
    });

    test('generator evidence outranks a leftover camera tag', () {
      final both = crossCheckOutcome(
        detectionResult: 'authentic',
        provenance: ProvenanceSnapshot(
          sourceApp: 'ChatGPT / DALL-E (OpenAI)',
          category: 'Generative AI',
          isAiGenerated: true,
          isCameraOriginal: true,
          cameraHardware: 'CANON',
        ),
      );
      expect(both!.outcome, AnalysisOutcome.falseNegative);
      expect(both.evidence, isNot(contains('CANON')));
    });
  });

  group('wording', () {
    test('a disagreement names both sources and the limit of the evidence', () {
      final fn = crossCheckOutcome(
          detectionResult: 'authentic', provenance: _ai())!;
      final fnText = fn.outcome.sentence('AUTHENTIC', fn.evidence);
      expect(fnText, contains('ChatGPT / DALL-E (OpenAI)'));
      expect(fnText, contains('AUTHENTIC'));
      expect(fnText, contains('out of distribution'));
      expect(fnText, contains('False Negative'));

      final fp = crossCheckOutcome(
          detectionResult: 'manipulated', provenance: _camera())!;
      final fpText = fp.outcome.sentence('MANIPULATED', fp.evidence);
      // The camera direction is weaker evidence and must say so on its face.
      expect(fpText, contains('not the scene it depicts'));
      expect(fpText, contains('review'));
    });

    test('short codes match the formal terms the results chapter uses', () {
      expect(AnalysisOutcome.falsePositive.shortCode, 'FP');
      expect(AnalysisOutcome.falsePositive.formalTerm, 'False Positive');
      expect(AnalysisOutcome.falseNegative.shortCode, 'FN');
      expect(AnalysisOutcome.falseNegative.formalTerm, 'False Negative');
    });
  });

  group('HistoryEntry', () {
    HistoryEntry entryWith(ProvenanceSnapshot? snap) => HistoryEntry(
          id: 'e1',
          mediaType: 'image',
          detectionResult: 'authentic',
          confidence: 0.9,
          timestamp: DateTime.utc(2026, 10, 26),
          provenance: snap,
        );

    test('outcome is derived from the persisted snapshot, not stored', () {
      final entry = entryWith(_ai());
      expect(entry.outcome, AnalysisOutcome.falseNegative);
      expect(entry.outcomeFlag?.evidence, 'ChatGPT / DALL-E (OpenAI)');
      expect(entryWith(_silent()).outcome, isNull);
    });

    test('survives a JSON round trip and keeps deriving offline', () {
      final restored =
          HistoryEntry.fromJson(entryWith(_camera()).toJson());
      expect(restored.outcome, AnalysisOutcome.trueNegative);
    });

    test('a backup from the self-declaration build still parses', () {
      // That field is gone; unknown keys must be ignored rather than thrown on,
      // or one legacy backup would make a whole history list fail to open.
      final restored = HistoryEntry.fromJson({
        'id': 'legacy',
        'mediaType': 'image',
        'detectionResult': 'authentic',
        'confidence': 0.4,
        'timestamp': DateTime.utc(2026, 10, 1).toIso8601String(),
        'declaredTruth': 'manipulated',
        'declaredTruthSource': 'user',
      });
      expect(restored.id, 'legacy');
      expect(restored.outcome, isNull);
    });

    test('a provenance write-back cannot lose the record\'s other fields', () {
      final entry = entryWith(null);
      final updated = entry.copyWith(provenance: _ai());
      expect(updated.detectionResult, entry.detectionResult);
      expect(updated.confidence, entry.confidence);
      expect(updated.outcome, AnalysisOutcome.falseNegative);
    });
  });

  group('OutcomeTally', () {
    test('counts each cell and ignores unevidenced records', () {
      final tally = OutcomeTally.from([
        AnalysisOutcome.falseNegative,
        AnalysisOutcome.falseNegative,
        AnalysisOutcome.truePositive,
        null,
        null,
      ]);
      expect(tally.falseNegative, 2);
      expect(tally.truePositive, 1);
      expect(tally.trueNegative, 0);
      expect(tally.evidenced, 3, reason: 'the two nulls are not a denominator');
      expect(OutcomeTally.from([null]).isEmpty, isTrue);
    });
  });

  group('OutcomeFlagBanner widget', () {
    Future<void> pump(WidgetTester tester, Widget banner) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: Column(children: [banner])),
          ),
        ));

    testWidgets('renders the disagreement and the evidence behind it',
        (tester) async {
      await pump(
        tester,
        OutcomeFlagBanner(
          entryId: 'e1',
          detectionResult: 'authentic',
          snapshot: _ai(),
        ),
      );
      expect(find.text('FALSE-AUTHENTIC'), findsOneWidget);
      expect(find.text('False Negative'), findsOneWidget);
      expect(find.textContaining('ChatGPT / DALL-E (OpenAI)'), findsOneWidget);
      expect(find.text('PROVENANCE CROSS-CHECK · AUTOMATIC'), findsOneWidget);
    });

    testWidgets('says nothing when the evidence agrees with the verdict',
        (tester) async {
      await pump(
        tester,
        OutcomeFlagBanner(
          entryId: 'e1',
          detectionResult: 'manipulated',
          snapshot: _ai(),
        ),
      );
      expect(find.text('FALSE-AUTHENTIC'), findsNothing);
      expect(find.text('FALSE-MANIPULATED'), findsNothing);
      expect(find.text('PROVENANCE CROSS-CHECK · AUTOMATIC'), findsNothing);
    });

    testWidgets('says nothing when the file carried no evidence',
        (tester) async {
      await pump(
        tester,
        OutcomeFlagBanner(
          entryId: 'e1',
          detectionResult: 'authentic',
          snapshot: _silent(),
        ),
      );
      expect(find.textContaining('FALSE-'), findsNothing);
    });

    testWidgets('an unsaved, error verdict renders no flag', (tester) async {
      await pump(
        tester,
        const OutcomeFlagBanner(
          entryId: null,
          detectionResult: null,
        ),
      );
      expect(find.textContaining('FALSE-'), findsNothing);
    });
  });
}
