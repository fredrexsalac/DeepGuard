import '../services/media_provenance_service.dart';

/// A frozen, privacy-safe "screenshot" of the provenance + source-trace results
/// captured for a single analysis, persisted inside a [HistoryEntry].
///
/// When a LIVE analysis runs, the online Google Lens source-trace is executed
/// (the network part) alongside the offline metadata and C2PA checks. Once all
/// of those have settled, this snapshot is saved into the history record so the
/// exact same result can be RECALLED OFFLINE later — reopening history needs no
/// network and re-runs nothing.
///
/// PRIVACY: stores ONLY platform display names (e.g. "Facebook"), status tokens,
/// short summaries and on-device metadata strings. It NEVER stores URLs, profile
/// links, usernames, account IDs or any PII, consistent with the provenance
/// integrity rules.
class ProvenanceSnapshot {
  // ── On-device metadata report ──────────────────────────────────────────────
  final String sourceApp;
  final String category;
  final bool isAiGenerated;
  final bool isCameraOriginal;
  final List<String> forensicEvidence;
  final String? generationPrompt;
  final String? cameraHardware;
  final String? generatorModel;
  final String? generatorFamily;

  // ── Google Lens reverse-image source trace (the ONLINE part) ───────────────
  // Null when no trace was run (e.g. analyzed offline or AI-generated).
  final String? lensStatus;
  final String? lensSummary;
  final List<String> lensPlatforms;

  // ── C2PA content-credentials check ─────────────────────────────────────────
  final String? c2paStatus;
  final String? c2paSummary;

  const ProvenanceSnapshot({
    required this.sourceApp,
    required this.category,
    required this.isAiGenerated,
    required this.isCameraOriginal,
    this.forensicEvidence = const [],
    this.generationPrompt,
    this.cameraHardware,
    this.generatorModel,
    this.generatorFamily,
    this.lensStatus,
    this.lensSummary,
    this.lensPlatforms = const [],
    this.c2paStatus,
    this.c2paSummary,
  });

  /// Builds a snapshot from the live report + trace results.
  factory ProvenanceSnapshot.from(
    ProvenanceReport report,
    TraceResult? lens,
    TraceResult? c2pa,
  ) {
    return ProvenanceSnapshot(
      sourceApp: report.sourceApp,
      category: report.category,
      isAiGenerated: report.isAiGenerated,
      isCameraOriginal: report.isCameraOriginal,
      forensicEvidence: List<String>.from(report.forensicEvidence),
      generationPrompt: report.generationPrompt,
      cameraHardware: report.cameraHardware,
      generatorModel: report.generatorModel,
      generatorFamily: report.generatorFamily,
      lensStatus: lens?.status,
      lensSummary: lens?.summary,
      lensPlatforms: List<String>.from(lens?.sourcePlatforms ?? const []),
      c2paStatus: c2pa?.status,
      c2paSummary: c2pa?.summary,
    );
  }

  // ── Reconstruction helpers (for offline replay in history) ─────────────────

  ProvenanceReport toReport() => ProvenanceReport(
        sourceApp: sourceApp,
        category: category,
        isAiGenerated: isAiGenerated,
        isCameraOriginal: isCameraOriginal,
        forensicEvidence: forensicEvidence,
        generationPrompt: generationPrompt,
        cameraHardware: cameraHardware,
        generatorModel: generatorModel,
        generatorFamily: generatorFamily,
      );

  TraceResult? toLensTrace() => lensStatus == null
      ? null
      : TraceResult(
          engine: 'Google Lens',
          status: lensStatus!,
          summary: lensSummary ?? '',
          sourcePlatforms: lensPlatforms,
        );

  TraceResult? toC2paTrace() => c2paStatus == null
      ? null
      : TraceResult(
          engine: 'C2PA Content Credentials',
          status: c2paStatus!,
          summary: c2paSummary ?? '',
        );

  /// True if any online/offline trace result was captured (drives whether the
  /// history replay shows the "SOURCE TRACE RESULTS" block at all).
  bool get hasAnyTrace => lensStatus != null || c2paStatus != null;

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'sourceApp': sourceApp,
        'category': category,
        'isAiGenerated': isAiGenerated,
        'isCameraOriginal': isCameraOriginal,
        'forensicEvidence': forensicEvidence,
        'generationPrompt': generationPrompt,
        'cameraHardware': cameraHardware,
        'generatorModel': generatorModel,
        'generatorFamily': generatorFamily,
        'lensStatus': lensStatus,
        'lensSummary': lensSummary,
        'lensPlatforms': lensPlatforms,
        'c2paStatus': c2paStatus,
        'c2paSummary': c2paSummary,
      };

  factory ProvenanceSnapshot.fromJson(Map<String, dynamic> json) =>
      ProvenanceSnapshot(
        sourceApp: json['sourceApp'] as String? ?? 'No Recognizable Metadata',
        category: json['category'] as String? ?? 'Web / Social Media',
        isAiGenerated: json['isAiGenerated'] as bool? ?? false,
        isCameraOriginal: json['isCameraOriginal'] as bool? ?? false,
        forensicEvidence: (json['forensicEvidence'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        generationPrompt: json['generationPrompt'] as String?,
        cameraHardware: json['cameraHardware'] as String?,
        // Older history records have no model attribution saved → null, so the
        // result panel falls back to the generic "Modern A.I. Synthesis Engine"
        // label instead of inventing a model name.
        generatorModel: json['generatorModel'] as String?,
        generatorFamily: json['generatorFamily'] as String?,
        lensStatus: json['lensStatus'] as String?,
        lensSummary: json['lensSummary'] as String?,
        lensPlatforms: (json['lensPlatforms'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        c2paStatus: json['c2paStatus'] as String?,
        c2paSummary: json['c2paSummary'] as String?,
      );
}
