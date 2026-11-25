import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'analysis_framing.dart';
import 'gradcam_evidence.dart';

enum MediaType { image, video }
enum PredictionStatus { pending, processing, completed, error }
enum DetectionResult { authentic, manipulated }

class PredictionResult {
  final String id;
  final String? filePath;
  final MediaType mediaType;
  final PredictionStatus status;
  final DetectionResult? result;
  final double confidence;
  final String? errorMessage;
  final DateTime timestamp;

  /// What the classifier was actually shown — the detected face and the square
  /// cropped and resized to 128x128. Null for video (the temporal branch runs
  /// on whole frames by design) and for legacy replays saved before framing was
  /// recorded. See [AnalysisFraming] for why the distinction matters.
  final AnalysisFraming? framing;

  /// Real model-prescribed Grad-CAM spatial attribution computed on-device.
  final GradCamEvidence? gradCam;

  PredictionResult({
    required this.id,
    this.filePath,
    required this.mediaType,
    this.status = PredictionStatus.pending,
    this.result,
    this.confidence = 0.0,
    this.errorMessage,
    this.framing,
    this.gradCam,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  double get confidencePercentage => confidence * 100;

  /// User-facing classification label: REAL or A.I.
  String get resultLabel {
    if (result == null) return 'Pending';
    return result == DetectionResult.authentic ? 'REAL' : 'A.I.';
  }

  /// Internal model/dataset class label (Real / Fake) preserved unchanged.
  String get internalClassLabel {
    if (result == null) return 'Unknown';
    return result == DetectionResult.authentic ? 'Real' : 'Fake';
  }

  bool get isHighConfidence => confidencePercentage >= 70;
  bool get isMediumConfidence =>
      confidencePercentage >= 40 && confidencePercentage < 70;

  Color get resultColor {
    if (result == null) return DeepGuardColors.textMuted;
    return result == DetectionResult.authentic
        ? DeepGuardColors.authentic
        : DeepGuardColors.fake;
  }

  Color get resultTextColor {
    if (result == null) return DeepGuardColors.textMuted;
    return result == DetectionResult.authentic
        ? DeepGuardColors.authenticText
        : DeepGuardColors.fakeText;
  }

  /// Theme-aware graphic/badge color for Light and Dark modes.
  Color resultColorFor(DeepGuardPalette palette) {
    if (result == null) return palette.textMuted;
    return result == DetectionResult.authentic
        ? palette.realClassification
        : palette.aiClassification;
  }

  /// Theme-aware normal-text color guaranteed >= 4.5:1 in Light and Dark modes.
  Color resultTextColorFor(DeepGuardPalette palette) {
    if (result == null) return palette.textMuted;
    return result == DetectionResult.authentic ? palette.realText : palette.aiText;
  }

  /// Theme-aware soft container background color for verdict cards/chips.
  Color resultContainerFor(DeepGuardPalette palette) {
    if (result == null) return palette.surfaceElevated;
    return result == DetectionResult.authentic
        ? palette.realContainer
        : palette.aiContainer;
  }

  IconData get resultIcon {
    if (status == PredictionStatus.processing) return Icons.hourglass_top_rounded;
    if (status == PredictionStatus.error) return Icons.error_outline_rounded;
    if (result == null) return Icons.help_outline_rounded;
    return result == DetectionResult.authentic
        ? Icons.verified_rounded
        : Icons.warning_amber_rounded;
  }

  PredictionResult copyWith({
    String? id,
    String? filePath,
    MediaType? mediaType,
    PredictionStatus? status,
    DetectionResult? result,
    double? confidence,
    String? errorMessage,
    AnalysisFraming? framing,
    GradCamEvidence? gradCam,
    DateTime? timestamp,
  }) {
    return PredictionResult(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      result: result ?? this.result,
      confidence: confidence ?? this.confidence,
      errorMessage: errorMessage ?? this.errorMessage,
      framing: framing ?? this.framing,
      gradCam: gradCam ?? this.gradCam,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
