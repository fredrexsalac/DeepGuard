import 'package:flutter/material.dart';

import '../models/analysis_outcome.dart';
import '../models/provenance_snapshot.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// OutcomeFlagBanner
///
/// Displays an accessible advisory notice beneath the submitted media ONLY when
/// the classifier's verdict and positive embedded file provenance disagree.
/// Never alters the verdict, confidence, or stored record.
class OutcomeFlagBanner extends StatefulWidget {
  final String? entryId;
  final String? detectionResult;
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
    if (old.entryId != widget.entryId || old.snapshot != widget.snapshot) {
      _snapshot = widget.snapshot;
      _syncFromRecord();
    }
  }

  void _onServiceChange() {
    _syncFromRecord();
  }

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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final flag = crossCheckOutcome(
      detectionResult: widget.detectionResult,
      provenance: _snapshot,
    );
    if (flag == null || !flag.outcome.isDisagreement) {
      return const SizedBox.shrink();
    }

    final palette = DeepGuardPalette.of(context);
    final verdictLabel = widget.detectionResult == 'manipulated'
        ? 'A.I. (MANIPULATED)'
        : 'REAL (AUTHENTIC)';
    final outcome = flag.outcome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          'PROVENANCE CROSS-CHECK · AUTOMATIC',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'The classifier and this file\'s own metadata disagree. Neither one '
          'has been changed by the other, and the verdict above stands.',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: palette.warningContainer,
            border: Border.all(color: palette.warning.withValues(alpha: 0.65)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.report_problem_outlined,
                        size: 16,
                        color: palette.warningText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        outcome.uiTag.toUpperCase(),
                        style: TextStyle(
                          color: palette.warningText,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    outcome.formalTerm,
                    style: TextStyle(
                      color: palette.warningText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                outcome.sentence(verdictLabel, flag.evidence),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
