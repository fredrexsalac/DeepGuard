import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'analysis_framing.dart';
import 'analysis_outcome.dart';
import 'gradcam_evidence.dart';
import 'provenance_snapshot.dart';

/// A single analysis result saved to a user profile's history.
class HistoryEntry {
  final String id;
  final String? filePath;
  final String? originalFileName;
  final String mediaType; // 'image' or 'video'
  final String? detectionResult; // 'authentic' or 'manipulated' or null
  final double confidence;
  final DateTime timestamp;

  /// Frozen provenance + source-trace snapshot captured at analysis time, so a
  /// history record can be replayed OFFLINE (like a screenshot). Null for
  /// legacy entries saved before this feature.
  final ProvenanceSnapshot? provenance;

  /// What the classifier was actually shown — face box and analysed square.
  final AnalysisFraming? framing;

  /// Real model-prescribed Grad-CAM attribution saved with this result.
  final GradCamEvidence? gradCam;

  const HistoryEntry({
    required this.id,
    this.filePath,
    this.originalFileName,
    required this.mediaType,
    this.detectionResult,
    required this.confidence,
    required this.timestamp,
    this.provenance,
    this.framing,
    this.gradCam,
  });

  OutcomeFlag? get outcomeFlag => crossCheckOutcome(
        detectionResult: detectionResult,
        provenance: provenance,
      );

  AnalysisOutcome? get outcome => outcomeFlag?.outcome;

  HistoryEntry copyWith({
    String? filePath,
    String? originalFileName,
    ProvenanceSnapshot? provenance,
    AnalysisFraming? framing,
    GradCamEvidence? gradCam,
  }) =>
      HistoryEntry(
        id: id,
        filePath: filePath ?? this.filePath,
        originalFileName: originalFileName ?? this.originalFileName,
        mediaType: mediaType,
        detectionResult: detectionResult,
        confidence: confidence,
        timestamp: timestamp,
        provenance: provenance ?? this.provenance,
        framing: framing ?? this.framing,
        gradCam: gradCam ?? this.gradCam,
      );

  // ── Derived helpers ────────────────────────────────────────────────────────

  String get fileName {
    if (originalFileName != null && originalFileName!.trim().isNotEmpty) {
      return originalFileName!.trim();
    }
    if (filePath == null || filePath!.trim().isEmpty) return 'Unknown file';
    final normalized = filePath!.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? 'Unknown file' : name;
  }

  bool get isImage => mediaType == 'image';
  bool get isFake => detectionResult == 'manipulated';
  bool get fileExists => filePath != null && File(filePath!).existsSync();

  double get confidencePercent => (confidence * 100).clamp(0.0, 100.0);

  /// User-facing classification label: REAL or A.I.
  String get resultLabel {
    if (detectionResult == null) return 'Unknown';
    return isFake ? 'A.I.' : 'REAL';
  }

  Color get resultColor =>
      isFake ? DeepGuardColors.fake : DeepGuardColors.authentic;

  Color get resultTextColor =>
      isFake ? DeepGuardColors.fakeText : DeepGuardColors.authenticText;

  Color resultColorFor(DeepGuardPalette palette) {
    if (detectionResult == null) return palette.textMuted;
    return isFake ? palette.aiClassification : palette.realClassification;
  }

  Color resultTextColorFor(DeepGuardPalette palette) {
    if (detectionResult == null) return palette.textMuted;
    return isFake ? palette.aiText : palette.realText;
  }

  Color resultContainerFor(DeepGuardPalette palette) {
    if (detectionResult == null) return palette.surfaceElevated;
    return isFake ? palette.aiContainer : palette.realContainer;
  }

  IconData get resultIcon =>
      isFake ? Icons.warning_amber_rounded : Icons.verified_rounded;

  String get formattedDate {
    final d = timestamp;
    final month = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][d.month - 1];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$month ${d.day}, ${d.year} · $h:$m';
  }

  // ── Serialisation (100% backward-compatible) ───────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        if (originalFileName != null) 'originalFileName': originalFileName,
        'mediaType': mediaType,
        'detectionResult': detectionResult,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        'provenance': provenance?.toJson(),
        'framing': framing?.toJson(),
        if (gradCam != null) 'gradCam': gradCam!.toJson(),
      };

  static AnalysisFraming? _framingFrom(Object? raw) {
    if (raw is Map<String, dynamic>) return AnalysisFraming.fromJson(raw);
    if (raw is Map) {
      return AnalysisFraming.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static GradCamEvidence? _gradCamFrom(Object? raw) {
    if (raw is Map<String, dynamic>) return GradCamEvidence.fromJson(raw);
    if (raw is Map) {
      return GradCamEvidence.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: json['filePath'] as String?,
        originalFileName: json['originalFileName'] as String?,
        mediaType: json['mediaType'] as String? ?? 'image',
        detectionResult: json['detectionResult'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        timestamp: json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now())
            : DateTime.now(),
        provenance: json['provenance'] is Map<String, dynamic>
            ? ProvenanceSnapshot.fromJson(
                json['provenance'] as Map<String, dynamic>)
            : (json['provenance'] is Map
                ? ProvenanceSnapshot.fromJson(
                    Map<String, dynamic>.from(json['provenance'] as Map))
                : null),
        framing: _framingFrom(json['framing']),
        gradCam: _gradCamFrom(json['gradCam']),
      );
}
