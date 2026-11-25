import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/analysis_framing.dart';
import '../models/prediction_result.dart';
import '../services/ai_service.dart';
import '../services/preprocessing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/deepguard_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/processing_animation.dart';
import 'upload_screen.dart' show MediaSource;

typedef CustomInferenceRunner = Future<PredictionResult> Function({
  required String id,
  required String filePath,
  required String mediaType,
  required MediaSource source,
  required AnalysisProgressCallback onProgress,
});

/// DeepGuard Processing Screen (Phase 7 & WCAG 2.2 Level AA).
///
/// Displays a polished facial-scanning preview and truthful real-time stage
/// updates driven directly by [AIService] pipeline events:
/// - 6 truthful stages for Image analysis
/// - 9 truthful stages for Video analysis
/// - Measurable progress percentage ONLY when actual units exist (frame sampling)
/// - Indeterminate progress indicator otherwise
/// - Full reduced-motion support, cooperative cancellation, and screen-reader
///   live status announcements.
class ProcessingScreen extends StatefulWidget {
  final String filePath;
  final String mediaType;
  final MediaSource source;
  final void Function(PredictionResult) onComplete;
  final CustomInferenceRunner? customRunner;

  const ProcessingScreen({
    super.key,
    required this.filePath,
    required this.mediaType,
    required this.source,
    required this.onComplete,
    this.customRunner,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _aiService = AIService();
  final _preprocessing = PreprocessingService();

  late final List<ProcessingStep> _steps;
  int _currentStep = 0;
  String _statusTitle = '';
  String _statusDetail = '';
  int? _completedUnits;
  int? _totalUnits;
  BoxRect? _detectedFaceRect;
  int? _frameWidth;
  int? _frameHeight;
  bool _isCompleted = false;
  bool _isCancelled = false;
  int _lastAnnouncedStage = -1;

  bool get _isVideo => widget.mediaType == 'video';

  @override
  void initState() {
    super.initState();
    final table = _isVideo ? AIService.videoStages : AIService.imageStages;
    _steps = [
      for (final (title, detail) in table) ProcessingStep(title, detail),
    ];
    _statusTitle = _steps.first.title;
    _statusDetail = _steps.first.description;
    _startProcessing();
  }

  Future<void> _onProgressUpdate(AnalysisProgressUpdate update) async {
    if (!mounted || _isCancelled) return;
    setState(() {
      _currentStep = update.stageIndex.clamp(0, _steps.length - 1);
      _statusTitle = update.stageTitle;
      _statusDetail = update.stageDetail;
      _completedUnits = update.completedUnits;
      _totalUnits = update.totalUnits;
      if (update.detectedFaceRect != null) {
        _detectedFaceRect = update.detectedFaceRect;
      }
      if (update.frameWidth != null) _frameWidth = update.frameWidth;
      if (update.frameHeight != null) _frameHeight = update.frameHeight;
    });

    // Announce major stage changes politely without spamming per-frame updates
    if (_lastAnnouncedStage != update.stageIndex) {
      _lastAnnouncedStage = update.stageIndex;
      _announcePolite(
        'Stage ${update.stageIndex + 1} of ${_steps.length}: ${update.stageTitle}',
      );
    }

    // Yield a frame so Flutter paints the updated stage before synchronous work
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  void _announcePolite(String message) {
    if (!mounted) return;
    try {
      final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
      SemanticsService.announce(message, direction);
    } catch (_) {
      // Safe fallback in headless test environments
    }
  }

  Future<void> _startProcessing() async {
    final id = _preprocessing.generateProcessingId();

    PredictionResult result;
    if (widget.customRunner != null) {
      result = await widget.customRunner!(
        id: id,
        filePath: widget.filePath,
        mediaType: widget.mediaType,
        source: widget.source,
        onProgress: _onProgressUpdate,
      );
    } else if (_isVideo) {
      result = await _aiService.predictVideo(
        id: id,
        filePath: widget.filePath,
        source: widget.source,
        onProgress: _onProgressUpdate,
      );
    } else {
      result = await _aiService.predictImage(
        id: id,
        filePath: widget.filePath,
        source: widget.source,
        onProgress: _onProgressUpdate,
      );
    }

    if (!mounted || _isCancelled) return;

    if (result.status == PredictionStatus.error) {
      _announcePolite(
        'Analysis failed. ${result.errorMessage ?? "Please try another file."}',
      );
      widget.onComplete(result);
      return;
    }

    setState(() {
      _currentStep = _steps.length - 1;
      _isCompleted = true;
      _statusTitle = 'Analysis complete';
      _statusDetail = 'Opening authenticity report…';
      _completedUnits = null;
      _totalUnits = null;
    });
    _announcePolite('Analysis complete. Opening result screen.');

    final holdMs = shouldReduceMotion(context) ? 0 : 280;
    if (holdMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: holdMs));
    }
    if (mounted && !_isCancelled) {
      widget.onComplete(result);
    }
  }

  void _cancelAnalysis() {
    if (_isCancelled || _isCompleted) return;
    setState(() => _isCancelled = true);
    _announcePolite('Analysis cancelled.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final hasMeasurable = _completedUnits != null &&
        _totalUnits != null &&
        _totalUnits! > 0;
    final measurableFraction = hasMeasurable
        ? (_completedUnits! / _totalUnits!).clamp(0.0, 1.0)
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelAnalysis();
      },
      child: Scaffold(
        backgroundColor: palette.backgroundSecondary,
        appBar: DeepGuardAppBar(
          title: _isVideo ? 'Analyzing Video' : 'Analyzing Image',
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel analysis',
            onPressed: _cancelAnalysis,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Facial-scanning media preview
                MediaScanPreview(
                  filePath: widget.filePath,
                  isVideo: _isVideo,
                  stageTitle: _statusTitle,
                  completedUnits: _completedUnits,
                  totalUnits: _totalUnits,
                  detectedFaceRect: _detectedFaceRect,
                  frameWidth: _frameWidth,
                  frameHeight: _frameHeight,
                  isCompleted: _isCompleted,
                ),
                const SizedBox(height: 18),

                // Live status card (stage transitions announced politely via
                // throttled _announcePolite so TalkBack/VoiceOver never double-reads)
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    label:
                        '$_statusTitle. $_statusDetail. Stage ${_currentStep + 1} of ${_steps.length}.',
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _statusTitle,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.processingContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  hasMeasurable
                                      ? '${(measurableFraction! * 100).round()}%'
                                      : 'Stage ${_currentStep + 1} of ${_steps.length}',
                                  style: TextStyle(
                                    color: palette.primaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _statusDetail,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 14.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              // Numerical progress bar ONLY when measurable
                              // progress is available (Phase 7.3); otherwise
                              // indeterminate!
                              value: _isCompleted ? 1.0 : measurableFraction,
                              minHeight: 6,
                              backgroundColor: palette.surfaceElevated,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _isCompleted
                                    ? palette.success
                                    : palette.processingStatus,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Stage-by-stage checklist card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: ProcessingAnimation(
                    currentStep: _currentStep,
                    steps: _steps,
                    isCompleted: _isCompleted,
                  ),
                ),
                const SizedBox(height: 20),

                // Accessible Cancel button
                OutlinedButton.icon(
                  onPressed: _isCompleted ? null : _cancelAnalysis,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancel Analysis'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Facial-scanning media preview with reduced-motion support
// ─────────────────────────────────────────────────────────────────────────────

class MediaScanPreview extends StatefulWidget {
  final String filePath;
  final bool isVideo;
  final String stageTitle;
  final int? completedUnits;
  final int? totalUnits;
  final BoxRect? detectedFaceRect;
  final int? frameWidth;
  final int? frameHeight;
  final bool isCompleted;

  const MediaScanPreview({
    super.key,
    required this.filePath,
    required this.isVideo,
    this.stageTitle = '',
    this.completedUnits,
    this.totalUnits,
    this.detectedFaceRect,
    this.frameWidth,
    this.frameHeight,
    this.isCompleted = false,
  });

  @override
  State<MediaScanPreview> createState() => _MediaScanPreviewState();
}

class _MediaScanPreviewState extends State<MediaScanPreview>
    with SingleTickerProviderStateMixin {
  static const double _height = 220;

  late final AnimationController _scan;
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    if (widget.isVideo) _loadThumb();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MediaScanPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduce = shouldReduceMotion(context) || widget.isCompleted;
    if (reduce && _scan.isAnimating) {
      _scan.stop();
    } else if (!reduce && !_scan.isAnimating) {
      _scan.repeat(reverse: true);
    }
  }

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
    } catch (_) {}
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final reduceMotion = shouldReduceMotion(context);
    final accent =
        widget.isCompleted ? const Color(0xFF36CA8D) : const Color(0xFF35C9E2);

    return Semantics(
      image: true,
      label: widget.isVideo
          ? 'Video sample preview during authenticity analysis. Current stage: ${widget.stageTitle}.'
          : 'Image sample preview during facial authenticity analysis. Current stage: ${widget.stageTitle}.',
      child: ExcludeSemantics(
        child: Container(
          height: _height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.brandNavy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Media content
                    if (!widget.isVideo)
                      Image.file(
                        File(widget.filePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _placeholderTile(
                          Icons.image_outlined,
                          'Analyzing image…',
                        ),
                      )
                    else if (_thumb != null)
                      Image.memory(
                        _thumb!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _placeholderTile(
                          Icons.videocam_outlined,
                          'Analyzing video…',
                        ),
                      )
                    else
                      _placeholderTile(
                        Icons.movie_creation_outlined,
                        '',
                      ),

                    // Subtle contrast scrim
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.18),
                    ),

                    // Facial-scanning overlay (bounding box + landmarks + smooth scan line)
                    AnimatedBuilder(
                      animation: _scan,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _FacialScanOverlayPainter(
                            scanFraction:
                                reduceMotion ? 0.5 : _scan.value,
                            showMovingScanLine:
                                !reduceMotion && !widget.isCompleted,
                            accentColor: accent,
                            detectedFaceRect: widget.detectedFaceRect,
                            frameWidth: widget.frameWidth,
                            frameHeight: widget.frameHeight,
                          ),
                        );
                      },
                    ),

                    // Truthful video frame-extraction strip (only when real
                    // frame counts are reported!)
                    if (widget.isVideo &&
                        widget.totalUnits != null &&
                        widget.totalUnits! > 0)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 44,
                        child: _buildTruthfulFrameStrip(
                          completed: widget.completedUnits ?? 0,
                          total: widget.totalUnits!,
                          accent: accent,
                        ),
                      ),

                    // Bottom status badge
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.65),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isCompleted
                                  ? Icons.check_circle_rounded
                                  : (widget.detectedFaceRect != null
                                      ? Icons.face_retouching_natural
                                      : Icons.radar_rounded),
                              size: 15,
                              color: accent,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              widget.isCompleted
                                  ? 'Scan Complete'
                                  : (widget.detectedFaceRect != null
                                      ? 'Face Region Located'
                                      : (widget.isVideo
                                          ? 'Analyzing Video Sequence'
                                          : 'Scanning Image')),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTruthfulFrameStrip({
    required int completed,
    required int total,
    required Color accent,
  }) {
    final safeCompleted = completed.clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (int i = 0; i < total; i++) ...[
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: i < safeCompleted
                      ? accent
                      : Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i != total - 1) const SizedBox(width: 3),
          ],
          const SizedBox(width: 8),
          Text(
            '$safeCompleted/$total frames',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderTile(IconData icon, String label) {
    return ColoredBox(
      color: const Color(0xFF101C36),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white54, size: 36),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FacialScanOverlayPainter extends CustomPainter {
  final double scanFraction;
  final bool showMovingScanLine;
  final Color accentColor;
  final BoxRect? detectedFaceRect;
  final int? frameWidth;
  final int? frameHeight;

  const _FacialScanOverlayPainter({
    required this.scanFraction,
    required this.showMovingScanLine,
    required this.accentColor,
    this.detectedFaceRect,
    this.frameWidth,
    this.frameHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Compute either the real detected face bounding box (mapped via BoxFit.contain)
    // or a clean centered facial-detection guide frame.
    Rect targetBox;
    final face = detectedFaceRect;
    if (face != null &&
        face.isValid &&
        frameWidth != null &&
        frameWidth! > 0 &&
        frameHeight != null &&
        frameHeight! > 0) {
      final src = Size(frameWidth!.toDouble(), frameHeight!.toDouble());
      final fitted = applyBoxFit(BoxFit.contain, src, size);
      final dest = fitted.destination;
      final offsetX = (size.width - dest.width) / 2.0;
      final offsetY = (size.height - dest.height) / 2.0;
      final scale = dest.width / src.width;
      targetBox = Rect.fromLTWH(
        offsetX + face.left * scale,
        offsetY + face.top * scale,
        face.width * scale,
        face.height * scale,
      ).intersect(Offset.zero & size);
    } else {
      final boxSide = (size.shortestSide * 0.48).clamp(72.0, 128.0);
      targetBox = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.46),
        width: boxSide,
        height: boxSide * 1.12,
      );
    }

    // Subtle bounding box + corner brackets
    final guidePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(targetBox, const Radius.circular(8)),
      guidePaint,
    );

    final cornerPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final cornerLen = (targetBox.shortestSide * 0.22).clamp(10.0, 20.0);

    void drawCorner(Offset origin, double dx, double dy) {
      canvas.drawLine(origin, origin + Offset(dx, 0), cornerPaint);
      canvas.drawLine(origin, origin + Offset(0, dy), cornerPaint);
    }

    drawCorner(targetBox.topLeft, cornerLen, cornerLen);
    drawCorner(targetBox.topRight, -cornerLen, cornerLen);
    drawCorner(targetBox.bottomLeft, cornerLen, -cornerLen);
    drawCorner(targetBox.bottomRight, -cornerLen, -cornerLen);

    // Subtle facial feature alignment indicators (eyes, nose bridge, mouth)
    final dotPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;
    final cx = targetBox.center.dx;
    final cy = targetBox.center.dy;
    final w = targetBox.width;
    final h = targetBox.height;
    final landmarks = [
      Offset(cx - w * 0.20, cy - h * 0.14),
      Offset(cx + w * 0.20, cy - h * 0.14),
      Offset(cx, cy + h * 0.02),
      Offset(cx - w * 0.15, cy + h * 0.20),
      Offset(cx + w * 0.15, cy + h * 0.20),
    ];
    for (final pt in landmarks) {
      canvas.drawCircle(pt, 2.2, dotPaint);
    }

    // Smooth horizontal scanning line (omitted when reduced motion is enabled)
    if (showMovingScanLine) {
      final lineY = 12 + scanFraction * (size.height - 24);
      final glowRect = Rect.fromLTWH(0, (lineY - 28).clamp(0.0, size.height), size.width, 28);
      final glowPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: 0.0),
            accentColor.withValues(alpha: 0.18),
          ],
        ).createShader(glowRect);
      canvas.drawRect(glowRect, glowPaint);

      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            accentColor.withValues(alpha: 0.85),
            accentColor,
            accentColor.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, lineY, size.width, 2));
      canvas.drawRect(Rect.fromLTWH(0, lineY - 1, size.width, 2), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FacialScanOverlayPainter oldDelegate) {
    return oldDelegate.scanFraction != scanFraction ||
        oldDelegate.showMovingScanLine != showMovingScanLine ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.detectedFaceRect != detectedFaceRect;
  }
}
