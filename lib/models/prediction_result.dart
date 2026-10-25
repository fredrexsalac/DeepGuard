import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'analysis_framing.dart';

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

  PredictionResult({
    required this.id,
    this.filePath,
    required this.mediaType,
    this.status = PredictionStatus.pending,
    this.result,
    this.confidence = 0.0,
    this.errorMessage,
    this.framing,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  double get confidencePercentage => confidence * 100;

  String get resultLabel {
    if (result == null) return 'Pending';
    return result == DetectionResult.authentic ? 'Authentic' : 'Manipulated';
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

  IconData get resultIcon {
    if (status == PredictionStatus.processing) return Icons.hourglass_top;
    if (status == PredictionStatus.error) return Icons.error_outline;
    if (result == null) return Icons.help_outline;
    return result == DetectionResult.authentic
        ? Icons.verified
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
      timestamp: timestamp ?? this.timestamp,
    );
  }
}