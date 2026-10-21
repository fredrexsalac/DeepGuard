import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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

  const HistoryEntry({
    required this.id,
    this.filePath,
    required this.mediaType,
    this.detectionResult,
    required this.confidence,
    required this.timestamp,
    this.provenance,
  });

  /// Returns a copy with optional overridden fields (used to attach a provenance
  /// snapshot after the live source trace settles).
  HistoryEntry copyWith({ProvenanceSnapshot? provenance}) => HistoryEntry(
        id: id,
        filePath: filePath,
        mediaType: mediaType,
        detectionResult: detectionResult,
        confidence: confidence,
        timestamp: timestamp,
        provenance: provenance ?? this.provenance,
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
      };

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
      );
}
