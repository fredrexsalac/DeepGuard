import 'package:flutter/material.dart';

import '../models/analysis_outcome.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// OutcomeDeclarationSection
///
/// Lets the user state what the submitted media REALLY is, and shows where
/// that puts the model's verdict in the confusion matrix:
///
///   real media called MANIPULATED  →  'False-Manipulated'  (false positive)
///   fake media called AUTHENTIC    →  'False-Authentic'    (false negative)
///
/// WHY IT IS USER-SUPPLIED AND CANNOT BE AUTOMATIC
/// The app holds exactly one axis: its own verdict. Printing "false" needs the
/// other one, and the classifier cannot supply it without already having answered
/// the question it was asked — comparing a claim against itself proves nothing.
/// So this section asks a person, and stays silent until one answers.
///
/// INTEGRITY RULES BAKED IN HERE
///   - Before anything happens, no outcome is on screen: only the question.
///     The one automatic path is [autoTruthFromProvenance], which fills a
///     declaration ONLY from an in-file Generative-AI signature read off the
///     settled provenance snapshot — never from a filename, never from a
///     beauty-filter tag, and never over a record a human already answered.
///     It is recorded as [DeclaredTruthSource.autoProvenance] so it can be
///     separated from testimony in analysis, and it does not change the verdict.
///   - The declaration never alters the verdict, confidence or model class
///     rendered above it.
///   - The badge names both inputs out loud ("You declared X, the model said Y")
///     so a reader can never mistake it for a second opinion from the model.
///   - Controls carry no verdict colour. The amber on a disagreement is a
///     highlight, not authentic-green or fake-red, which are reserved for
///     classification output.
///   - Everything shown here is a claim about truth, not a measurement. It is
///     kept apart from the benchmark figures (Image 84.82% / Video 71.67%)
///     everywhere it appears.
class OutcomeDeclarationSection extends StatefulWidget {
  /// The saved history record this verdict belongs to. Null when the analysis
  /// was never stored, in which case there is nothing to annotate.
  final String? entryId;

  /// 'authentic' / 'manipulated' / null (error verdict — not scoreable).
  final String? detectionResult;

  /// A declaration already on the record, so replaying history re-marks the
  /// chip the user chose instead of offering a blank question again.
  final String? initialDeclaredTruth;

  const OutcomeDeclarationSection({
    super.key,
    required this.entryId,
    required this.detectionResult,
    this.initialDeclaredTruth,
  });

  @override
  State<OutcomeDeclarationSection> createState() =>
      _OutcomeDeclarationSectionState();
}

class _OutcomeDeclarationSectionState extends State<OutcomeDeclarationSection> {
  String? _declared;
  bool _failed = false;
  ProfileService? _service;

  @override
  void initState() {
    super.initState();
    _declared = DeclaredTruth.parse(widget.initialDeclaredTruth)?.storageValue;
    // The derived rule lands asynchronously, after the provenance snapshot
    // settles, so this widget cannot rely on its constructor argument alone.
    // Listening keeps the chips honest about what the record actually holds.
    _service = ProfileService()..addListener(_onServiceChange);
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() => _syncFromRecord();

  /// Adopts whatever the stored record says, if anything can be read. Failing
  /// to read is normal (no store initialised) and leaves local state alone.
  Future<void> _syncFromRecord() async {
    final entryId = widget.entryId;
    final service = _service;
    if (entryId == null || service == null) return;
    try {
      final profile = service.activeProfile;
      if (profile == null) return;
      final entries = await service.getHistory(profile.id);
      final match = entries.where((e) => e.id == entryId);
      if (match.isEmpty || !mounted) return;
      final stored = match.first.declaredTruth;
      if (stored != _declared) setState(() => _declared = stored);
    } catch (_) {
      // No store (tests, or before init). The local state stands.
    }
  }

  @override
  void didUpdateWidget(OutcomeDeclarationSection old) {
    super.didUpdateWidget(old);
    // A different record replayed into the same widget position (history →
    // back → another record) must not keep the previous record's annotation.
    if (old.entryId != widget.entryId) {
      _declared = DeclaredTruth.parse(widget.initialDeclaredTruth)?.storageValue;
      _syncFromRecord();
    }
  }

  Future<void> _declare(String? value) async {
    final previous = _declared;
    final entryId = widget.entryId;
    if (entryId == null) return;

    setState(() {
      _declared = value;
      _failed = false;
    });

    final service = ProfileService();
    final profile = service.activeProfile;
    if (profile == null) {
      _revert(previous);
      return;
    }
    try {
      await service.updateHistoryDeclaration(profile.id, entryId, value);
      if (mounted) setState(() {});
    } catch (_) {
      _revert(previous);
    }
  }

  void _revert(String? previous) {
    if (!mounted) return;
    setState(() {
      _declared = previous;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final verdict = widget.detectionResult;
    // An error verdict has nothing to score, and an unsaved analysis has no
    // record to attach a declaration to. Show the question in neither case.
    if (verdict != 'authentic' && verdict != 'manipulated') {
      return const SizedBox.shrink();
    }
    if (widget.entryId == null) return const SizedBox.shrink();

    final outcome = resolveOutcome(
      detectionResult: verdict,
      declaredTruth: _declared,
    );
    final verdictLabel = verdict == 'manipulated' ? 'MANIPULATED' : 'AUTHENTIC';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'YOUR ASSESSMENT · SELF-REPORTED',
          style: TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 10,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'DeepGuard cannot know what this file really is — only its own guess. '
          'If you know the truth, record it. This does not change the verdict above.',
          style: const TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 10,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              label: 'Actually authentic',
              value: DeclaredTruth.authentic.storageValue,
              selected: _declared == DeclaredTruth.authentic.storageValue,
            ),
            _chip(
              label: 'Actually manipulated',
              value: DeclaredTruth.manipulated.storageValue,
              selected: _declared == DeclaredTruth.manipulated.storageValue,
            ),
          ],
        ),
        if (_declared != null) ...[
          const SizedBox(height: 4),
          Text(
            'Tap the selected one again to undo.',
            style: TextStyle(
              color: DeepGuardColors.textMuted.withAlpha(180),
              fontSize: 9,
            ),
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: 8),
          const Text(
            'Not saved — this record could not be found in your history.',
            style: TextStyle(
              color: DeepGuardColors.warning,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 10),
          _OutcomeBadge(outcome: outcome, verdictLabel: verdictLabel),
        ],
      ],
    );
  }

  Widget _chip({
    required String label,
    required String value,
    required bool selected,
  }) {
    final border = selected
        ? DeepGuardColors.textSecondary
        : DeepGuardColors.textMuted.withAlpha(70);
    return GestureDetector(
      onTap: () => _declare(selected ? null : value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? DeepGuardColors.textSecondary.withAlpha(28)
              : Colors.transparent,
          border: Border.all(color: border, width: selected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 14,
              color: selected
                  ? DeepGuardColors.textPrimary
                  : DeepGuardColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? DeepGuardColors.textPrimary
                    : DeepGuardColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeBadge extends StatelessWidget {
  final AnalysisOutcome outcome;
  final String verdictLabel;
  const _OutcomeBadge({required this.outcome, required this.verdictLabel});

  @override
  Widget build(BuildContext context) {
    // Amber for a disagreement, neutral blue-grey for an agreement. Neither is
    // authentic-green or fake-red: those two mean "the model decided", and this
    // box reports what a human said about the model.
    final accent =
        outcome.isDisagreement ? DeepGuardColors.warning : DeepGuardColors.info;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withAlpha(14),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              outcome.isDisagreement
                  ? Icons.report_problem_outlined
                  : Icons.thumb_up_outlined,
              size: 14,
              color: accent,
            ),
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
              style: TextStyle(
                color: accent.withAlpha(190),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            outcome.sentence(verdictLabel),
            style: const TextStyle(
              color: DeepGuardColors.textSecondary,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
