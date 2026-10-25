import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'analysis_framing.dart';
import 'analysis_outcome.dart';
import 'provenance_snapshot.dart';

/// A single analysis result saved to a user profile's history.
class HistoryEntry {
  final String id;
  final String? filePath;
  final String mediaType;       // 'image' or 'video'
  final String? detectionResult; // 'authentic' or 'manipulated' or null
  final double confidence;
  final DateTime timestamp;

  /// Frozen provenance + source-trace snapshot captured at analysis time, so a
  /// history record can be replayed OFFLINE (like a screenshot). Null for
  /// legacy entries saved before this feature.
  final ProvenanceSnapshot? provenance;

  /// What the classifier was actually shown — face box and analysed square.
  /// Persisted for the same reason as [provenance]: a replayed record has to
  /// still be able to say whether its verdict came from a tight face crop or
  /// from a whole wide frame. Null for legacy entries and for video.
  final AnalysisFraming? framing;

  /// What the USER declared this media actually is — 'authentic' or
  /// 'manipulated', or null when unannotated. This is the second axis the
  /// verdict needs and cannot supply itself: without it, a false positive is
  /// indistinguishable from a true negative inside the app. Self-reported, so
  /// it is never a model metric and never merged with the benchmark figures.
  final String? declaredTruth;

  /// Who made that declaration — [DeclaredTruthSource.user] or
  /// [DeclaredTruthSource.autoProvenance]. No screen prints it; it exists so
  /// the two kinds can be separated in analysis instead of silently merged.
  final String? declaredTruthSource;

  const HistoryEntry({
    required this.id,
    this.filePath,
    required this.mediaType,
    this.detectionResult,
    required this.confidence,
    required this.timestamp,
    this.provenance,
    this.framing,
    this.declaredTruth,
    this.declaredTruthSource,
  });

  /// The confusion-matrix position of this record, or null while either axis
  /// is missing. Derived, never stored: one source of truth for the mapping.
  AnalysisOutcome? get outcome => resolveOutcome(
        detectionResult: detectionResult,
        declaredTruth: declaredTruth,
      );

  /// Returns a copy with optional overridden fields (used to attach a provenance
  /// snapshot after the live source trace settles).
  ///
  /// [declaredTruth] must be carried through here even when untouched: a
  /// provenance write-back that rebuilt the record without it would silently
  /// erase an annotation the user already made.
  HistoryEntry copyWith({
    ProvenanceSnapshot? provenance,
    AnalysisFraming? framing,
    String? declaredTruth,
    String? declaredTruthSource,
  }) =>
      HistoryEntry(
        id: id,
        filePath: filePath,
        mediaType: mediaType,
        detectionResult: detectionResult,
        confidence: confidence,
        timestamp: timestamp,
        provenance: provenance ?? this.provenance,
        framing: framing ?? this.framing,
        declaredTruth: declaredTruth ?? this.declaredTruth,
        declaredTruthSource:
            declaredTruthSource ?? this.declaredTruthSource,
      );

  // ── Derived helpers ────────────────────────────────────────────────────────

  String get fileName {
    if (filePath == null || filePath!.trim().isEmpty) return 'Unknown file';
    final normalized = filePath!.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? 'Unknown file' : name;
  }

  bool get isImage => mediaType == 'image';
  bool get isFake => detectionResult == 'manipulated';
  bool get fileExists => filePath != null && File(filePath!).existsSync();

  double get confidencePercent => (confidence * 100).clamp(0.0, 100.0);

  String get resultLabel {
    if (detectionResult == null) return 'Unknown';
    return isFake ? 'FAKE' : 'REAL';
  }

  Color get resultColor =>
      isFake ? DeepGuardColors.fake : DeepGuardColors.authentic;

  IconData get resultIcon =>
      isFake ? Icons.warning_amber_rounded : Icons.verified;

  String get formattedDate {
    final d = timestamp;
    final month = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ][d.month - 1];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$month ${d.day}, ${d.year}  $h:$m';
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'mediaType': mediaType,
        'detectionResult': detectionResult,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        'provenance': provenance?.toJson(),
        'framing': framing?.toJson(),
        'declaredTruth': declaredTruth,
        'declaredTruthSource': declaredTruthSource,
      };

  /// Same tolerant decode as [provenance]: decoded JSON is not always a
  /// `Map<String, dynamic>` at rest, and a record must never fail to open
  /// because one nested map came back loosely typed.
  static AnalysisFraming? _framingFrom(Object? raw) {
    if (raw is Map<String, dynamic>) return AnalysisFraming.fromJson(raw);
    if (raw is Map) return AnalysisFraming.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  static String? _sourceFrom(Map<String, dynamic> json, String? truth) {
    if (truth == null) return null;
    final raw = json['declaredTruthSource'];
    if (raw is String && raw.isNotEmpty) return raw;
    // A record saved by an earlier build carries a declaration but no source,
    // and the only way a declaration could exist then is a human tapping a
    // chip. Defaulting those to 'auto-provenance' would mislabel a person's
    // testimony as a machine inference.
    return DeclaredTruthSource.user;
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: json['filePath'] as String?,
        mediaType: json['mediaType'] as String? ?? 'image',
        detectionResult: json['detectionResult'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        timestamp: json['timestamp'] != null
            ? (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now())
            : DateTime.now(),
        provenance: json['provenance'] is Map<String, dynamic>
            ? ProvenanceSnapshot.fromJson(json['provenance'] as Map<String, dynamic>)
            : (json['provenance'] is Map
                ? ProvenanceSnapshot.fromJson(
                    Map<String, dynamic>.from(json['provenance'] as Map))
                : null),
        framing: _framingFrom(json['framing']),
        declaredTruth: _truthFrom(json),
        declaredTruthSource: _sourceFrom(json, _truthFrom(json)),
      );

  static String? _truthFrom(Map<String, dynamic> json) =>
      DeclaredTruth.parse(json['declaredTruth'])?.storageValue;
}
