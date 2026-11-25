import 'package:flutter/material.dart';
import '../services/upload_verification_service.dart';
import '../theme/app_theme.dart';

/// Accessible pre-analysis file verification and authorization confirmation sheet.
///
/// Preserves all 5 [UploadVerificationService] validation layers and the
/// user authorization confirmation while adapting cleanly to Light and Dark
/// themes and dynamic text scaling.
class UploadConfirmationSheet extends StatefulWidget {
  final String filePath;

  const UploadConfirmationSheet._({required this.filePath});

  static Future<bool?> show({
    required BuildContext context,
    required String filePath,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UploadConfirmationSheet._(filePath: filePath),
    );
  }

  @override
  State<UploadConfirmationSheet> createState() =>
      _UploadConfirmationSheetState();
}

class _UploadConfirmationSheetState extends State<UploadConfirmationSheet> {
  ValidationResult? _result;
  bool _loading = true;
  bool _securityConfirmed = false;

  @override
  void initState() {
    super.initState();
    _runValidation();
  }

  Future<void> _runValidation() async {
    final result = await UploadVerificationService().validate(widget.filePath);
    if (mounted) {
      setState(() {
        _result = result;
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndAnalyze(ValidationResult r) async {
    final isImg = r.mediaType == 'image';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Confirm Media Analysis'),
        content: Text(
          'Are you sure you want to analyze this ${isImg ? "image" : "video"} '
          '(${r.fileName}) on your device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('Yes, Analyze'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return DraggableScrollableSheet(
      initialChildSize: _loading ? 0.35 : 0.82,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(
            top: BorderSide(color: palette.border, width: 1.2),
          ),
        ),
        child: _loading
            ? _buildLoading(palette)
            : _buildContent(scrollCtrl, palette),
      ),
    );
  }

  Widget _buildLoading(DeepGuardPalette palette) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: palette.processingStatus,
                strokeWidth: 2.5,
              ),
              const SizedBox(height: 14),
              Text(
                'Checking media requirements…',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildContent(ScrollController ctrl, DeepGuardPalette palette) {
    final r = _result!;
    final isImg = r.mediaType == 'image';
    final hasWarning = r.checks.any((c) => c.status == ValidationStatus.warn);
    final canAnalyze = r.canProceed && _securityConfirmed;

    return ListView(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        ExcludeSemantics(
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Header
        Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: r.canProceed
                      ? (hasWarning
                          ? palette.warningContainer
                          : palette.successContainer)
                      : palette.errorContainer,
                ),
                child: Icon(
                  r.canProceed
                      ? (hasWarning
                          ? Icons.warning_amber_rounded
                          : Icons.verified_outlined)
                      : Icons.cancel_outlined,
                  color: r.canProceed
                      ? (hasWarning ? palette.warningText : palette.successText)
                      : palette.errorText,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      r.canProceed ? 'Ready for Analysis' : 'Cannot Analyze File',
                      style: TextStyle(
                        color: r.canProceed
                            ? palette.textPrimary
                            : palette.errorText,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.canProceed
                        ? 'Review the file checks and confirm below to start.'
                        : (r.fatalMessage ?? 'Please resolve the issue below.'),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // File summary card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.backgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.processingContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isImg ? Icons.image_outlined : Icons.videocam_outlined,
                    color: palette.primaryText,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isImg ? 'Image' : 'Video'} · ${r.fileSizeMb.toStringAsFixed(1)} MB',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Semantics(
          header: true,
          child: Text(
            'Validation Checks',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),

        for (final check in r.checks) _CheckRow(check: check, palette: palette),

        if (r.canProceed && hasWarning) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.warningContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: palette.warning.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: palette.warningText,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Advisory warnings were noted above. You may still proceed, though results may be less reliable on low-resolution files.',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        if (r.canProceed) ...[
          // Consolidated single-node accessible Checkbox control
          Semantics(
            checked: _securityConfirmed,
            button: true,
            label:
                'Security Confirmation. I confirm that I am authorized to submit and analyze this media.',
            child: Material(
              color: _securityConfirmed
                  ? palette.successContainer
                  : palette.backgroundSecondary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(
                  () => _securityConfirmed = !_securityConfirmed,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _securityConfirmed
                          ? palette.success
                          : palette.controlBorder,
                      width: _securityConfirmed ? 1.5 : 1.1,
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            _securityConfirmed
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: _securityConfirmed
                                ? palette.successText
                                : palette.textSecondary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Authorization Confirmation',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'I confirm that I am authorized to submit and analyze this media on this device.',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13.5,
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
            ),
          ),
          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final stackVertically =
                  constraints.maxWidth < 340 || textScale > 1.3;

              final cancelBtn = OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              );
              final analyzeBtn = FilledButton.icon(
                onPressed: canAnalyze ? () => _confirmAndAnalyze(r) : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Analyze Now'),
              );

              if (stackVertically) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    analyzeBtn,
                    const SizedBox(height: 10),
                    cancelBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: cancelBtn),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: analyzeBtn),
                ],
              );
            },
          ),

          if (!_securityConfirmed) ...[
            const SizedBox(height: 10),
            Text(
              'Check the authorization box above to enable analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13.5,
              ),
            ),
          ],
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final ValidationCheck check;
  final DeepGuardPalette palette;

  const _CheckRow({required this.check, required this.palette});

  @override
  Widget build(BuildContext context) {
    final textColor = check.textColorFor(palette);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: '${check.label}: ${check.statusBadgeText}. ${check.detail}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: check.containerFor(palette),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: check.colorFor(palette).withValues(alpha: 0.45),
            ),
          ),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(check.icon, color: textColor, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              check.label,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            check.statusBadgeText,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        check.detail,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13.5,
                          height: 1.35,
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
    );
  }
}
