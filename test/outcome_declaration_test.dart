import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepfake_flutter_app/models/analysis_outcome.dart';
import 'package:deepfake_flutter_app/models/history_entry.dart';
import 'package:deepfake_flutter_app/models/provenance_snapshot.dart';
import 'package:deepfake_flutter_app/widgets/outcome_declaration.dart';

/// Tests for the self-reported outcome ledger.
///
/// The whole feature rests on one property: an outcome may exist ONLY where a
/// human declared a truth. These tests pin the four-way mapping, the wording
/// the user asked for, and the three ways it could silently go wrong —
/// inventing an outcome for an unannotated record, losing a declaration to a
/// later write-back, and presenting the tally as a model metric.
void main() {
  group('resolveOutcome', () {
    test('real media called manipulated is a false positive', () {
      expect(
        resolveOutcome(
            detectionResult: 'manipulated', declaredTruth: 'authentic'),
        AnalysisOutcome.falsePositive,
      );
    });

    test('fake media called authentic is a false negative', () {
      expect(
        resolveOutcome(
            detectionResult: 'authentic', declaredTruth: 'manipulated'),
        AnalysisOutcome.falseNegative,
      );
    });

    test('agreements resolve to true positive and true negative', () {
      expect(
        resolveOutcome(
            detectionResult: 'manipulated', declaredTruth: 'manipulated'),
        AnalysisOutcome.truePositive,
      );
      expect(
        resolveOutcome(
            detectionResult: 'authentic', declaredTruth: 'authentic'),
        AnalysisOutcome.trueNegative,
      );
    });

    test('no declaration means no outcome — never a guess', () {
      expect(
        resolveOutcome(detectionResult: 'manipulated', declaredTruth: null),
        isNull,
      );
      expect(
        resolveOutcome(detectionResult: 'authentic', declaredTruth: 'garbage'),
        isNull,
      );
    });

    test('an error verdict cannot be scored', () {
      expect(
        resolveOutcome(detectionResult: null, declaredTruth: 'authentic'),
        isNull,
      );
    });
  });

  group('wording', () {
    test('the user-facing tags read as the user asked', () {
      expect(AnalysisOutcome.falsePositive.uiTag, 'False-Manipulated');
      expect(AnalysisOutcome.falseNegative.uiTag, 'False-Authentic');
      expect(AnalysisOutcome.falsePositive.shortCode, 'FP');
      expect(AnalysisOutcome.falseNegative.shortCode, 'FN');
    });

    test('the sentence names both inputs so it cannot be read as the model',
        () {
      final text =
          AnalysisOutcome.falsePositive.sentence('MANIPULATED');
      expect(text, contains('You declared'));
      expect(text, contains('False Positive'));
      expect(AnalysisOutcome.falseNegative.isDisagreement, isTrue);
      expect(AnalysisOutcome.trueNegative.isDisagreement, isFalse);
    });
  });

  group('HistoryEntry persistence', () {
    test('declaredTruth survives a JSON round trip', () {
      final entry = HistoryEntry(
        id: 'e1',
        mediaType: 'image',
        detectionResult: 'manipulated',
        confidence: 0.9604,
        timestamp: DateTime.utc(2026, 10, 25),
        declaredTruth: 'authentic',
      );
      final restored = HistoryEntry.fromJson(entry.toJson());
      expect(restored.declaredTruth, 'authentic');
      expect(restored.outcome, AnalysisOutcome.falsePositive);
    });

    test('a legacy record with no such key decodes unannotated', () {
      final legacy = HistoryEntry.fromJson({
        'id': 'old',
        'mediaType': 'image',
        'detectionResult': 'authentic',
        'confidence': 0.99,
        'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      expect(legacy.declaredTruth, isNull);
      expect(legacy.outcome, isNull);
    });

    test('a later provenance write-back must not erase a declaration', () {
      // copyWith is how the source trace persists after it settles. If it
      // dropped declaredTruth, an annotation would vanish without the user
      // doing anything.
      final entry = HistoryEntry(
        id: 'e2',
        mediaType: 'image',
        detectionResult: 'authentic',
        confidence: 0.9,
        timestamp: DateTime.utc(2026, 10, 25),
        declaredTruth: 'manipulated',
      );
      expect(entry.copyWith().declaredTruth, 'manipulated');
      expect(entry.copyWith().outcome, AnalysisOutcome.falseNegative);
    });
  });

  group('OutcomeTally', () {
    test('counts each bucket and ignores unannotated records', () {
      final tally = OutcomeTally.from(const [
        AnalysisOutcome.truePositive,
        AnalysisOutcome.falsePositive,
        AnalysisOutcome.falsePositive,
        AnalysisOutcome.falseNegative,
        null,
        null,
      ]);
      expect(tally.truePositive, 1);
      expect(tally.falsePositive, 2);
      expect(tally.falseNegative, 1);
      expect(tally.trueNegative, 0);
      // The denominator is annotated records, never the full history.
      expect(tally.annotated, 4);
      expect(tally.isEmpty, isFalse);
    });

    test('an all-null set is empty rather than a zero-accuracy result', () {
      expect(OutcomeTally.from(const [null, null]).isEmpty, isTrue);
    });
  });

  group('autoTruthFromProvenance', () {
    ProvenanceSnapshot snap({
      String app = 'ChatGPT / DALL-E (OpenAI)',
      String category = 'Generative AI',
      bool ai = true,
    }) =>
        ProvenanceSnapshot(
          sourceApp: app,
          category: category,
          isAiGenerated: ai,
          isCameraOriginal: false,
        );

    test('in-file generator signature plus AUTHENTIC derives the miss', () {
      expect(autoTruthFromProvenance(snap(), 'authentic'), 'manipulated');
    });

    test('a MANIPULATED verdict agrees with the signature, so nothing is derived',
        () {
      expect(autoTruthFromProvenance(snap(), 'manipulated'), isNull);
    });

    test('attribution from the file NAME alone must never move a result', () {
      expect(
        autoTruthFromProvenance(
            snap(app: 'Midjourney (filename heuristic)'), 'authentic'),
        isNull,
      );
    });

    test('a beauty filter on a real photo is not a manipulated face', () {
      expect(
        autoTruthFromProvenance(snap(app: 'FaceApp (AI Face Filter)'),
            'authentic'),
        isNull,
      );
    });

    test('no generative signature, nothing derived', () {
      expect(
        autoTruthFromProvenance(
            snap(ai: false, category: 'Web / Social Media'), 'authentic'),
        isNull,
      );
    });

    test('an error verdict is never derived against', () {
      expect(autoTruthFromProvenance(snap(), null), isNull);
    });

    test('the derived declaration lands as a false negative, tagged as derived',
        () {
      final truth = autoTruthFromProvenance(snap(), 'authentic');
      expect(
        resolveOutcome(detectionResult: 'authentic', declaredTruth: truth),
        AnalysisOutcome.falseNegative,
      );
      final entry = HistoryEntry(
        id: 'auto-1',
        mediaType: 'image',
        detectionResult: 'authentic',
        confidence: 0.99,
        timestamp: DateTime.utc(2026, 10, 25),
        declaredTruth: truth,
        declaredTruthSource: DeclaredTruthSource.autoProvenance,
      );
      final restored = HistoryEntry.fromJson(entry.toJson());
      expect(restored.declaredTruthSource, 'auto-provenance');
      expect(restored.outcome, AnalysisOutcome.falseNegative);
    });

    test('a declaration from an earlier build with no source reads as human',
        () {
      final restored = HistoryEntry.fromJson({
        'id': 'old-1',
        'mediaType': 'image',
        'detectionResult': 'manipulated',
        'confidence': 0.9,
        'timestamp': DateTime.utc(2026, 10, 25).toIso8601String(),
        'declaredTruth': 'authentic',
      });
      expect(restored.declaredTruthSource, DeclaredTruthSource.user);
    });
  });

  group('OutcomeDeclarationSection', () {
    testWidgets('offers the question but no answer before a tap', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OutcomeDeclarationSection(
            entryId: 'live-1',
            detectionResult: 'manipulated',
          ),
        ),
      ));
      expect(find.text('Actually authentic'), findsOneWidget);
      expect(find.text('Actually manipulated'), findsOneWidget);
      // Nothing may resemble a verdict on the verdict before the user speaks.
      expect(find.textContaining('False-Manipulated'), findsNothing);
      expect(find.textContaining('False Positive'), findsNothing);
    });

    testWidgets('an existing declaration replays as its own badge',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OutcomeDeclarationSection(
            entryId: 'hist-1',
            detectionResult: 'manipulated',
            initialDeclaredTruth: 'authentic',
          ),
        ),
      ));
      expect(find.text('FALSE-MANIPULATED'), findsOneWidget);
      expect(find.text('False Positive'), findsOneWidget);
    });

    testWidgets('a declaration that cannot be stored is reported as unstored',
        (tester) async {
      // No SharedPreferences initialisation here, so ProfileService has no
      // profiles and the write cannot succeed. The section must say so rather
      // than show a badge that implies the record was annotated.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OutcomeDeclarationSection(
              entryId: 'live-2',
              detectionResult: 'authentic',
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Actually manipulated'));
      await tester.pump();
      expect(find.textContaining('Not saved'), findsOneWidget);
      expect(find.text('FALSE-AUTHENTIC'), findsNothing);
    });

    testWidgets('an error verdict shows nothing to score', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: OutcomeDeclarationSection(
            entryId: 'err-1',
            detectionResult: null,
          ),
        ),
      ));
      expect(find.text('Actually authentic'), findsNothing);
      expect(find.text('YOUR ASSESSMENT · SELF-REPORTED'), findsNothing);
    });
  });
}
