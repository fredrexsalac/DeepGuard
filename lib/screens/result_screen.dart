import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../theme/app_theme.dart';
import '../models/prediction_result.dart';
import '../models/provenance_snapshot.dart';
import '../widgets/glass_card.dart';
import '../widgets/confidence_gauge.dart';
import '../services/media_provenance_service.dart';
import '../services/profile_service.dart';

/// DeepGuard Result Screen
///
/// Displays the final deepfake detection result using the application's
/// user-facing terminology:
///
///   Internal (model/dataset)   User-facing (this screen)
///   ─────────────────────────────────────────────────────
///   Real  (class 0)         →  AUTHENTIC
///   Fake  (class 1)         →  MANIPULATED
///
/// The Prediction Confidence value is the actual probability output from
/// the TFLite model for this ONE individual file — never hard-coded,
/// randomly generated, or adjusted. It is a separate concept from the
/// model's dataset-level test accuracy (Image 84.82% · Video 71.67%),
/// which is an evaluation metric reported on the Home and About screens.
///
/// The provenance section at the bottom is auxiliary metadata only — it is
/// not part of the detection pipeline and never overrides the classification.
class ResultScreen extends StatelessWidget {
  final PredictionResult result;
  final String filePath;
  final VoidCallback onAnalyzeAnother;
  final VoidCallback onGoHome;
  final bool isHistory;

  /// For history records: the provenance + source-trace snapshot captured when
  /// the media was first analyzed. When present, the provenance section replays
  /// it OFFLINE (like a screenshot) instead of re-running any trace. Null for a
  /// fresh/live analysis.
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

  // ── Derived display values ─────────────────────────────────────────────────

  /// User-facing display label.
  /// DetectionResult.authentic  → "AUTHENTIC"
  /// DetectionResult.manipulated → "MANIPULATED"
  /// (null / error)              → "ERROR"
  String get _displayLabel {
    if (result.result == null) return 'ERROR';
    return result.result == DetectionResult.authentic
        ? 'AUTHENTIC'
        : 'MANIPULATED';
  }

  /// Internal class name (model/dataset terminology — NOT shown as primary UI).
  String get _internalClass {
    if (result.result == null) return 'Unknown';
    return result.result == DetectionResult.authentic ? 'Real' : 'Fake';
  }

  bool get _isAuthentic => result.result == DetectionResult.authentic;
  bool get _isError     => result.status == PredictionStatus.error;
  bool get _isImage     => result.mediaType == MediaType.image;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: DeepGuardColors.primary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: Text(
            isHistory ? 'History Record' : 'Analysis Complete',
            style: const TextStyle(
              color: DeepGuardColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined,
                  color: DeepGuardColors.primary),
              onPressed: onGoHome,
              tooltip: 'Home',
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: DeepGuardColors.backgroundGradient,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Error state ─────────────────────────────────────────
                  if (_isError) ...[
                    _ErrorCard(message: result.errorMessage),
                    const SizedBox(height: 24),
                  ],

                  // ── Low confidence warning ───────────────────────────────
                  if (!_isError && !result.isHighConfidence) ...[
                    GlassCard(
                      padding: const EdgeInsets.all(14),
                      gradient: [
                        DeepGuardColors.warning.withValues(alpha: 0.10),
                        Colors.transparent
                      ],
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: DeepGuardColors.warning, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Low Confidence '
                                '(${result.confidencePercentage.toStringAsFixed(2)}%)',
                                style: const TextStyle(
                                  color: DeepGuardColors.warning,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Results below 70% may be less reliable. '
                                'Consider testing with a higher-quality file.',
                                style: TextStyle(
                                  color: DeepGuardColors.textMuted,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Primary result card ──────────────────────────────────
                  if (!_isError) ...[
                    GlassCard(
                      padding: const EdgeInsets.all(28),
                      glow: true,
                      glowColor: result.resultColor,
                      child: Column(
                        children: [
                          // Confidence gauge
                          ConfidenceGauge(
                            confidence: result.confidence,
                            size: 160,
                            color: result.resultColor,
                          ),
                          const SizedBox(height: 24),

                          // Result icon
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: result.resultColor.withValues(alpha: 0.15),
                              border: Border.all(
                                color: result.resultColor.withValues(alpha: 0.45),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: result.resultColor.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isAuthentic
                                  ? Icons.verified
                                  : Icons.warning_amber_rounded,
                              color: result.resultColor,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── USER-FACING LABEL: AUTHENTIC or MANIPULATED ──
                          Text(
                            _displayLabel,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: result.resultColor,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: result.resultColor.withValues(alpha: 0.45),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Sub-label
                          Text(
                            _isAuthentic
                                ? 'No signs of manipulation detected'
                                : 'AI manipulation patterns detected',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: DeepGuardColors.textSecondary
                                  .withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Internal class badge (small, informational)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: result.resultColor.withValues(alpha: 0.30)),
                              color: result.resultColor.withValues(alpha: 0.08),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Model class: ',
                                  style: TextStyle(
                                    color: DeepGuardColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  _internalClass,
                                  style: TextStyle(
                                    color: result.resultColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Detail row ─────────────────────────────────────────
                    Row(children: [
                      // Confidence
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 12),
                          child: Column(children: [
                            Icon(Icons.analytics_outlined,
                                color: DeepGuardColors.primary.withValues(alpha: 0.7),
                                size: 22),
                            const SizedBox(height: 8),
                            const Text('PREDICTION\nCONFIDENCE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: DeepGuardColors.textMuted,
                                  fontSize: 9,
                                  letterSpacing: 1,
                                  height: 1.35,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              '${result.confidencePercentage.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: result.resultColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Media type
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 12),
                          child: Column(children: [
                            Icon(
                              _isImage
                                  ? Icons.image_outlined
                                  : Icons.videocam_outlined,
                              color:
                                  DeepGuardColors.secondary.withValues(alpha: 0.7),
                              size: 22,
                            ),
                            const SizedBox(height: 8),
                            const Text('MEDIA TYPE',
                                style: TextStyle(
                                  color: DeepGuardColors.textMuted,
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              _isImage ? 'Image' : 'Video',
                              style: const TextStyle(
                                color: DeepGuardColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Result (internal)
                      Expanded(
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 12),
                          child: Column(children: [
                            Icon(result.resultIcon,
                                color: result.resultColor.withValues(alpha: 0.7),
                                size: 22),
                            const SizedBox(height: 8),
                            const Text('CLASS',
                                style: TextStyle(
                                  color: DeepGuardColors.textMuted,
                                  fontSize: 9,
                                  letterSpacing: 1.5,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              _internalClass,
                              style: TextStyle(
                                color: result.resultColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // ── Safeguard: prediction confidence ≠ benchmark accuracy ─
                    Text(
                      'Prediction Confidence is the model\'s raw output for '
                      'this individual file only. It is separate from the '
                      'model\'s benchmark evaluation accuracy '
                      '(${_isImage ? 'Image: 84.82%' : 'Video: 71.67%'}), '
                      'which is a dataset-level metric and NOT the confidence '
                      'of this prediction. Prediction confidence represents '
                      'the model\'s output for this media and does not '
                      'guarantee that the media is authentic or manipulated.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: DeepGuardColors.textMuted,
                        fontSize: 10.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Out-of-scope reminder for very-high-confidence Authentic ─
                    // The classifier detects FACE-based deepfake manipulation only.
                    // A near-100% "Authentic" can simply mean the input is out-of-
                    // distribution (AI-generated photo, graphic, heavy edit). The
                    // raw Prediction Confidence is intentionally left UNCHANGED —
                    // this note only frames how the number should be interpreted.
                    if (_isAuthentic &&
                        result.confidencePercentage >= 95.0) ...[
                      GlassCard(
                        padding: const EdgeInsets.all(14),
                        gradient: [
                          DeepGuardColors.info.withValues(alpha: 0.10),
                          Colors.transparent
                        ],
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              color: DeepGuardColors.info, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'High-confidence "Authentic" \u2014 scope reminder',
                                  style: TextStyle(
                                    color: DeepGuardColors.info,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'DeepGuard detects face-based deepfake '
                                  'manipulation. A very high Authentic confidence '
                                  'means no such manipulation was found \u2014 it '
                                  'does NOT confirm the media is human-made, and it '
                                  'may not flag AI-generated images, graphics, or '
                                  'heavy edits that fall outside its training. See '
                                  'the provenance and similar-imagery match below for '
                                  'origin clues.',
                                  style: TextStyle(
                                    color: DeepGuardColors.textMuted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ── Media preview ──────────────────────────────────────────
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SUBMITTED MEDIA',
                          style: TextStyle(
                            color: DeepGuardColors.textMuted,
                            fontSize: 10,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: file.existsSync()
                                ? (_isImage
                                    ? Image.file(file, fit: BoxFit.contain)
                                    : _InlineVideoPlayer(filePath: filePath))
                                : Container(
                                    color: DeepGuardColors.surfaceDark,
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.broken_image,
                                              color: DeepGuardColors.textMuted,
                                              size: 36),
                                          const SizedBox(height: 10),
                                          Text(
                                            // A history record's own data is intact; only the
                                            // media file is missing, so say which of the two this
                                            // screen still shows.
                                            isHistory
                                                ? 'Media file not on this device.\n'
                                                    'The report below is replayed from your saved record.'
                                                : 'The media file could not be read.',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: DeepGuardColors.textMuted,
                                              fontSize: 11,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Digital Provenance & Origin Attribution ───────────────
                  _ProvenanceSection(
                    filePath: filePath,
                    isHistory: isHistory,
                    isVideo: !_isImage,
                    entryId: result.id,
                    snapshot: historyProvenance,
                  ),
                  const SizedBox(height: 20),

                  // ── Action buttons ─────────────────────────────────────────
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onGoHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DeepGuardColors.textMuted,
                          side: BorderSide(
                              color:
                                  DeepGuardColors.textMuted.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home_outlined, size: 16),
                            SizedBox(width: 6),
                            Text('Home',
                                style: TextStyle(letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _GradientButton(
                        label: isHistory ? 'Back to History' : 'Analyze Another',
                        icon: isHistory ? Icons.history : Icons.upload_file,
                        onTap: onAnalyzeAnother,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Info / disclaimer box ──────────────────────────────────
                  GlassCard(
                    gradient: _isAuthentic && !_isError
                        ? [
                            DeepGuardColors.authentic.withValues(alpha: 0.05),
                            Colors.transparent
                          ]
                        : _isError
                            ? null
                            : [
                                DeepGuardColors.fake.withValues(alpha: 0.05),
                                Colors.transparent
                              ],
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _isError
                              ? Icons.error_outline
                              : (_isAuthentic
                                  ? Icons.info_outline
                                  : Icons.shield_outlined),
                          color: _isError
                              ? DeepGuardColors.fake
                              : result.resultColor,
                          size: 20,
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
                                        ? 'This media appears to be authentic'
                                        : 'This media shows signs of manipulation'),
                                style: TextStyle(
                                  color: _isError
                                      ? DeepGuardColors.fake
                                      : result.resultColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isError
                                    ? 'Please verify the file is a supported '
                                        'image or video format and try again.'
                                    : (_isAuthentic
                                        ? 'The DeepGuard AI model detected no '
                                            'signs of manipulation. No detection '
                                            'system is 100% accurate — use this '
                                            'result as guidance, not definitive proof.'
                                        : 'The DeepGuard AI model detected patterns '
                                            'consistent with deepfake generation. '
                                            'Further verification is recommended '
                                            'before sharing or acting on this content.'),
                                style: const TextStyle(
                                  color: DeepGuardColors.textMuted,
                                  fontSize: 12,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error card
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  final String? message;
  const _ErrorCard({this.message});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glow: true,
      glowColor: DeepGuardColors.fake,
      gradient: [DeepGuardColors.fake.withValues(alpha: 0.08), Colors.transparent],
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: DeepGuardColors.fake, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Analysis Failed',
                style: TextStyle(
                  color: DeepGuardColors.fake,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message ??
                    'An unexpected error occurred during analysis. '
                    'Please try again with a different file.',
                style: const TextStyle(
                  color: DeepGuardColors.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gradient action button
// ─────────────────────────────────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
              colors: DeepGuardColors.primaryGradient),
          boxShadow: [
            BoxShadow(
              color: DeepGuardColors.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Digital Provenance & Source Attribution Section
// ────────────────────────────────────────────────────────────────────────────────
/// Self-contained, playable inline video preview for the result screen.
/// Creates its own [VideoPlayerController], plays/pauses on tap, shows a
/// scrubbing progress bar, and degrades to a placeholder if the file cannot
/// be initialized. (The previous build used Image.file() on the video, which
/// could never play.)
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
  bool _showIcon = true;

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
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
        _showIcon = true;
      } else {
        ctrl.play();
        _showIcon = false;
      }
    });
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
      return Container(
        color: DeepGuardColors.surfaceDark,
        child: const Center(
          child: Icon(Icons.videocam_off,
              color: DeepGuardColors.textMuted, size: 40),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              ctrl,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: DeepGuardColors.primary,
                bufferedColor:
                    DeepGuardColors.primary.withValues(alpha: 0.25),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
              padding:
                  const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            ),
          ),
          if (!ctrl.value.isPlaying || _showIcon)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(
                      color:
                          DeepGuardColors.primary.withValues(alpha: 0.6),
                      width: 1.5),
                ),
                child: Icon(
                  ctrl.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProvenanceSection extends StatefulWidget {
  final String filePath;
  final bool isHistory;
  final bool isVideo;

  /// History-entry id (== the analysis result id). Used to persist a provenance
  /// snapshot after a LIVE source trace settles.
  final String? entryId;

  /// Stored snapshot to replay offline for a history record. Null for live.
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
  // Connectivity status — auto-trace source is strictly hidden when offline
  bool _hasInternet = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Auto-trace results — loaded automatically on init when internet is present
  TraceResult? _traceResult;
  TraceResult? _c2paResult;
  bool _traceLoading = false;
  bool _c2paLoading = false;

  // On-device metadata report (loaded once, reused for both UI + persistence)
  ProvenanceReport? _report;
  late Future<ProvenanceReport> _reportFuture;

  // Guards one-time persistence of the snapshot for a live analysis
  bool _persisted = false;

  // Legacy single-trace loading flag (kept for _runTrace bottom sheet flow)
  String? _loadingTrace;

  @override
  void initState() {
    super.initState();
    final snap = widget.snapshot;
    if (snap != null) {
      // HISTORY REPLAY: render the frozen snapshot offline — like a screenshot.
      // No network, no connectivity listener, no re-run, nothing to persist.
      _report = snap.toReport();
      _reportFuture = Future.value(_report);
      _traceResult = snap.toLensTrace();
      _c2paResult = snap.toC2paTrace();
      _hasInternet = snap.hasAnyTrace; // reveal trace block only if it was captured
      _persisted = true;
    } else if (!widget.isHistory) {
      // LIVE: offline metadata + online source trace, then persist a snapshot.
      _startReport();
      _checkInitialConnectivity();
      _listenToConnectivity();
    } else {
      // LEGACY HISTORY (saved before snapshots existed): offline metadata only.
      _startReport();
    }
  }

  /// Kicks off the one-time on-device metadata analysis and captures the result
  /// in state so it can be reused for both rendering and persistence.
  void _startReport() {
    _reportFuture = MediaProvenanceService().analyzeFile(widget.filePath)
      ..then((r) {
        if (!mounted) return;
        setState(() => _report = r);
        _maybePersist();
      });
  }

  /// Saves the provenance/source-trace snapshot into the history record once,
  /// after the live metadata report AND (online) traces have settled. Offline
  /// live analyses persist with just the metadata. History replays never persist.
  void _maybePersist() {
    if (_persisted || widget.isHistory || widget.entryId == null) return;
    if (_report == null) return;
    final settled = !_hasInternet ||
        (!_traceLoading &&
            !_c2paLoading &&
            _traceResult != null &&
            _c2paResult != null);
    if (!settled) return;
    _persisted = true;
    final snap = ProvenanceSnapshot.from(_report!, _traceResult, _c2paResult);
    final svc = ProfileService();
    final profile = svc.activeProfile;
    if (profile == null) return;
    svc.updateHistoryProvenance(profile.id, widget.entryId!, snap);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Verifies active internet connectivity using network interfaces and a reachability probe.
  Future<bool> _checkInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) return false;

      // Fast DNS reachability probe
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
    setState(() {
      _hasInternet = online;
    });
    if (online) {
      _autoRunAllTraces();
    }
  }

  void _listenToConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) async {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        if (mounted && _hasInternet) {
          setState(() => _hasInternet = false);
        }
        return;
      }
      final online = await _checkInternetConnection();
      if (!mounted) return;
      if (online != _hasInternet) {
        setState(() => _hasInternet = online);
        if (online && (_traceResult == null || _c2paResult == null)) {
          _autoRunAllTraces();
        }
      }
    });
  }

  /// Runs the SerpApi Google Lens reverse-image trace. For a video, extracts
  /// one representative frame first. Auxiliary only — never the verdict.
  Future<TraceResult> _runLensTrace() async {
    const engine = 'Google Lens';
    try {
      final svc = MediaProvenanceService();
      Uint8List bytes;
      if (widget.isVideo) {
        // Grab a representative frame. The very first frame of social clips is
        // often black or a logo splash, which Google Lens can't match — so try
        // a point a couple seconds in first, then fall back toward the start.
        Uint8List? frame;
        for (final ms in const [2000, 1000, 3000, 500, 0]) {
          frame = await VideoThumbnail.thumbnailData(
            video: widget.filePath,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 1024,
            quality: 80,
            timeMs: ms,
          );
          if (frame != null && frame.isNotEmpty) break;
        }
        if (frame == null || frame.isEmpty) {
          return const TraceResult(
            engine: engine,
            status: 'not_found',
            summary: 'No representative frame could be read from the video.',
          );
        }
        bytes = frame;
      } else {
        final file = File(widget.filePath);
        if (!await file.exists()) {
          return const TraceResult(
            engine: engine,
            status: 'error',
            summary: 'File not found on device.',
          );
        }
        bytes = await file.readAsBytes();
      }
      return svc.traceOnSerpApi(bytes);
    } catch (_) {
      return const TraceResult(
        engine: engine,
        status: 'error',
        summary: 'Could not complete trace.',
      );
    }
  }

  /// Fires the reverse-image source trace (SerpApi Google Lens) and the C2PA
  /// check in parallel when internet is confirmed. For a video, one
  /// representative frame is extracted and traced (auxiliary only — never the
  /// Hybrid CNN-RNN verdict).
  Future<void> _autoRunAllTraces() async {
    if (!mounted) return;
    setState(() {
      _traceLoading = true;
      _c2paLoading = true;
    });

    final svc = MediaProvenanceService();
    // Run both concurrently
    final results = await Future.wait([
      _runLensTrace(),
      svc.traceOnC2PA(widget.filePath).catchError((_) => const TraceResult(
            engine: 'C2PA Content Credentials',
            status: 'error',
            summary: 'Could not complete trace.',
          )),
    ]);
    if (!mounted) return;
    setState(() {
      _traceResult = results[0];
      _c2paResult  = results[1];
      _traceLoading = false;
      _c2paLoading  = false;
    });
    // Source trace has settled — capture the snapshot into the history record.
    _maybePersist();
  }

  /// Re-runs a single trace on demand and shows the bottom sheet.
  Future<void> _runTrace(
    String traceId,
    Future<TraceResult> Function() traceCall,
  ) async {
    final online = await _checkInternetConnection();
    if (!online) {
      if (mounted) {
        setState(() => _hasInternet = false);
      }
      return;
    }
    setState(() => _loadingTrace = traceId);
    final result = await traceCall();
    if (!mounted) return;
    setState(() => _loadingTrace = null);
    _showTraceSheet(result);
  }

  void _showTraceSheet(TraceResult result) {
    // Neutral informational colours: a trace hit (found) is NOT a
    // manipulation verdict, and a missing trace (not_found) is NOT an
    // authenticity verdict. Classification comes only from the CNN-RNN model.
    final statusColor = result.status == 'found'
        ? DeepGuardColors.info
        : result.status == 'not_found'
            ? DeepGuardColors.textSecondary
            : Colors.orangeAccent;
    final statusIcon = result.status == 'found'
        ? Icons.travel_explore_rounded
        : result.status == 'not_found'
            ? Icons.remove_circle_outline
            : Icons.error_outline;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: DeepGuardColors.surfaceCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: DeepGuardColors.primary.withAlpha(60),
                width: 1,
              ),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: DeepGuardColors.textMuted.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Engine title
              Row(
                children: [
                  Icon(Icons.travel_explore_rounded,
                      color: DeepGuardColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.engine.toUpperCase(),
                      style: const TextStyle(
                        color: DeepGuardColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: statusColor.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        result.summary,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Findings list
              if (result.findings.isNotEmpty) ...
                result.findings.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.chevron_right_rounded,
                                color: DeepGuardColors.primary, size: 16),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f,
                              style: const TextStyle(
                                color: DeepGuardColors.textSecondary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 8),
              // Bandwidth note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DeepGuardColors.surfaceDark.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '📶  A small amount of internet data was used to run this trace. '
                  'No image data is stored by DeepGuard.',
                  style: TextStyle(
                    color: DeepGuardColors.textMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the "Similar Imagery Found" (reverse-image match) section.
  ///
  /// Shows ONLY recognisable platform names + icons derived from the source
  /// trace. It NEVER displays URLs, profile links, usernames or any PII, and
  /// there are NO clickable elements. This is supplementary information that
  /// has no effect on the Authentic / Manipulated classification above.
  Widget _buildPossibleSource() {
    // Defense-in-depth: filter explicit/adult tokens again here, so even a
    // snapshot saved before the trace-side filter was added can never surface
    // them. Only recognised, clean platform display names remain.
    final platforms = (_traceResult?.sourcePlatforms ?? const <String>[])
        .where((p) => !MediaProvenanceService.containsAdultTerm(p))
        .toList();

    Widget body;
    if (!_hasInternet) {
      body = const Text(
        'No similar-imagery trace available.',
        style: TextStyle(
          color: DeepGuardColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      );
    } else if (_traceLoading) {
      body = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DeepGuardColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Scanning matched web sources...',
            style: TextStyle(
              color: DeepGuardColors.textMuted,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    } else if (platforms.isEmpty) {
      body = const Text(
        'No visually similar imagery found online.',
        style: TextStyle(
          color: DeepGuardColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      );
    } else {
      // Reverse-image search can only find visually SIMILAR imagery hosted
      // elsewhere — it can never know where this file actually came from. A
      // locally saved or edited clip (e.g. from CapCut) will still match
      // unrelated look-alike content online. Platforms are therefore shown as
      // one equal-ranked list (no highlighted "primary" source) under explicit
      // similarity wording. This NEVER affects the Authentic / Manipulated
      // classification.
      final shown = platforms.take(6).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Visually similar content exists on:',
            style: TextStyle(
              color: DeepGuardColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in shown) _SourceChip(platform: p),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'These are look-alike matches only — this does NOT identify where '
            'the file came from. A local or edited video can still match '
            'unrelated web content.',
            style: TextStyle(
              color: DeepGuardColors.textMuted,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: DeepGuardColors.glassBorder, height: 24),
        Row(
          children: [
            Icon(Icons.image_search,
                color: DeepGuardColors.secondary, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'SIMILAR IMAGERY FOUND',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: DeepGuardColors.textMuted,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Supplementary trace information only — the detected platform list '
          'never affects the Authentic / Manipulated classification.',
          style: TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 10,
            fontStyle: FontStyle.italic,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProvenanceReport>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DeepGuardColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tracing media origin & digital signatures...',
                    style: TextStyle(
                      color: DeepGuardColors.textMuted,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final report = snapshot.data!;
        Color badgeColor;
        IconData badgeIcon;

        // Neutral informational colours: provenance badges must never look
        // like an Authentic/Manipulated verdict — the classification shown
        // above is decided solely by the Hybrid CNN-RNN model.
        if (report.isAiGenerated) {
          badgeColor = DeepGuardColors.secondary;
          badgeIcon = Icons.auto_awesome;
        } else if (report.isCameraOriginal) {
          badgeColor = DeepGuardColors.primary;
          badgeIcon = Icons.camera_alt_outlined;
        } else if (report.category == 'Image Editor') {
          badgeColor = Colors.purpleAccent;
          badgeIcon = Icons.brush_outlined;
        } else {
          badgeColor = Colors.blueAccent;
          badgeIcon = Icons.public;
        }

        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fingerprint,
                      color: DeepGuardColors.primary, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ORIGIN & DIGITAL PROVENANCE',
                        style: TextStyle(
                          color: DeepGuardColors.textMuted,
                          fontSize: 9.5,
                          letterSpacing: 1.2,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(38),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: badgeColor.withAlpha(90)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, color: badgeColor, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          report.isAiGenerated
                              ? 'AI GENERATOR TAG'
                              : report.isCameraOriginal
                                  ? 'CAMERA METADATA'
                                  : report.category == 'Image Editor'
                                      ? 'EDITOR METADATA'
                                      : 'UNVERIFIED SOURCE',
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Auxiliary-information disclaimer: provenance is metadata
              // inspection only and is NOT part of the detection pipeline.
              const Text(
                'Auxiliary metadata only — provenance never overrides the '
                'Hybrid CNN-RNN classification, and its absence does not '
                'imply Authentic or Manipulated.',
                style: TextStyle(
                  color: DeepGuardColors.textMuted,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),

              // Origin label. When the embedded metadata names a specific
              // generative MODEL, that model is shown by name (e.g.
              // "DALL·E 3 / GPT-4o image output (OpenAI)") instead of the
              // generic bucket. History records saved before model
              // attribution existed keep the generic wording — nothing is
              // guessed. Auxiliary metadata only: this never changes the
              // Hybrid CNN-RNN verdict above.
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
                style: const TextStyle(
                  color: DeepGuardColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Architecture family line for AI-attributed media.
              if (report.isAiGenerated && report.generatorFamily != null) ...[
                Text(
                  'Generative family: ${report.generatorFamily} — named from '
                  'embedded metadata, not a verified origin.',
                  style: const TextStyle(
                    color: DeepGuardColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Detected source logo badge (auxiliary only — rendered from
              // bundled assets with an icon fallback, fully offline, and it
              // NEVER affects the classification). Shown for AI generators and
              // for recognizable camera / editor / screen-capture sources.
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

              // Evidence list
              ...report.forensicEvidence.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: TextStyle(
                                color: DeepGuardColors.primary, fontSize: 12)),
                        Expanded(
                          child: Text(
                            e,
                            style: TextStyle(
                              color: DeepGuardColors.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

              // ── Auto Source Trace Results ──────────────────────────────────
              // Shown whenever an active internet connection is available — this
              // now includes history records, so a saved item gets the same source
              // trace as a fresh analysis. Offline, this block hides and only the
              // on-device metadata provenance remains.
              if (_hasInternet) ...[
                const Divider(color: DeepGuardColors.glassBorder, height: 24),
                Row(
                  children: [
                    Icon(Icons.travel_explore_rounded,
                        color: DeepGuardColors.secondary, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'REVERSE-IMAGE SIMILARITY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: DeepGuardColors.textMuted,
                          fontSize: 9,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isHistory ? 'SAVED SNAPSHOT' : 'AUTO-SCANNED',
                      style: TextStyle(
                        color: DeepGuardColors.primary.withAlpha(160),
                        fontSize: 8,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // NOTE: Both auto-traces run in _autoRunAllTraces(). The
                // Google Lens trace derives the platform names shown in the
                // Similar-imagery section below; the C2PA trace checks for
                // embedded content credentials. Both are auxiliary only and
                // never affect the Hybrid CNN-RNN classification.

                // Google Lens reverse-image trace tile. Hidden when the file's
                // own provenance is already confirmed AI-generated (a freshly
                // synthesized image has no legitimate web source) OR when it is
                // a genuine camera-hardware capture — the origin is the device
                // itself, so a reverse-image match would only be misleading.
                if (!report.isAiGenerated && !report.isCameraOriginal) ...[
                  _InlineTraceResult(
                    icon: Icons.travel_explore_rounded,
                    label: 'GOOGLE LENS SIMILARITY',
                    isLoading: _traceLoading,
                    result: _traceResult,
                    onRerun: (widget.isHistory || _loadingTrace != null)
                        ? null
                        : () => _runTrace('lens', _runLensTrace),
                  ),
                  const SizedBox(height: 10),
                ],

                // C2PA tile
                _InlineTraceResult(
                  icon: Icons.verified_user_outlined,
                  label: 'C2PA Credentials',
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

              // ── SIMILAR IMAGERY FOUND ────────────────────────────────────
              // Supplementary component shown after the classification result, for
              // both fresh analyses and history records. Derived ONLY from the
              // source-trace platform names; never affects the Authentic/Manipulated
              // decision. Falls back to "No visually similar imagery found online."
              // when nothing is identified. Suppressed for confirmed AI-generated
              // media (a synthesized image has no real web origin) and for genuine
              // camera-hardware captures (the origin is the device itself).
              if (!report.isAiGenerated && !report.isCameraOriginal)
                _buildPossibleSource(),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline auto-displayed trace result tile
// Shows a loading spinner → then result status + summary inline.
// Includes a small Re-run icon for manual refresh.
// ─────────────────────────────────────────────────────────────────────────────
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
    // Neutral informational colours — trace results never imply an
    // Authentic/Manipulated verdict (that comes only from the CNN-RNN model).
    final Color statusColor = result == null
        ? DeepGuardColors.textMuted
        : result!.status == 'found'
            ? DeepGuardColors.info
            : result!.status == 'not_found'
                ? DeepGuardColors.textSecondary
                : Colors.orangeAccent;

    final IconData statusIcon = result == null
        ? Icons.hourglass_top
        : result!.status == 'found'
            ? Icons.travel_explore_rounded
            : result!.status == 'not_found'
                ? Icons.remove_circle_outline
                : Icons.error_outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLoading
            ? DeepGuardColors.surfaceDark.withAlpha(80)
            : statusColor.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLoading
              ? DeepGuardColors.primary.withAlpha(50)
              : statusColor.withAlpha(70),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Engine icon
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, color: DeepGuardColors.primary, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label row
                Text(
                  label,
                  style: const TextStyle(
                    color: DeepGuardColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // Status / loading
                if (isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: DeepGuardColors.primary,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Scanning online sources...',
                        style: TextStyle(
                          color: DeepGuardColors.textMuted,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                else if (result != null) ...[
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 13),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          result!.summary,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result!.findings.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...result!.findings.take(2).map((f) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '› $f',
                            style: TextStyle(
                              color: DeepGuardColors.textSecondary,
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        )),
                  ],
                ],
              ],
            ),
          ),
          // Re-run icon
          if (!isLoading)
            GestureDetector(
              onTap: onRerun,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 15,
                  color: onRerun != null
                      ? DeepGuardColors.primary.withAlpha(180)
                      : DeepGuardColors.textMuted.withAlpha(80),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Similar-imagery platform chip
// Shows ONLY a platform name + its icon. It is NOT tappable (no GestureDetector,
// no link) and never exposes a URL, username or any other PII.
// ─────────────────────────────────────────────────────────────────────────────
class _SourceChip extends StatelessWidget {
  final String platform;

  const _SourceChip({required this.platform});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _platformStyle(platform);
    final asset = provenanceLogoAsset(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: asset != null
                ? Image.asset(
                    asset,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(icon, color: color, size: 20),
                  )
                : Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            platform,
            style: const TextStyle(
              color: DeepGuardColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a platform display name to a representative icon and brand colour.
/// Uses only long-standing generic Material icons (brand glyphs were removed
/// from the Flutter SDK), so it stays version-safe. Unknown platforms fall
/// back to a neutral globe icon.
(IconData, Color) _platformStyle(String platform) {
  switch (platform) {
    case 'Facebook':
      return (Icons.people, const Color(0xFF1877F2));
    case 'Instagram':
      return (Icons.camera, const Color(0xFFE4405F));
    case 'Snapchat':
      return (Icons.photo_camera, const Color(0xFFFFFC00));
    case 'TikTok':
      return (Icons.music_note, const Color(0xFF00F2EA));
    case 'X (Twitter)':
      return (Icons.alternate_email, const Color(0xFF1DA1F2));
    case 'YouTube':
      return (Icons.smart_display, const Color(0xFFFF0000));
    case 'Reddit':
      return (Icons.forum, const Color(0xFFFF4500));
    case 'LinkedIn':
      return (Icons.work, const Color(0xFF0A66C2));
    default:
      return (Icons.public, DeepGuardColors.secondary);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Maps a detected source-app / platform name to a bundled brand logo under
// `assets/images/provenance/`. Returns null when no logo ships, so callers fall
// back to a generic Material icon. Substring-matched so vendor variants and the
// "(filename heuristic)" / "(from filename)" suffixes still resolve. This is a
// purely decorative provenance detail rendered fully offline and it NEVER
// affects the CNN-RNN classification.
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
  if (s.contains('instagram') || s.contains('insta_') ||
      s.contains('cdninstagram')) {
    return 'assets/images/provenance/instagram.jpg';
  }
  if (s.contains('twitter') || s.contains('x (twitter)') ||
      s.contains('twimg') || s.contains('t.co')) {
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

// ─────────────────────────────────────────────────────────────────────────────
// Detected-source logo badge (Provenance card)
// Shows the bundled brand logo for the detected generator / capture / editing
// app (ChatGPT, Gemini, Midjourney, CapCut, camera hardware, screen capture,
// Facebook, TikTok, YouTube). When no logo ships it falls back to a brand-
// coloured Material icon. Rendered fully offline and NEVER affects the CNN-RNN
// classification; purely auxiliary provenance detail.
// ─────────────────────────────────────────────────────────────────────────────
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
    final asset = provenanceLogoAsset(sourceApp);
    final (_, aiColor, aiName) = _aiToolLogo(sourceApp);

    final Color color = isAi
        ? aiColor
        : isCamera
            ? DeepGuardColors.primary
            : category == 'Image Editor'
                ? Colors.purpleAccent
                : DeepGuardColors.secondary;
    // AI tools get a cleaned display name; other sources show the detected
    // app label verbatim (e.g. "CapCut Video Editor", "Samsung Camera Capture").
    final String name = isAi ? aiName : sourceApp;
    final String caption = isAi
        ? 'DETECTED GENERATOR'
        : isCamera
            ? 'CAPTURE DEVICE'
            : category == 'Image Editor'
                ? 'EDITING APP'
                : 'DETECTED SOURCE';
    final IconData fallbackIcon = isAi
        ? Icons.auto_awesome
        : isCamera
            ? Icons.camera_alt_outlined
            : category == 'Image Editor'
                ? Icons.brush_outlined
                : Icons.public;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: asset != null
              ? Image.asset(
                  asset,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _logoCircle(fallbackIcon, color),
                )
              : _logoCircle(fallbackIcon, color),
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
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: const TextStyle(
                  color: DeepGuardColors.textMuted,
                  fontSize: 8.5,
                  letterSpacing: 1.1,
                  fontFamily: 'monospace',
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
          color: color.withAlpha(38),
          border: Border.all(color: color.withAlpha(150), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 19),
      );
}

/// Maps a detected AI `sourceApp` string to a representative icon, brand colour
/// and short display name. Substring-matched so vendor variants and the
/// "(filename heuristic)" suffix still resolve. Unknown → neutral sparkle.
(IconData, Color, String) _aiToolLogo(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('openai') || s.contains('dall') || s.contains('chatgpt')) {
    return (Icons.auto_awesome, const Color(0xFF10A37F), 'ChatGPT · DALL·E');
  }
  if (s.contains('gemini') || s.contains('imagen') ||
      s.contains('synthid') || s.contains('deepmind')) {
    return (Icons.psychology, const Color(0xFF4285F4), 'Gemini · Imagen');
  }
  if (s.contains('midjourney') || s.contains('mj-')) {
    return (Icons.waves, const Color(0xFF8B5CF6), 'Midjourney');
  }
  if (s.contains('firefly') || s.contains('adobe')) {
    return (Icons.local_florist, const Color(0xFFFF2D8F), 'Adobe Firefly');
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
  if (s.contains('stable diffusion') || s.contains('comfyui') ||
      s.contains('novelai') || s.contains('a1111') || s.contains('sd-webui')) {
    return (Icons.blur_on, const Color(0xFFA855F7), 'Stable Diffusion');
  }
  if (s.contains('stylegan') || s.contains('nvidia') ||
      s.contains('nvlabs') || s.contains('thispersondoesnotexist')) {
    return (Icons.memory, const Color(0xFF76B900), 'StyleGAN · NVIDIA');
  }
  return (Icons.auto_awesome_motion, DeepGuardColors.secondary,
      'Generative AI');
}
