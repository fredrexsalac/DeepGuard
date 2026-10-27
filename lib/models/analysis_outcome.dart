/// Provenance cross-check
///
/// The confusion-matrix position of ONE saved verdict, derived from evidence
/// the app already holds and the classifier did not use: the file's own
/// embedded provenance.
///
/// WHY THIS EXISTS
/// [HistoryEntry] carries the model's side of the story — 'authentic' or
/// 'manipulated' — and nothing else. A miss is therefore invisible from inside
/// the app, because the classifier's own output is the only knowledge it has,
/// and comparing a claim against itself proves nothing. What is missing is not
/// a calculation but a second, independent input. The provenance scanner
/// supplies one: it reads generator fingerprints and camera tags out of the
/// file bytes, on a code path that never touches inference. Where that
/// evidence contradicts the verdict, the disagreement can be stated without
/// asking anyone.
///
/// WHAT THIS IS NOT
///   - Not a model metric. These counts rest on embedded metadata, which is
///     ATTRIBUTION, not verification: a generator name in a header says which
///     tool wrote the file. The benchmark figures (Image 84.82% / Video 71.67%)
///     come from the held-out test set and are never recomputed from here; the
///     two must never be presented as the same number.
///   - Not a guess from absence. Most files carry no readable metadata at all,
///     and stripped EXIF is normal for screenshots, messenger downloads and
///     re-encoded images. No evidence resolves to null, which renders nothing.
///     A record is only ever counted here when the file positively stated
///     something.
///   - Not a correction. Flagging a verdict can never change the verdict, the
///     confidence or the model class shown above it.
///   - Not a claim about the picture's content. A camera tag identifies the
///     hardware that wrote a file, not the scene it depicts — a photograph of
///     a monitor carrying an AI image has an equally genuine sensor tag. That
///     limit is printed with the flag, never filed away in a comment.
library;

import 'provenance_snapshot.dart';

/// Where a verdict sits against the file's own evidence.
enum AnalysisOutcome {
  truePositive,
  trueNegative,
  falsePositive,
  falseNegative,
}

/// A cross-check result: the confusion-matrix cell, plus the evidence string
/// that put it there. The evidence travels with the outcome so no screen can
/// render "False-Authentic" as a bare assertion — the badge has to say what
/// the file claimed.
class OutcomeFlag {
  final AnalysisOutcome outcome;

  /// The attributed tool or hardware, verbatim from the scanner
  /// (e.g. 'ChatGPT / DALL-E (OpenAI)' or 'SAMSUNG Camera Capture').
  final String evidence;

  const OutcomeFlag(this.outcome, this.evidence);
}

/// Vendor attribution the cross-check is willing to act on, or null.
///
/// EXCLUSIONS, and why each one matters:
///   - `…​(filename heuristic)` — attribution inferred from the file NAME alone,
///     which the scanner itself labels "weak attribution, not a verified
///     origin". Anyone renaming a file must not be able to move a result.
///   - `FaceApp (AI Face Filter)` — a real in-file signature, but a beauty
///     filter on a real photograph is not a manipulated face within this
///     project's Real/Fake taxonomy, so calling an AUTHENTIC verdict wrong
///     there would overstate what the evidence supports.
String? _generatorEvidence(ProvenanceSnapshot p) {
  if (!p.isAiGenerated) return null;
  if (p.category != 'Generative AI') return null;
  final app = p.sourceApp;
  if (app.contains('filename heuristic')) return null;
  if (app == 'FaceApp (AI Face Filter)') return null;
  return app;
}

/// Physical-capture attribution, or null. Only counts when no generator
/// signature is present, so an AI file with a leftover camera tag can never
/// produce contradictory evidence in the same record.
String? _cameraEvidence(ProvenanceSnapshot p) {
  if (!p.isCameraOriginal || p.isAiGenerated) return null;
  return p.cameraHardware ?? p.sourceApp;
}

/// Cross-checks one saved verdict against the file's provenance.
///
/// Returns null when the file stated nothing usable, when the verdict is an
/// error, or when media provenance is absent — the majority of records, and
/// correctly so.
OutcomeFlag? crossCheckOutcome({
  String? detectionResult,
  ProvenanceSnapshot? provenance,
}) {
  final p = provenance;
  if (p == null) return null;
  final verdictIsFake = detectionResult == 'manipulated';
  final verdictIsReal = detectionResult == 'authentic';
  if (!verdictIsFake && !verdictIsReal) return null;

  final generator = _generatorEvidence(p);
  if (generator != null) {
    // AI-generated media called AUTHENTIC is the documented scope gap: the
    // model learned GAN artefacts, so diffusion output is out of distribution
    // and reads authentic. Called MANIPULATED, the two sources agree.
    return OutcomeFlag(
      verdictIsFake ? AnalysisOutcome.truePositive : AnalysisOutcome.falseNegative,
      generator,
    );
  }

  final camera = _cameraEvidence(p);
  if (camera != null) {
    // A camera-tagged file called MANIPULATED is the other direction: the
    // evidence says an ordinary device wrote it, the classifier says a face was
    // synthesised. Weaker than the generator case, and labelled as such.
    return OutcomeFlag(
      verdictIsReal ? AnalysisOutcome.trueNegative : AnalysisOutcome.falsePositive,
      camera,
    );
  }

  return null;
}

extension AnalysisOutcomeInfo on AnalysisOutcome {
  /// True when the file's evidence and the classifier disagree.
  bool get isDisagreement =>
      this == AnalysisOutcome.falsePositive ||
      this == AnalysisOutcome.falseNegative;

  /// Two-letter code for the compact history tile.
  String get shortCode => switch (this) {
        AnalysisOutcome.truePositive => 'TP',
        AnalysisOutcome.trueNegative => 'TN',
        AnalysisOutcome.falsePositive => 'FP',
        AnalysisOutcome.falseNegative => 'FN',
      };

  /// The formal term for anyone cross-referencing the results chapter.
  String get formalTerm => switch (this) {
        AnalysisOutcome.truePositive => 'True Positive',
        AnalysisOutcome.trueNegative => 'True Negative',
        AnalysisOutcome.falsePositive => 'False Positive',
        AnalysisOutcome.falseNegative => 'False Negative',
      };

  /// The lay-user tag. The "False-" prefix modifies the verdict on screen, so
  /// 'False-Manipulated' means the MANIPULATED label is the one in question.
  String get uiTag => switch (this) {
        AnalysisOutcome.truePositive => 'Verdict agreed',
        AnalysisOutcome.trueNegative => 'Verdict agreed',
        AnalysisOutcome.falsePositive => 'False-Manipulated',
        AnalysisOutcome.falseNegative => 'False-Authentic',
      };

  /// Says both inputs out loud, so the badge can never be mistaken for a
  /// second opinion from the classifier. It is a report of two sources that
  /// do not agree, named one at a time.
  String sentence(String verdictLabel, String evidence) => switch (this) {
        AnalysisOutcome.truePositive =>
          'File evidence attributes this media to $evidence, and the '
              'classifier returned $verdictLabel. The two agree. $formalTerm.',
        AnalysisOutcome.trueNegative =>
          'EXIF attributes this file to a physical camera capture ($evidence) '
              'with no generator signature, and the classifier returned '
              '$verdictLabel. The two agree. $formalTerm.',
        AnalysisOutcome.falseNegative =>
          'File evidence attributes this media to $evidence, yet the '
              'classifier returned $verdictLabel. The model was trained on '
              'GAN artefacts, so this generator is out of distribution and '
              'reads authentic. $formalTerm.',
        AnalysisOutcome.falsePositive =>
          'EXIF attributes this file to a physical camera capture ($evidence) '
              'with no generator signature, yet the classifier returned '
              '$verdictLabel. A sensor tag names the device that wrote the '
              'file, not the scene it depicts, so this is a disagreement to '
              'review rather than a proven error. $formalTerm.',
      };
}

/// Tallies cross-checked outcomes across saved records.
class OutcomeTally {
  final int truePositive;
  final int trueNegative;
  final int falsePositive;
  final int falseNegative;

  const OutcomeTally({
    this.truePositive = 0,
    this.trueNegative = 0,
    this.falsePositive = 0,
    this.falseNegative = 0,
  });

  /// Records that carried usable file evidence — the denominator for anything
  /// computed here, and deliberately NOT the benchmark's test-set size.
  int get evidenced =>
      truePositive + trueNegative + falsePositive + falseNegative;

  int get total => evidenced;

  bool get isEmpty => evidenced == 0;

  static OutcomeTally from(Iterable<dynamic> outcomes) {
    var tp = 0, tn = 0, fp = 0, fn = 0;
    for (final outcome in outcomes) {
      switch (outcome) {
        case AnalysisOutcome.truePositive:
          tp++;
        case AnalysisOutcome.trueNegative:
          tn++;
        case AnalysisOutcome.falsePositive:
          fp++;
        case AnalysisOutcome.falseNegative:
          fn++;
        default:
          break;
      }
    }
    return OutcomeTally(
        truePositive: tp, trueNegative: tn, falsePositive: fp,
        falseNegative: fn);
  }
}
