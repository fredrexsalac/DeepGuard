import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../models/prediction_result.dart';
import '../models/provenance_snapshot.dart';
import '../widgets/glass_card.dart';
import '../widgets/confidence_gauge.dart';
import '../widgets/deepguard_app_bar.dart';
import '../widgets/framing_evidence_overlay.dart';
import '../widgets/gradcam_heatmap_overlay.dart';
import '../widgets/outcome_flag.dart';
import '../services/media_provenance_service.dart';
import '../services/profile_service.dart';

/// DeepGuard Result Screen (Phase 8 & WCAG 2.2 Level AA).
///
/// Presents authenticity results using clear user-facing classifications:
///   - `REAL` (internal class 0 = Real, `DetectionResult.authentic`)
///   - `A.I.` (internal class 1 = Fake, `DetectionResult.manipulated`)
///
/// Every classification communicates status through readable text, a distinct
/// icon, and contrast-validated theme colors — never color alone.
/// Confidence is labeled strictly as **Model Confidence** (never accuracy).
class ResultScreen extends StatelessWidget {
  final PredictionResult result;
  final String filePath;
  final VoidCallback onAnalyzeAnother;
  final VoidCallback onGoHome;
  final bool isHistory;
  final ProvenanceSnapshot? historyProvenance;

  const ResultScreen({
    super.key,
    required this.result,
    required this.filePath,
    required this.onAnalyzeAnother,
    required this.onGoHome,
    this.isHistory = false,
    this.historyProvenance,
  });

  /// Primary user-facing classification label: REAL or A.I.
  String get _displayLabel {
    if (result.result == null) return 'ERROR';
    return result.result == DetectionResult.authentic ? 'REAL' : 'A.I.';
  }

  /// Internal model/dataset class preserved unchanged (Real / Fake).
  String get _internalClass {
    if (result.result == null) return 'Unknown';
    return result.result == DetectionResult.authentic ? 'Real' : 'Fake';
  }

  bool get _isAuthentic => result.result == DetectionResult.authentic;
  bool get _isError => result.status == PredictionStatus.error;
  bool get _isImage => result.mediaType == MediaType.image;

  String? get _verdictKey {
    if (result.result == null) return null;
    return _isAuthentic ? 'authentic' : 'manipulated';
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final file = File(filePath);
    final verdictColor = result.resultColorFor(palette);
    final verdictTextColor = result.resultTextColorFor(palette);
    final verdictContainer = result.resultContainerFor(palette);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        backgroundColor: palette.backgroundSecondary,
        appBar: DeepGuardAppBar(
          title: isHistory ? 'Saved Analysis' : 'Analysis Result',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Return to Home',
              onPressed: onGoHome,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Error state ─────────────────────────────────────────────
                if (_isError) ...[
                  _ErrorCard(message: result.errorMessage, palette: palette),
                  const SizedBox(height: 18),
                ],

                // ── Low model confidence advisory ───────────────────────────
                if (!_isError && !result.isHighConfidence) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.warningContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: palette.warning.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: palette.warningText,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Low Model Confidence '
                                '(${result.confidencePercentage.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  color: palette.warningText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Scores below 70% indicate a borderline prediction. '
                                'Consider testing a clearer, higher-resolution sample.',
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
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Primary REAL / A.I. Verdict Card ────────────────────────
                if (!_isError) ...[
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    glow: true,
                    glowColor: verdictColor,
                    borderColor: verdictColor.withValues(alpha: 0.65),
                    child: Column(
                      children: [
                        // Accessible classification status pill (Icon + Text + Color)
                        Semantics(
                          header: true,
                          label: _isAuthentic
                              ? 'Classification Result: REAL. Media shows no detected AI manipulation patterns.'
                              : 'Classification Result: A.I. Media shows patterns consistent with AI generation or manipulation.',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: verdictContainer,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: verdictColor.withValues(alpha: 0.65),
                                width: 1.5,
                              ),
                            ),
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isAuthentic
                                        ? Icons.verified_rounded
                                        : Icons.warning_amber_rounded,
                                    color: verdictTextColor,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _displayLabel,
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: verdictTextColor,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Short explanation
                        Text(
                          _isAuthentic
                              ? 'No signs of AI manipulation were detected in this ${_isImage ? "image" : "video"}.'
                              : 'Patterns consistent with AI generation or deepfake manipulation were detected in this ${_isImage ? "image" : "video"}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 15.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Model Confidence Gauge
                        ConfidenceGauge(
                          confidence: result.confidence,
                          size: 164,
                          color: verdictColor,
                          textColor: verdictTextColor,
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'Model confidence reflects certainty for this individual file — not overall experimental model accuracy.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Responsive Summary Metrics ────────────────────────────
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(1.0);
                      final stackMetrics =
                          constraints.maxWidth < 300 || textScale > 1.2;

                      final confidenceTile = _MetricSummaryTile(
                        icon: Icons.insights_rounded,
                        label: 'Model Confidence',
                        value:
                            '${result.confidencePercentage.toStringAsFixed(1)}%',
                        valueColor: verdictTextColor,
                        palette: palette,
                      );
                      final mediaTile = _MetricSummaryTile(
                        icon: _isImage
                            ? Icons.image_outlined
                            : Icons.videocam_outlined,
                        label: 'Media Type',
                        value: _isImage ? 'Image' : 'Video',
                        valueColor: palette.primaryText,
                        palette: palette,
                      );
                      final classTile = _MetricSummaryTile(
                        icon: result.resultIcon,
                        label: 'Model Class',
                        value: '$_displayLabel ($_internalClass)',
                        valueColor: verdictTextColor,
                        palette: palette,
                      );

                      if (stackMetrics) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            confidenceTile,
                            const SizedBox(height: 8),
                            mediaTile,
                            const SizedBox(height: 8),
                            classTile,
                          ],
                        );
                      }
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: confidenceTile),
                            const SizedBox(width: 8),
                            Expanded(child: mediaTile),
                            const SizedBox(width: 8),
                            Expanded(child: classTile),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Selected Media Preview & Framing Evidence ───────────────
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              isHistory
                                  ? 'Retained Media Evidence'
                                  : 'Analyzed Media Preview',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isHistory && file.existsSync())
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: palette.processingContainer,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: palette.accent.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 14,
                                    color: palette.accentText,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isImage
                                        ? 'IMAGE EVIDENCE'
                                        : 'VIDEO EVIDENCE',
                                    style: TextStyle(
                                      color: palette.accentText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          color: palette.brandNavy,
                          child: file.existsSync()
                              ? (_isImage
                                  ? Semantics(
                                      image: true,
                                      label:
                                          'Analyzed image evidence sample with framing region indicator.',
                                      child: FramingEvidenceOverlay(
                                        framing: result.framing,
                                        child: Image.file(
                                          file,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    )
                                  : _InlineVideoPlayer(filePath: filePath))
                              : Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.white70,
                                          size: 34,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          isHistory
                                              ? 'Media evidence is unavailable for this legacy record.\nRestore from a DeepGuard Evidence Archive (.zip) to include image and video previews.'
                                              : 'The media file could not be displayed.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.5,
                                            height: 1.45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (isHistory && file.existsSync()) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Preserved ${_isImage ? "image" : "video"} evidence — '
                          'retained locally for offline review and bundled inside '
                          'exported DeepGuard ZIP archives.',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                      FramingEvidenceLegend(
                        framing: result.framing,
                        mutedColor: palette.textMuted,
                      ),
                      OutcomeFlagBanner(
                        entryId: result.id,
                        detectionResult: _verdictKey,
                        snapshot: historyProvenance,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Real Model-Prescribed Grad-CAM & Key Video Frames ─────────
                if (!_isError && result.gradCam != null) ...[
                  GradCamSection(
                    gradCam: result.gradCam!,
                    isVideo: !_isImage,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Digital Provenance & Origin Attribution ─────────────────
                _ProvenanceSection(
                  filePath: filePath,
                  isHistory: isHistory,
                  isVideo: !_isImage,
                  entryId: result.id,
                  snapshot: historyProvenance,
                ),
                const SizedBox(height: 20),

                // ── Primary Navigation Actions ──────────────────────────────
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(1.0);
                    final stackButtons =
                        constraints.maxWidth < 340 || textScale > 1.3;

                    final homeBtn = OutlinedButton.icon(
                      onPressed: onGoHome,
                      icon: const Icon(Icons.home_outlined, size: 19),
                      label: const Text('Return Home'),
                    );
                    final nextBtn = FilledButton.icon(
                      onPressed: onAnalyzeAnother,
                      icon: Icon(
                        isHistory
                            ? Icons.history_rounded
                            : Icons.add_photo_alternate_outlined,
                        size: 20,
                      ),
                      label: Text(
                        isHistory ? 'Back to History' : 'Analyze Another',
                      ),
                    );

                    if (stackButtons) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          nextBtn,
                          const SizedBox(height: 10),
                          homeBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: homeBtn),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: nextBtn),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),

                // ── Guidance & Responsible Use Box ──────────────────────────
                GlassCard(
                  backgroundColor: _isError
                      ? palette.errorContainer
                      : verdictContainer,
                  borderColor: _isError
                      ? palette.error.withValues(alpha: 0.5)
                      : verdictColor.withValues(alpha: 0.45),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isError
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        color: _isError ? palette.errorText : verdictTextColor,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isError
                                  ? 'Analysis could not be completed'
                                  : (_isAuthentic
                                      ? 'Guidance for REAL classification'
                                      : 'Guidance for A.I. classification'),
                              style: TextStyle(
                                color: _isError
                                    ? palette.errorText
                                    : verdictTextColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _isError
                                  ? 'Verify that the file is a valid, uncorrupted image or video and try again.'
                                  : (_isAuthentic
                                      ? 'DeepGuard found no indicators of synthetic manipulation. Automated detection is an assistive tool rather than absolute proof of origin.'
                                      : 'DeepGuard identified visual or temporal patterns consistent with synthetic media. Verify the source independently before sharing or acting on this content.'),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ],
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

class _MetricSummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final DeepGuardPalette palette;

  const _MetricSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Semantics(
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Icon(icon, color: valueColor, size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String? message;
  final DeepGuardPalette palette;

  const _ErrorCard({this.message, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: GlassCard(
        backgroundColor: palette.errorContainer,
        borderColor: palette.error.withValues(alpha: 0.65),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: palette.errorText,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analysis Could Not Complete',
                    style: TextStyle(
                      color: palette.errorText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message ??
                        'An unexpected error occurred during analysis. Please try another supported image or video file.',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineVideoPlayer extends StatefulWidget {
  final String filePath;
  const _InlineVideoPlayer({required this.filePath});

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.filePath));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.seekTo(Duration.zero);
      ctrl.addListener(_onTick);
      if (mounted) setState(() => _ready = ctrl.value.isInitialized);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (_failed || ctrl == null || !_ready || !ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF101C36),
        child: Center(
          child: Icon(Icons.videocam_off, color: Colors.white70, size: 38),
        ),
      );
    }
    final isPlaying = ctrl.value.isPlaying;
    return Semantics(
      button: true,
      label: isPlaying ? 'Pause analyzed video' : 'Play analyzed video',
      child: GestureDetector(
        onTap: _togglePlay,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: ctrl.value.aspectRatio > 0
                    ? ctrl.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(ctrl),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ExcludeSemantics(
                child: VideoProgressIndicator(
                  ctrl,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF35C9E2),
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                ),
              ),
            ),
            if (!isPlaying)
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.65),
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProvenanceSection extends StatefulWidget {
  final String filePath;
  final bool isHistory;
  final bool isVideo;
  final String? entryId;
  final ProvenanceSnapshot? snapshot;

  const _ProvenanceSection({
    required this.filePath,
    this.isHistory = false,
    this.isVideo = false,
    this.entryId,
    this.snapshot,
  });

  @override
  State<_ProvenanceSection> createState() => _ProvenanceSectionState();
}

class _ProvenanceSectionState extends State<_ProvenanceSection> {
  bool _hasInternet = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  TraceResult? _c2paResult;
  bool _c2paLoading = false;

  ProvenanceReport? _report;
  late Future<ProvenanceReport> _reportFuture;
  bool _persisted = false;
  String? _loadingTrace;

  @override
  void initState() {
    super.initState();
    final snap = widget.snapshot;
    if (snap != null) {
      _report = snap.toReport();
      _reportFuture = Future.value(_report);
      _c2paResult = snap.toC2paTrace();
      _hasInternet = snap.hasAnyTrace;
      _persisted = true;
    } else if (!widget.isHistory) {
      _startReport();
      _checkInitialConnectivity();
      _listenToConnectivity();
    } else {
      _startReport();
    }
  }

  void _startReport() {
    _reportFuture = MediaProvenanceService().analyzeFile(widget.filePath)
      ..then((r) {
        if (!mounted) return;
        setState(() => _report = r);
        _maybePersist();
      });
  }

  void _maybePersist() {
    if (_persisted || widget.isHistory || widget.entryId == null) return;
    if (_report == null) return;
    final settled = !_hasInternet || (!_c2paLoading && _c2paResult != null);
    if (!settled) return;
    _persisted = true;
    final snap = ProvenanceSnapshot.from(_report!, null, _c2paResult);
    final svc = ProfileService();
    final profile = svc.activeProfile;
    if (profile == null) return;
    svc.updateHistoryProvenance(profile.id, widget.entryId!, snap);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel().catchError((_) {});
    super.dispose();
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) return false;
      try {
        final lookup = await InternetAddress.lookup('example.com')
            .timeout(const Duration(milliseconds: 2500));
        return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      } catch (_) {
        try {
          final lookup2 = await InternetAddress.lookup('google.com')
              .timeout(const Duration(milliseconds: 2000));
          return lookup2.isNotEmpty && lookup2[0].rawAddress.isNotEmpty;
        } catch (_) {
          return false;
        }
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkInitialConnectivity() async {
    final online = await _checkInternetConnection();
    if (!mounted) return;
    setState(() => _hasInternet = online);
    if (online) _autoRunAllTraces();
  }

  void _listenToConnectivity() {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (results) async {
          final hasInterface =
              results.any((r) => r != ConnectivityResult.none);
          if (!hasInterface) {
            if (mounted && _hasInternet) setState(() => _hasInternet = false);
            return;
          }
          final online = await _checkInternetConnection();
          if (!mounted) return;
          if (online != _hasInternet) {
            setState(() => _hasInternet = online);
            if (online && _c2paResult == null) {
              _autoRunAllTraces();
            }
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _autoRunAllTraces() async {
    if (!mounted) return;
    setState(() => _c2paLoading = true);

    final svc = MediaProvenanceService();
    final c2pa = await svc.traceOnC2PA(widget.filePath).catchError(
          (_) => const TraceResult(
            engine: 'C2PA Content Credentials',
            status: 'error',
            summary: 'Could not complete trace.',
          ),
        );
    if (!mounted) return;
    setState(() {
      _c2paResult = c2pa;
      _c2paLoading = false;
    });
    _maybePersist();
  }

  Future<void> _runTrace(
    String traceId,
    Future<TraceResult> Function() traceCall,
  ) async {
    final online = await _checkInternetConnection();
    if (!online) {
      if (mounted) setState(() => _hasInternet = false);
      return;
    }
    setState(() => _loadingTrace = traceId);
    final result = await traceCall();
    if (!mounted) return;
    setState(() => _loadingTrace = null);
    _showTraceSheet(result);
  }

  void _showTraceSheet(TraceResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final palette = DeepGuardPalette.of(sheetCtx);
        final statusTextColor = result.status == 'found'
            ? palette.primaryText
            : result.status == 'not_found'
                ? palette.textSecondary
                : palette.warningText;
        final statusContainer = result.status == 'found'
            ? palette.processingContainer
            : result.status == 'not_found'
                ? palette.surfaceElevated
                : palette.warningContainer;
        final statusIcon = result.status == 'found'
            ? Icons.travel_explore_rounded
            : result.status == 'not_found'
                ? Icons.remove_circle_outline
                : Icons.error_outline;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Row(
                    children: [
                      Icon(
                        Icons.travel_explore_rounded,
                        color: palette.primaryText,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.engine,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: statusContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusTextColor, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.summary,
                          style: TextStyle(
                            color: statusTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final f in result.findings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.primaryText,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'A small amount of network data was used for this check. DeepGuard does not store your media online.',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);

    return FutureBuilder<ProvenanceReport>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.processingStatus,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Inspecting file metadata and digital provenance…',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final report = snapshot.data!;
        final IconData badgeIcon = report.isAiGenerated
            ? Icons.auto_awesome_outlined
            : report.isCameraOriginal
                ? Icons.camera_alt_outlined
                : report.category == 'Image Editor'
                    ? Icons.brush_outlined
                    : Icons.public_outlined;

        final String badgeText = report.isAiGenerated
            ? 'AI Metadata Tag'
            : report.isCameraOriginal
                ? 'Camera Metadata'
                : report.category == 'Image Editor'
                    ? 'Editor Metadata'
                    : 'Unverified Source';

        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.fingerprint_rounded,
                            color: palette.primaryText,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Origin & Digital Provenance',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.processingContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, color: palette.primaryText, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          badgeText,
                          style: TextStyle(
                            color: palette.primaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Supplementary metadata only — provenance never overrides the AI model classification above.',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                report.isAiGenerated && report.generatorModel != null
                    ? report.generatorModel!
                    : report.isAiGenerated
                        ? 'Modern A.I. Synthesis Engine'
                        : report.isCameraOriginal
                            ? 'Physical Camera Hardware'
                            : report.category == 'Image Editor'
                                ? 'Digital Editing Software'
                                : 'No Recognizable Metadata',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (report.isCameraOriginal) ...[
                Text(
                  'Confirms the capture device only. A photograph of a screen or printed image carries the same camera tag and does not certify the scene as real.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (report.isAiGenerated && report.generatorFamily != null) ...[
                Text(
                  'Generative family: ${report.generatorFamily} (read from embedded metadata).',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (report.isAiGenerated ||
                  report.isCameraOriginal ||
                  report.category == 'Image Editor' ||
                  provenanceLogoAsset(report.sourceApp) != null) ...[
                _GeneratorLogoBadge(
                  sourceApp: report.sourceApp,
                  isAi: report.isAiGenerated,
                  isCamera: report.isCameraOriginal,
                  category: report.category,
                ),
                const SizedBox(height: 10),
              ],
              for (final e in report.forensicEvidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          color: palette.primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_hasInternet) ...[
                Divider(color: palette.border, height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: palette.accentText,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Content Credentials (C2PA)',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      widget.isHistory ? 'Saved Snapshot' : 'Auto-Checked',
                      style: TextStyle(
                        color: palette.primaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _InlineTraceResult(
                  icon: Icons.verified_user_outlined,
                  label: 'C2PA Content Credentials',
                  isLoading: _c2paLoading,
                  result: _c2paResult,
                  onRerun: (widget.isHistory || _loadingTrace != null)
                      ? null
                      : () => _runTrace(
                            'c2pa',
                            () => MediaProvenanceService()
                                .traceOnC2PA(widget.filePath),
                          ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InlineTraceResult extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isLoading;
  final TraceResult? result;
  final VoidCallback? onRerun;

  const _InlineTraceResult({
    required this.icon,
    required this.label,
    required this.isLoading,
    required this.result,
    required this.onRerun,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final Color statusTextColor = result == null
        ? palette.textMuted
        : result!.status == 'found'
            ? palette.primaryText
            : result!.status == 'not_found'
                ? palette.textSecondary
                : palette.warningText;

    final IconData statusIcon = result == null
        ? Icons.hourglass_top_rounded
        : result!.status == 'found'
            ? Icons.travel_explore_rounded
            : result!.status == 'not_found'
                ? Icons.remove_circle_outline
                : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, color: palette.primaryText, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.processingStatus,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Checking content credentials…',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (result != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(statusIcon, color: statusTextColor, size: 16),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result!.summary,
                          style: TextStyle(
                            color: statusTextColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result!.findings.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final f in result!.findings.take(2))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '› $f',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          if (!isLoading && onRerun != null)
            IconButton(
              onPressed: onRerun,
              tooltip: 'Refresh C2PA credentials check',
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: palette.primaryText,
              ),
            ),
        ],
      ),
    );
  }
}

String? provenanceLogoAsset(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('chatgpt') || s.contains('dall') || s.contains('openai')) {
    return 'assets/images/provenance/chatgpt.png';
  }
  if (s.contains('gemini') ||
      s.contains('imagen') ||
      s.contains('synthid') ||
      s.contains('deepmind')) {
    return 'assets/images/provenance/gemini.jpg';
  }
  if (s.contains('midjourney') || s.contains('mj-')) {
    return 'assets/images/provenance/midjourney.png';
  }
  if (s.contains('capcut')) {
    return 'assets/images/provenance/capcut.png';
  }
  if (s.contains('facebook') || s.contains('fb_img') || s.contains('fbimg')) {
    return 'assets/images/provenance/facebook.png';
  }
  if (s.contains('instagram') ||
      s.contains('insta_') ||
      s.contains('cdninstagram')) {
    return 'assets/images/provenance/instagram.jpg';
  }
  if (s.contains('twitter') ||
      s.contains('x (twitter)') ||
      s.contains('twimg') ||
      s.contains('t.co')) {
    return 'assets/images/provenance/twitter_x.png';
  }
  if (s.contains('reddit')) {
    return 'assets/images/provenance/reddit.png';
  }
  if (s.contains('tiktok')) {
    return 'assets/images/provenance/tiktok.png';
  }
  if (s.contains('youtube')) {
    return 'assets/images/provenance/youtube.png';
  }
  if (s.contains('screen capture') ||
      s.contains('screenshot') ||
      s.contains('screen_record') ||
      s.contains('screen record')) {
    return 'assets/images/provenance/screen_record.png';
  }
  if (s.contains('camera capture')) {
    return 'assets/images/provenance/camera_hardware.png';
  }
  return null;
}

class _GeneratorLogoBadge extends StatelessWidget {
  final String sourceApp;
  final bool isAi;
  final bool isCamera;
  final String category;

  const _GeneratorLogoBadge({
    required this.sourceApp,
    this.isAi = false,
    this.isCamera = false,
    this.category = '',
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final asset = provenanceLogoAsset(sourceApp);
    final (_, aiColor, aiName) = _aiToolLogo(sourceApp);

    final Color color = isAi
        ? aiColor
        : isCamera
            ? palette.primaryButton
            : category == 'Image Editor'
                ? palette.accent
                : palette.primaryButton;
    final Color safeColor = DeepGuardContrast.textSafeOn(
      color,
      brightness: palette.brightness,
    );
    final String name = isAi ? aiName : sourceApp;
    final String caption = isAi
        ? 'Detected Generator'
        : isCamera
            ? 'Capture Device'
            : category == 'Image Editor'
                ? 'Editing Software'
                : 'Detected Source';
    final IconData fallbackIcon = isAi
        ? Icons.auto_awesome_outlined
        : isCamera
            ? Icons.camera_alt_outlined
            : category == 'Image Editor'
                ? Icons.brush_outlined
                : Icons.public_outlined;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: asset != null
                ? Image.asset(
                    asset,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _logoCircle(fallbackIcon, color),
                  )
                : _logoCircle(fallbackIcon, color),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: safeColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                caption,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoCircle(IconData icon, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 19),
      );
}

(IconData, Color, String) _aiToolLogo(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('openai') || s.contains('dall') || s.contains('chatgpt')) {
    return (Icons.auto_awesome, const Color(0xFF10A37F), 'ChatGPT · DALL·E');
  }
  if (s.contains('gemini') ||
      s.contains('imagen') ||
      s.contains('synthid') ||
      s.contains('deepmind')) {
    return (Icons.psychology, const Color(0xFF4285F4), 'Gemini · Imagen');
  }
  if (s.contains('midjourney') || s.contains('mj-')) {
    return (Icons.waves, const Color(0xFF8B5CF6), 'Midjourney');
  }
  if (s.contains('firefly') || s.contains('adobe')) {
    return (Icons.local_florist, const Color(0xFFD64B55), 'Adobe Firefly');
  }
  if (s.contains('flux') || s.contains('black forest')) {
    return (Icons.bolt, const Color(0xFFFF5C00), 'FLUX');
  }
  if (s.contains('ideogram')) {
    return (Icons.title, const Color(0xFF22C3B6), 'Ideogram');
  }
  if (s.contains('leonardo')) {
    return (Icons.brush, const Color(0xFF1C9CFF), 'Leonardo AI');
  }
  if (s.contains('playground')) {
    return (Icons.videogame_asset, const Color(0xFFF5A623), 'Playground AI');
  }
  if (s.contains('recraft')) {
    return (Icons.layers, const Color(0xFF00C2A8), 'Recraft');
  }
  if (s.contains('stable diffusion') ||
      s.contains('comfyui') ||
      s.contains('novelai') ||
      s.contains('a1111') ||
      s.contains('sd-webui')) {
    return (Icons.blur_on, const Color(0xFFA855F7), 'Stable Diffusion');
  }
  if (s.contains('stylegan') ||
      s.contains('nvidia') ||
      s.contains('nvlabs') ||
      s.contains('thispersondoesnotexist')) {
    return (Icons.memory, const Color(0xFF76B900), 'StyleGAN · NVIDIA');
  }
  return (
    Icons.auto_awesome_motion,
    const Color(0xFF2457C5),
    'Generative AI',
  );
}
