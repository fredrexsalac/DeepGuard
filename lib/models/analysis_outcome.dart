/// AnalysisOutcome
///
/// The confusion-matrix position of ONE saved verdict, computed only from a
/// truth that a human declared themselves.
///
/// WHY THIS EXISTS
/// [HistoryEntry] carries the model's side of the story — 'authentic' or
/// 'manipulated' — and nothing else. A false positive is therefore invisible
/// from inside the app: the classifier's own output is the only knowledge the
/// app holds, and comparing a claim against itself proves nothing. What is
/// missing is not a calculation but an input, namely a statement about what
/// the media actually is. Only a person can supply that, so this file turns a
/// person's statement into the standard four outcomes and nothing more.
///
/// WHAT THIS IS NOT
///   - Not a model metric. These counts are self-reported annotations made on
///     the phone. The benchmark figures (Image 84.82% / Video 71.67%) come from
///     the held-out test set and are never recomputed from here, and the two
///     must never be presented as the same number.
///   - Not automatic. Nothing in this file's mapping infers, suggests or
///     pre-fills a human declaration; an unannotated record resolves to null.
///     The one automatic path, [autoTruthFromProvenance], is a deliberate
///     exception requested for this project: it writes a declaration from an
///     in-file generator signature, and it records that fact in
///     [HistoryEntry.declaredTruthSource] so the two kinds never merge.
///   - Not a correction. Declaring a verdict wrong never changes the verdict,
///     the confidence, or the model class shown above it.
library;

import 'provenance_snapshot.dart';

/// Where a [HistoryEntry.declaredTruth] came from.
///
/// Kept in the data even though no screen prints it: a tally that mixes human
/// ground truth with machine-derived assertions cannot be filtered apart
/// afterwards, and the difference is exactly what a results chapter has to
/// state. Filter on this to report human-only or auto-only counts.
class DeclaredTruthSource {
  static const String user = 'user';
  static const String autoProvenance = 'auto-provenance';
}

/// The user's own statement about what the submitted media really is.
enum DeclaredTruth {
  authentic('authentic'),
  manipulated('manipulated');

  const DeclaredTruth(this.storageValue);

  /// Stored exactly like [HistoryEntry.detectionResult] — a bare string in
  /// JSON — so the two axes read the same way side by side.
  final String storageValue;

  /// Tolerant decode: a legacy record simply has no key, and a restored one may
  /// carry a loose value. Neither may throw, because one bad record must not
  /// make a whole history list fail to open.
  static DeclaredTruth? parse(Object? raw) {
    if (raw is DeclaredTruth) return raw;
    if (raw is! String) return null;
    for (final value in DeclaredTruth.values) {
      if (value.storageValue == raw) return value;
    }
    return null;
  }
}

/// Where a verdict sits against a declared truth.
enum AnalysisOutcome {
  truePositive,
  trueNegative,
  falsePositive,
  falseNegative,
}

/// Derives a declaration from the file's own provenance, for the one case where
/// the app holds independent evidence that the classifier is wrong: the media
/// carries an in-file Generative-AI signature and the verdict came back
/// AUTHENTIC. The model was trained on GAN artefacts, so diffusion output
/// (DALL·E, Midjourney, Stable Diffusion) is out of distribution and reads
/// authentic — a documented scope gap, not a code bug.
///
/// Returns the [DeclaredTruth.storageValue] to record, or null to leave the
/// record unannotated.
///
/// EXCLUSIONS, and why each one matters:
///   - `…​(filename heuristic)` — attribution inferred from the file NAME alone,
///     which the scanner itself labels "weak attribution, not a verified
///     origin". Anyone renaming a file must not be able to move a result.
///   - `FaceApp (AI Face Filter)` — an in-file signature, but a beauty filter on
///     a real photograph is not a manipulated face within this project's
///     Real/Fake taxonomy.
///   - An already-declared record is never recomputed here: the caller checks
///     first, so a human's word always wins over this rule.
String? autoTruthFromProvenance(
  ProvenanceSnapshot snapshot,
  String? detectionResult,
) {
  // Only a miss in the AUTHENTIC direction is evidenced. A MANIPULATED verdict
  // on AI-generated media agrees with the signature and needs no annotation.
  if (detectionResult != 'authentic') return null;
  if (!snapshot.isAiGenerated) return null;
  if (snapshot.category != 'Generative AI') return null;

  final app = snapshot.sourceApp;
  if (app.contains('filename heuristic')) return null;
  if (app == 'FaceApp (AI Face Filter)') return null;

  return DeclaredTruth.manipulated.storageValue;
}

/// Resolves the two axes. Returns null when either side is missing, so an
/// error verdict or an unannotated record can never be counted.
AnalysisOutcome? resolveOutcome({
  String? detectionResult,
  String? declaredTruth,
}) {
  final declared = DeclaredTruth.parse(declaredTruth);
  if (declared == null) return null;
  final verdictIsFake = detectionResult == 'manipulated';
  final verdictIsReal = detectionResult == 'authentic';
  if (!verdictIsFake && !verdictIsReal) return null;

  final truthIsFake = declared == DeclaredTruth.manipulated;
  if (verdictIsFake && truthIsFake) return AnalysisOutcome.truePositive;
  if (verdictIsReal && !truthIsFake) return AnalysisOutcome.trueNegative;
  if (verdictIsFake && !truthIsFake) return AnalysisOutcome.falsePositive;
  return AnalysisOutcome.falseNegative;
}

extension AnalysisOutcomeInfo on AnalysisOutcome {
  /// True when the model and the human disagree.
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
  /// 'False-Manipulated' means the MANIPULATED label was wrong.
  String get uiTag => switch (this) {
        AnalysisOutcome.truePositive => 'Verdict agreed',
        AnalysisOutcome.trueNegative => 'Verdict agreed',
        AnalysisOutcome.falsePositive => 'False-Manipulated',
        AnalysisOutcome.falseNegative => 'False-Authentic',
      };

  /// Says both inputs out loud, so the badge can never be read as a second
  /// opinion from the model rather than a record of what the user stated.
  String sentence(String verdictLabel) => switch (this) {
        AnalysisOutcome.truePositive =>
          'You declared this media manipulated, and the model said '
              '$verdictLabel. $formalTerm.',
        AnalysisOutcome.trueNegative =>
          'You declared this media authentic, and the model said '
              '$verdictLabel. $formalTerm.',
        AnalysisOutcome.falsePositive =>
          'You declared this media authentic, so the $verdictLabel verdict '
              'is wrong. $formalTerm.',
        AnalysisOutcome.falseNegative =>
          'You declared this media manipulated, so the $verdictLabel '
              'verdict is wrong. $formalTerm.',
      };
}

/// Tallies self-reported outcomes across saved records.
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

  /// Records annotated by the user — the denominator for anything computed
  /// here, and deliberately NOT the benchmark's test-set size.
  int get annotated =>
      truePositive + trueNegative + falsePositive + falseNegative;

  int get total => annotated;

  bool get isEmpty => annotated == 0;

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
        truePositive: tp, trueNegative: tn, falsePositive: fp, falseNegative: fn);
  }
}
