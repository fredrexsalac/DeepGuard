import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../theme/app_theme.dart';
import '../widgets/processing_animation.dart';
import '../widgets/glass_card.dart';
import '../widgets/deepguard_app_bar.dart';
import '../services/ai_service.dart';
import '../services/preprocessing_service.dart';
import '../models/prediction_result.dart';
import 'upload_screen.dart' show MediaSource;

/// DeepGuard Processing Screen
///
/// Runs the full inference pipeline and shows live step-by-step status text.
///
/// IMAGE pipeline:
///   1. Loading AI model
///   2. Analyzing image…
///   3. Running CNN extractor…
///   4. Hybrid CNN-RNN inference…
///   5. Neuro-symbolic analysis…
///
/// VIDEO pipeline:
///   1. Loading AI model
///   2. Extracting video frames…
///   3. Preparing sequence…
///   4. Analyzing video…
///   5. Generating result…
class ProcessingScreen extends StatefulWidget {
  final String filePath;
  final String mediaType;
  final MediaSource source;
  final void Function(PredictionResult) onComplete;

  const ProcessingScreen({
    super.key,
    required this.filePath,
    required this.mediaType,
    required this.source,
    required this.onComplete,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  int _currentStep = 0;
  String _statusText = 'Initializing AI engine…';

  final _aiService     = AIService();
  final _preprocessing = PreprocessingService();

  // Steps are defined per media type at runtime
  late final List<ProcessingStep> _steps;

  @override
  void initState() {
    super.initState();

    if (widget.mediaType == 'video') {
      _steps = const [
        ProcessingStep('Loading Model',       'Initializing AI engine…'),
        ProcessingStep('Extracting Frames',   'Extracting video frames…'),
        ProcessingStep('Preparing Sequence',  'Preparing 10-frame sequence…'),
        ProcessingStep('Running Inference',   'Analyzing video…'),
        ProcessingStep('Generating Result',   'Generating result…'),
      ];
    } else {
      _steps = const [
        ProcessingStep('Loading Model',       'Initializing AI engine…'),
        ProcessingStep('Preprocessing',       'Analyzing image…'),
        ProcessingStep('Extracting Features', 'Running CNN extractor…'),
        ProcessingStep('Running Prediction',  'Hybrid CNN-RNN inference…'),
        ProcessingStep('Generating Result',   'Neuro-symbolic analysis…'),
      ];
    }

    _startProcessing();
  }

  Future<void> _startProcessing() async {
    final id = _preprocessing.generateProcessingId();
    final sw = Stopwatch()..start();

    await _advance(0, _steps[0].description);

    PredictionResult result;
    if (widget.mediaType == 'video') {
      await _advance(1, 'Extracting video frames…');
      await _advance(2, 'Preparing 10-frame sequence…');
      await _advance(3, 'Analyzing video…');

      result = await _aiService.predictVideo(
          id: id, filePath: widget.filePath, source: widget.source);

      await _advance(4, 'Generating result…');
    } else {
      await _advance(1, 'Analyzing image…');
      await _advance(2, 'Running CNN extractor…');
      await _advance(3, 'Hybrid CNN-RNN inference…');

      result = await _aiService.predictImage(
          id: id, filePath: widget.filePath, source: widget.source);

      await _advance(4, 'Neuro-symbolic analysis…');
    }

    // Hold the scan animation briefly so the sweep reads as part of the flow
    // before the result is revealed. This is a UI pacing delay ONLY — it never
    // touches the model, the inference, or the reported confidence value.
    const minScanMs = 2200;
    final remaining = minScanMs - sw.elapsedMilliseconds;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }
    if (mounted) widget.onComplete(result);
  }

  Future<void> _advance(int step, String status) async {
    if (!mounted) return;
    setState(() {
      _currentStep = step;
      _statusText  = status;
    });
    // Small yield so the UI repaints before heavy work begins
    await Future.delayed(const Duration(milliseconds: 40));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const DeepGuardAppBar(title: 'Processing'),
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
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // ── Live scan preview of the submitted media ──
                  MediaScanPreview(
                    filePath: widget.filePath,
                    isVideo: widget.mediaType == 'video',
                  ),
                  const SizedBox(height: 24),
                  ProcessingAnimation(
                    currentStep: _currentStep + 1,
                    steps: _steps,
                  ),
                  const SizedBox(height: 24),
                  GlassCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  DeepGuardColors.primary.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Processing…',
                              style: TextStyle(
                                color: DeepGuardColors.primary.withValues(alpha: 0.8),
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: DeepGuardColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ((_currentStep + 1) / _steps.length)
                                .clamp(0.0, 1.0),
                            backgroundColor: DeepGuardColors.surfaceLight,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              DeepGuardColors.primary.withValues(alpha: 0.6),
                            ),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Step ${_currentStep + 1} of ${_steps.length}',
                          style: const TextStyle(
                            color: DeepGuardColors.textMuted,
                            fontSize: 11,
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
// Live media scan preview
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the submitted media with a glowing scan line sweeping top-to-bottom so
/// the user perceives the file being "scanned" as part of the analysis flow.
/// Purely decorative — it does NOT affect inference or the reported confidence.
class MediaScanPreview extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const MediaScanPreview({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<MediaScanPreview> createState() => _MediaScanPreviewState();
}

class _MediaScanPreviewState extends State<MediaScanPreview>
    with TickerProviderStateMixin {
  static const double _height = 220;
  static const int _frameSlots = 10; // matches the model's 10-frame input

  late final AnimationController _scan;    // sweeping scan line (loops)
  late final AnimationController _extract; // one-shot frame-extraction fill
  Uint8List? _thumb;                        // representative video frame

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
    _extract = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    if (widget.isVideo) _loadThumb();
  }

  /// Fetches ONE representative frame purely for the preview. Decorative only —
  /// the real 10-frame extraction happens independently in the model pipeline.
  Future<void> _loadThumb() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        maxHeight: 480,
        timeMs: 0,
        quality: 60,
      );
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() => _thumb = bytes);
      }
    } catch (_) {
      // If the frame can't be decoded we simply keep the icon tile.
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    _extract.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: _height,
        width: double.infinity,
        color: DeepGuardColors.surfaceDark,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── The media itself ──
            if (!widget.isVideo)
              Image.file(
                File(widget.filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderTile(
                    Icons.broken_image_outlined, 'Preview unavailable'),
              )
            else if (_thumb != null)
              Image.memory(
                _thumb!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _placeholderTile(Icons.videocam_outlined, 'Video frame'),
              )
            else
              _placeholderTile(
                  Icons.movie_creation_outlined, 'Extracting frame…'),

            // subtle scanner tint
            Container(color: DeepGuardColors.primary.withValues(alpha: 0.05)),

            // ── Animated sweep ──
            AnimatedBuilder(
              animation: _scan,
              builder: (context, _) {
                final lineY = _scan.value * _height;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // trailing translucent band above the line
                    Positioned(
                      top: (lineY - 80).clamp(0.0, _height),
                      left: 0,
                      right: 0,
                      height: 80,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              DeepGuardColors.primary.withValues(alpha: 0.0),
                              DeepGuardColors.primary.withValues(alpha: 0.20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // the glowing scan line
                    Positioned(
                      top: lineY - 1,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: DeepGuardColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: DeepGuardColors.primary
                                  .withValues(alpha: 0.85),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Corner brackets ──
            ..._cornerBrackets(),

            // ── Frame-extraction filmstrip (video only) ──
            if (widget.isVideo)
              Positioned(
                left: 12,
                right: 12,
                bottom: 38,
                child: AnimatedBuilder(
                  animation: _extract,
                  builder: (context, _) {
                    final filled = (_extract.value * _frameSlots)
                        .round()
                        .clamp(0, _frameSlots);
                    return Row(
                      children: [
                        for (int i = 0; i < _frameSlots; i++) ...[
                          Expanded(
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: i < filled
                                    ? DeepGuardColors.primary
                                    : Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  width: 1,
                                  color: DeepGuardColors.primary.withValues(
                                      alpha: i < filled ? 1.0 : 0.4),
                                ),
                              ),
                            ),
                          ),
                          if (i != _frameSlots - 1) const SizedBox(width: 3),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          '$filled/$_frameSlots',
                          style: const TextStyle(
                            color: DeepGuardColors.primary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // ── Scanning label ──
            Positioned(
              left: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: DeepGuardColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: DeepGuardColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isVideo ? 'EXTRACTING FRAMES' : 'SCANNING IMAGE',
                      style: const TextStyle(
                        color: DeepGuardColors.primary,
                        fontSize: 10,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderTile(IconData icon, String label) {
    return Container(
      color: DeepGuardColors.surfaceDark,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: DeepGuardColors.primary.withValues(alpha: 0.5),
                size: 40),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: DeepGuardColors.textMuted.withValues(alpha: 0.7),
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  List<Widget> _cornerBrackets() {
    const double len = 22;
    const double thick = 2;
    const double pad = 8;
    Widget bracket(Alignment a) {
      final top = a.y < 0, bottom = a.y > 0, left = a.x < 0, right = a.x > 0;
      return Positioned(
        top: top ? pad : null,
        bottom: bottom ? pad : null,
        left: left ? pad : null,
        right: right ? pad : null,
        child: Container(
          width: len,
          height: len,
          decoration: BoxDecoration(
            border: Border(
              top: top
                  ? BorderSide(color: DeepGuardColors.primary, width: thick)
                  : BorderSide.none,
              bottom: bottom
                  ? BorderSide(color: DeepGuardColors.primary, width: thick)
                  : BorderSide.none,
              left: left
                  ? BorderSide(color: DeepGuardColors.primary, width: thick)
                  : BorderSide.none,
              right: right
                  ? BorderSide(color: DeepGuardColors.primary, width: thick)
                  : BorderSide.none,
            ),
          ),
        ),
      );
    }
    return [
      bracket(Alignment.topLeft),
      bracket(Alignment.topRight),
      bracket(Alignment.bottomLeft),
      bracket(Alignment.bottomRight),
    ];
  }
}
