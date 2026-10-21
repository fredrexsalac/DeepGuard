import 'package:flutter/material.dart';

/// Internal class labels — mirrors the model/dataset terminology exactly.
/// Do NOT rename these to Authentic/Manipulated; that mapping is UI-only.
enum InternalLabel {
  /// Model class 0 — the media shows no signs of manipulation.
  real,

  /// Model class 1 — the media shows signs of deepfake manipulation.
  fake,
}

/// Maps the raw sigmoid probability scalar from a DeepGuard model into a
/// structured detection result.
///
/// Internal terminology (model/dataset):
///   0 = Real   (fakeProbability < 0.5)
///   1 = Fake   (fakeProbability >= 0.5)
///
/// User-facing terminology (Flutter UI):
///   Real  → AUTHENTIC
///   Fake  → MANIPULATED
class DeepGuardDetectionResult {
  /// Raw sigmoid output from the TFLite model in [0.0, 1.0].
  /// Represents the probability that the media is FAKE.
  final double fakeProbability;

  /// Internal model label (Real / Fake).
  final InternalLabel internalLabel;

  /// Confidence in the prediction — always the probability of the
  /// predicted class, so always >= 0.5 (unless model output is exactly 0.5).
  ///
  /// Real  → confidence = 1.0 − fakeProbability
  /// Fake  → confidence = fakeProbability
  final double confidence;

  /// Inference latency in milliseconds (wall-clock).
  final int latencyMs;

  // ── Derived display properties ─────────────────────────────────────────────

  /// Whether the predicted class is Fake → UI shows MANIPULATED.
  bool get isFake => internalLabel == InternalLabel.fake;

  /// Whether the predicted class is Real → UI shows AUTHENTIC.
  bool get isReal => internalLabel == InternalLabel.real;

  /// Internal class name as stored in labels.txt.
  ///
  /// Returns "Real" or "Fake" — do NOT use these as UI text.
  String get internalClassName => isFake ? 'Fake' : 'Real';

  /// User-facing display label (application terminology).
  ///
  /// Returns "AUTHENTIC" or "MANIPULATED".
  String get displayLabel => isFake ? 'MANIPULATED' : 'AUTHENTIC';

  /// Short description shown below the result label.
  String get displayDescription => isFake
      ? 'AI manipulation patterns detected'
      : 'No signs of manipulation detected';

  /// Confidence as a percentage string, e.g. "85.32%".
  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(2)}%';

  /// Whether the confidence is high enough to be considered reliable.
  bool get isHighConfidence => confidence >= 0.70;

  /// Whether the confidence is medium (40–70%).
  bool get isMediumConfidence => confidence >= 0.40 && confidence < 0.70;

  /// Whether the confidence is low (< 40%).
  bool get isLowConfidence => confidence < 0.40;

  /// Result colour for UI: green for authentic, red for manipulated.
  Color get resultColor =>
      isFake ? const Color(0xFFFF4444) : const Color(0xFF00E676);

  /// Result icon for UI.
  IconData get resultIcon =>
      isFake ? Icons.warning_amber_rounded : Icons.verified;

  // ── Constructor ────────────────────────────────────────────────────────────

  const DeepGuardDetectionResult({
    required this.fakeProbability,
    required this.internalLabel,
    required this.confidence,
    required this.latencyMs,
  });

  /// Constructs a result directly from the raw TFLite scalar output.
  ///
  /// [fakeProbability] must be clamped to [0.0, 1.0] before calling.
  factory DeepGuardDetectionResult.fromFakeProbability({
    required double fakeProbability,
    int latencyMs = 0,
  }) {
    final isFake = fakeProbability >= 0.5;
    final confidence = isFake ? fakeProbability : (1.0 - fakeProbability);
    return DeepGuardDetectionResult(
      fakeProbability: fakeProbability,
      internalLabel: isFake ? InternalLabel.fake : InternalLabel.real,
      confidence: confidence.clamp(0.0, 1.0),
      latencyMs: latencyMs,
    );
  }

  @override
  String toString() =>
      'DeepGuardDetectionResult('
      'internalLabel=$internalClassName, '
      'displayLabel=$displayLabel, '
      'confidence=$confidencePercent, '
      'fakeProbability=${fakeProbability.toStringAsFixed(4)}, '
      'latencyMs=${latencyMs}ms)';
}
