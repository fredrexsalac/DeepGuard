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

  const HistoryEntry({
    required this.id,
    this.filePath,
    required this.mediaType,
    this.detectionResult,
    required this.confidence,
    required this.timestamp,
    this.provenance,
    this.framing,
  });

  /// The verdict cross-checked against the file's own provenance, with the
  /// evidence that produced it. Null when the file stated nothing usable —
  /// which is most files, and is not itself a finding.
  ///
  /// Derived, never stored: recomputing it from the persisted snapshot means a
  /// record saved before this rule existed gets checked the moment it is
  /// opened, instead of staying unflagged forever.
  OutcomeFlag? get outcomeFlag => crossCheckOutcome(
        detectionResult: detectionResult,
        provenance: provenance,
      );

  /// The confusion-matrix cell alone, for tiles and tallies.
  AnalysisOutcome? get outcome => outcomeFlag?.outcome;

  /// Returns a copy with optional overridden fields (used to attach a provenance
  /// snapshot after the live source trace settles).
  HistoryEntry copyWith({
    ProvenanceSnapshot? provenance,
    AnalysisFraming? framing,
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

  /// The verdict colour with enough luminance to be read as words. `fake`
  /// measures 4.94:1 on the page background but only 4.04:1 on a card, so the
  /// red needs a lighter text variant. `authentic` clears 7.78:1 worst case
  /// and is returned as-is rather than brightened out of its own identity.
  Color get resultTextColor =>
      isFake ? DeepGuardColors.fakeText : DeepGuardColors.authentic;

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
      };

  /// Same tolerant decode as [provenance]: decoded JSON is not always a
  /// `Map<String, dynamic>` at rest, and a record must never fail to open
  /// because one nested map came back loosely typed.
  static AnalysisFraming? _framingFrom(Object? raw) {
    if (raw is Map<String, dynamic>) return AnalysisFraming.fromJson(raw);
    if (raw is Map) return AnalysisFraming.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Records restored from a backup written by the short-lived build that asked
  /// users to self-declare a verdict may still carry `declaredTruth` /
  /// `declaredTruthSource` keys. They are read by nobody and dropped on the
  /// next save: the outcome axis is derived from file evidence now, so a
  /// person's opinion is no longer an input the app accepts or stores.
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
      );
}
