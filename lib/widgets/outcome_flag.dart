import 'package:flutter/material.dart';

import '../models/analysis_outcome.dart';
import '../models/provenance_snapshot.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// OutcomeFlagBanner
///
/// Shows, under the submitted media, the one case the app can state without
/// asking anyone: the classifier's verdict and the file's own embedded
/// provenance contradict each other.
///
///   AI generator signature + AUTHENTIC verdict   →  'False-Authentic'
///   physical camera tag + MANIPULATED verdict    →  'False-Manipulated'
///
/// WHY IT IS AUTOMATIC
/// The provenance scanner reads generator fingerprints and EXIF hardware tags
/// out of the file bytes on a code path that never touches inference, so it is
/// genuinely independent evidence rather than the model grading itself. Where
/// the two disagree the disagreement is a fact about the record, and asking the
/// user to confirm it first would only be a hassle.
///
/// INTEGRITY RULES BAKED IN HERE
///   - Renders ONLY on a disagreement. Agreement is counted in the history
///     tally and shown nowhere else, so the screen never fills with green.
///   - Renders ONLY on positive evidence. A file with stripped or absent
///     metadata — the common case — produces nothing at all, because absence
///     is not evidence of anything.
///   - Never near the verdict it scores. It sits under the media, with the
///     evidence named in its own words, so it cannot be read as a second
///     confidence reading from the model.
///   - Does not alter [detectionResult], the confidence, the model class, or
///     any stored record. It writes nothing anywhere.
///   - Amber only. Authentic-green and fake-red are reserved for classification
///     output, and this is not classification.
class OutcomeFlagBanner extends StatefulWidget {
  /// The saved history record this verdict belongs to. Its persisted provenance
  /// snapshot is the evidence source, so the banner can be rebuilt offline.
  final String? entryId;

  /// 'authentic' / 'manipulated' / null (error verdict — nothing to check).
  final String? detectionResult;

  /// The snapshot already in hand (history replay). When null the banner reads
  /// the record from storage instead, and keeps listening, because on a live
  /// analysis the provenance settles after this widget is first built.
  final ProvenanceSnapshot? snapshot;

  const OutcomeFlagBanner({
    super.key,
    required this.entryId,
    required this.detectionResult,
    this.snapshot,
  });

  @override
  State<OutcomeFlagBanner> createState() => _OutcomeFlagBannerState();
}

class _OutcomeFlagBannerState extends State<OutcomeFlagBanner> {
  ProvenanceSnapshot? _snapshot;
  ProfileService? _service;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.snapshot;
    _service = ProfileService()..addListener(_onServiceChange);
    _syncFromRecord();
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChange);
    super.dispose();
  }

  @override
  void didUpdateWidget(OutcomeFlagBanner old) {
    super.didUpdateWidget(old);
    // A different record replayed into the same widget position (history →
    // back → another record) must not keep the previous record's evidence.
    if (old.entryId != widget.entryId || old.snapshot != widget.snapshot) {
      _snapshot = widget.snapshot;
      _syncFromRecord();
    }
  }

  void _onServiceChange() {
    // The provenance write-back notifies here; that is the moment a live
    // analysis either gains its flag or stays correctly silent.
    _syncFromRecord();
  }

  /// Adopts the record's persisted snapshot, if one can be read. Failing to
  /// read is normal (no store initialised) and leaves current state alone.
  Future<void> _syncFromRecord() async {
    final entryId = widget.entryId;
    final service = _service;
    if (entryId == null || service == null) return;
    if (service.activeProfile == null) return;
    try {
      final entries = await service.getHistory(service.activeProfile!.id);
      final match = entries.where((e) => e.id == entryId);
      if (match.isEmpty || !mounted) return;
      final stored = match.first.provenance;
      if (stored != null && !identical(stored, _snapshot)) {
        setState(() => _snapshot = stored);
      }
    } catch (_) {
      // No store (tests, or before init). Whatever came in stands.
    }
  }

  @override
  Widget build(BuildContext context) {
    final flag = crossCheckOutcome(
      detectionResult: widget.detectionResult,
      provenance: _snapshot,
    );
    // Agreements and unevidenced records render nothing at all.
    if (flag == null || !flag.outcome.isDisagreement) {
      return const SizedBox.shrink();
    }

    final verdictLabel =
        widget.detectionResult == 'manipulated' ? 'MANIPULATED' : 'AUTHENTIC';
    final outcome = flag.outcome;
    final accent = DeepGuardColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'PROVENANCE CROSS-CHECK · AUTOMATIC',
          style: TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 11,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'The classifier and this file\'s own metadata disagree. Neither one '
          'has been changed by the other, and the verdict above stands.',
          style: const TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: accent.withAlpha(14),
            border: Border.all(color: accent.withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.report_problem_outlined, size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  outcome.uiTag.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  outcome.formalTerm,
                  // Full `warning`, not accent.withAlpha(190) at 9px: the formal
                  // term is the readable half of this pair, and amber at 190
                  // over a tinted box had fallen under the AA floor.
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                outcome.sentence(verdictLabel, flag.evidence),
                style: const TextStyle(
                  color: DeepGuardColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
