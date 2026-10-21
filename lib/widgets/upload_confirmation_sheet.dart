import 'package:flutter/material.dart';
import '../services/upload_verification_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet that:
///   1. Validates the selected file (extension, size, magic bytes)
///   2. Shows a security confirmation checkbox
///      "I confirm that I am authorized to submit and analyze this media."
///   3. Shows CANCEL / ANALYZE buttons (Analyze disabled until checkbox is checked)
///
/// Returns `true` when the user completes both the checkbox and the
/// "Are you sure?" confirmation dialog, `false`/`null` if cancelled.
class UploadConfirmationSheet extends StatefulWidget {
  final String filePath;

  const UploadConfirmationSheet._({required this.filePath});

  /// Shows the sheet. Returns `true` only when:
  ///   - Validation passes (canProceed)
  ///   - Security checkbox is ticked
  ///   - User taps ANALYZE on the confirmation dialog
  static Future<bool?> show({
    required BuildContext context,
    required String filePath,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UploadConfirmationSheet._(filePath: filePath),
    );
  }

  @override
  State<UploadConfirmationSheet> createState() =>
      _UploadConfirmationSheetState();
}

class _UploadConfirmationSheetState extends State<UploadConfirmationSheet>
    with SingleTickerProviderStateMixin {
  ValidationResult? _result;
  bool _loading = true;

  /// Security confirmation checkbox state.
  bool _securityConfirmed = false;

  late final AnimationController _entryAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut));
    _runValidation();
  }

  @override
  void dispose() {
    _entryAnim.dispose();
    super.dispose();
  }

  Future<void> _runValidation() async {
    final result = await UploadVerificationService().validate(widget.filePath);
    if (mounted) {
      setState(() {
        _result = result;
        _loading = false;
      });
      _entryAnim.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _loading ? 0.35 : 0.85,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1035),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: DeepGuardColors.primary, width: 1),
          ),
        ),
        child: _loading ? _buildLoading() : _buildContent(scrollCtrl),
      ),
    );
  }

  // ── Loading state ──────────────────────────────────────────────────────────
  Widget _buildLoading() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 24),
          CircularProgressIndicator(
              color: DeepGuardColors.primary, strokeWidth: 2),
          SizedBox(height: 14),
          Text('Verifying file…',
              style: TextStyle(
                  color: DeepGuardColors.textSecondary,
                  fontSize: 12,
                  fontFamily: 'monospace')),
          SizedBox(height: 24),
        ]),
      );

  // ── Main content ───────────────────────────────────────────────────────────
  Widget _buildContent(ScrollController ctrl) {
    final r = _result!;
    final isImg = r.mediaType == 'image';
    final hasWarning = r.checks.any((c) => c.status == ValidationStatus.warn);
    final canAnalyze = r.canProceed && _securityConfirmed;

    return SlideTransition(
      position: _slideAnim,
      child: ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // ── Handle bar ─────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DeepGuardColors.textMuted.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ─────────────────────────────────────────────────────────
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: r.canProceed
                    ? DeepGuardColors.authentic.withAlpha(20)
                    : DeepGuardColors.fake.withAlpha(20),
                border: Border.all(
                  color: r.canProceed
                      ? DeepGuardColors.authentic.withAlpha(100)
                      : DeepGuardColors.fake.withAlpha(100),
                ),
              ),
              child: Icon(
                r.canProceed
                    ? (hasWarning
                        ? Icons.warning_amber_outlined
                        : Icons.verified_outlined)
                    : Icons.cancel_outlined,
                color: r.canProceed
                    ? (hasWarning
                        ? DeepGuardColors.warning
                        : DeepGuardColors.authentic)
                    : DeepGuardColors.fake,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.canProceed ? 'Ready for Analysis' : 'Cannot Proceed',
                      style: TextStyle(
                        color: r.canProceed
                            ? DeepGuardColors.textPrimary
                            : DeepGuardColors.fake,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      r.canProceed
                          ? 'Complete the confirmation below to start'
                          : r.fatalMessage ?? 'Fix the errors below',
                      style: const TextStyle(
                          color: DeepGuardColors.textSecondary, fontSize: 12),
                    ),
                  ]),
            ),
          ]),

          const SizedBox(height: 20),

          // ── File summary ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: DeepGuardColors.primary.withAlpha(40)),
              color: DeepGuardColors.primary.withAlpha(8),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: DeepGuardColors.surfaceCard,
                ),
                child: Icon(
                  isImg ? Icons.image_outlined : Icons.videocam_outlined,
                  color: DeepGuardColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.fileName,
                          style: const TextStyle(
                              color: DeepGuardColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(children: [
                        _badge(isImg ? 'IMAGE' : 'VIDEO',
                            DeepGuardColors.primary),
                        const SizedBox(width: 6),
                        _badge('${r.fileSizeMb.toStringAsFixed(1)} MB',
                            DeepGuardColors.textMuted),
                      ]),
                    ]),
              ),
            ]),
          ),

          const SizedBox(height: 18),

          // ── Validation checks ───────────────────────────────────────────────
          const Text('VALIDATION CHECKS',
              style: TextStyle(
                  color: DeepGuardColors.textMuted,
                  fontSize: 9,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
          const SizedBox(height: 10),

          ...r.checks.map((c) => _CheckRow(check: c)),

          // ── Warning notice ──────────────────────────────────────────────────
          if (r.canProceed && hasWarning) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: DeepGuardColors.warning.withAlpha(60)),
                color: DeepGuardColors.warning.withAlpha(10),
              ),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: DeepGuardColors.warning, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Some advisory checks flagged warnings. '
                        'You may still proceed — results may vary.',
                        style: TextStyle(
                            color: DeepGuardColors.warning,
                            fontSize: 11,
                            height: 1.5),
                      ),
                    ),
                  ]),
            ),
          ],

          const SizedBox(height: 24),

          if (r.canProceed) ...[
            // ── Security confirmation checkbox ──────────────────────────────
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _securityConfirmed
                      ? DeepGuardColors.authentic.withAlpha(120)
                      : DeepGuardColors.glassBorder,
                ),
                color: _securityConfirmed
                    ? DeepGuardColors.authentic.withAlpha(12)
                    : DeepGuardColors.surfaceCard.withAlpha(60),
              ),
              child: InkWell(
                onTap: () =>
                    setState(() => _securityConfirmed = !_securityConfirmed),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _securityConfirmed,
                          onChanged: (v) => setState(
                              () => _securityConfirmed = v ?? false),
                          activeColor: DeepGuardColors.authentic,
                          side: BorderSide(
                            color: _securityConfirmed
                                ? DeepGuardColors.authentic
                                : DeepGuardColors.textMuted,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Security Confirmation',
                              style: TextStyle(
                                color: DeepGuardColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'I confirm that I am authorized to submit '
                              'and analyze this media.',
                              style: TextStyle(
                                color: DeepGuardColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Action buttons ──────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: DeepGuardColors.textMuted.withAlpha(60)),
                    ),
                    child: const Center(
                      child: Text('CANCEL',
                          style: TextStyle(
                              color: DeepGuardColors.textMuted,
                              fontSize: 12,
                              letterSpacing: 2,
                              fontFamily: 'monospace')),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: canAnalyze ? _onAnalyzeTappedInSheet : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: canAnalyze
                          ? const LinearGradient(
                              colors: DeepGuardColors.primaryGradient)
                          : null,
                      color: canAnalyze
                          ? null
                          : DeepGuardColors.surfaceLight.withAlpha(80),
                      boxShadow: canAnalyze
                          ? [
                              BoxShadow(
                                color: DeepGuardColors.primary.withAlpha(70),
                                blurRadius: 16,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.psychology_outlined,
                              color: canAnalyze
                                  ? Colors.white
                                  : DeepGuardColors.textMuted,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'ANALYZE',
                            style: TextStyle(
                              color: canAnalyze
                                  ? Colors.white
                                  : DeepGuardColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ]),
                  ),
                ),
              ),
            ]),

            if (!_securityConfirmed) ...[
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'Please tick the security confirmation to enable analysis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DeepGuardColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ] else ...[
            // ── Fatal error — dismiss only ───────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: DeepGuardColors.fake.withAlpha(80)),
                  color: DeepGuardColors.fake.withAlpha(10),
                ),
                child: const Center(
                  child: Text('DISMISS',
                      style: TextStyle(
                          color: DeepGuardColors.fake,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          fontFamily: 'monospace')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Handles ANALYZE tap: shows the confirmation dialog inside the sheet,
  /// then pops the sheet with the correct boolean result.
  Future<void> _onAnalyzeTappedInSheet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1035),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: DeepGuardColors.primary.withAlpha(80), width: 1),
        ),
        title: Row(children: [
          Icon(Icons.psychology_outlined,
              color: DeepGuardColors.primary, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Run Analysis?',
            style: TextStyle(
              color: DeepGuardColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
        content: const Text(
          'Are you sure you want to run the analysis?\n\n'
          'The selected media will be analyzed on-device using the '
          'DeepGuard AI model. No data will leave your device.',
          style: TextStyle(
            color: DeepGuardColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: DeepGuardColors.textMuted,
                fontSize: 13,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: DeepGuardColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'ANALYZE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.of(context).pop(confirmed == true);
    }
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: color.withAlpha(20),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                fontFamily: 'monospace')),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Single validation check row
// ─────────────────────────────────────────────────────────────────────────────
class _CheckRow extends StatelessWidget {
  final ValidationCheck check;
  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: check.color.withAlpha(40)),
          color: check.color.withAlpha(8),
        ),
        child: Row(children: [
          Icon(check.icon, color: check.color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(check.label,
                      style: TextStyle(
                          color: check.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace')),
                  const SizedBox(height: 2),
                  Text(check.detail,
                      style: const TextStyle(
                          color: DeepGuardColors.textSecondary,
                          fontSize: 11,
                          height: 1.3)),
                ]),
          ),
        ]),
      ),
    );
  }
}
