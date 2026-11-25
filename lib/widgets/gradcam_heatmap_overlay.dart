import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/gradcam_evidence.dart';
import '../theme/app_theme.dart';

/// Renders a real, model-prescribed Grad-CAM heatmap (`64x64` normalized `[0, 1]`)
/// directly over an analyzed image or video frame using a scientific Jet-like
/// perceptual colormap (cool blue -> cyan -> yellow -> red).
class GradCamHeatmapOverlay extends StatelessWidget {
  final List<double> heatmap;
  final int width;
  final int height;
  final double opacity;
  final Widget child;

  const GradCamHeatmapOverlay({
    super.key,
    required this.heatmap,
    this.width = 64,
    this.height = 64,
    this.opacity = 0.58,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (heatmap.length != width * height || width <= 0 || height <= 0) {
      return child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GradCamPainter(
                heatmap: heatmap,
                gridW: width,
                gridH: height,
                opacity: opacity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GradCamPainter extends CustomPainter {
  final List<double> heatmap;
  final int gridW;
  final int gridH;
  final double opacity;

  const _GradCamPainter({
    required this.heatmap,
    required this.gridW,
    required this.gridH,
    required this.opacity,
  });

  /// Maps normalized activation `v` in `[0.0, 1.0]` to an intuitive
  /// transparency-weighted Jet colormap so low-activation background stays clear
  /// while high-gradient model focus glows amber-red.
  static Color _heatColor(double v, double maxOpacity) {
    final t = v.clamp(0.0, 1.0);
    if (t < 0.08) return Colors.transparent;

    final double r;
    final double g;
    final double b;
    if (t < 0.35) {
      final k = (t - 0.08) / 0.27;
      r = 0.0;
      g = k;
      b = 1.0;
    } else if (t < 0.65) {
      final k = (t - 0.35) / 0.30;
      r = k;
      g = 1.0;
      b = 1.0 - k;
    } else {
      final k = (t - 0.65) / 0.35;
      r = 1.0;
      g = (1.0 - k).clamp(0.0, 1.0);
      b = 0.0;
    }

    final alpha = ((0.22 + 0.78 * t) * maxOpacity).clamp(0.0, 1.0);
    return Color.fromRGBO(
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
      alpha,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final cellW = size.width / gridW;
    final cellH = size.height / gridH;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < gridH; y++) {
      final rowOffset = y * gridW;
      for (var x = 0; x < gridW; x++) {
        final v = heatmap[rowOffset + x];
        if (v < 0.08) continue;
        paint.color = _heatColor(v, opacity);
        canvas.drawRect(
          Rect.fromLTWH(
            x * cellW,
            y * cellH,
            cellW + 0.6,
            cellH + 0.6,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GradCamPainter oldDelegate) =>
      oldDelegate.heatmap != heatmap ||
      oldDelegate.opacity != opacity ||
      oldDelegate.gridW != gridW ||
      oldDelegate.gridH != gridH;
}

/// Interactive Grad-CAM card for **Image** results and **Top 3 Video Key Frames**.
class GradCamSection extends StatefulWidget {
  final GradCamEvidence gradCam;
  final bool isVideo;

  const GradCamSection({
    super.key,
    required this.gradCam,
    required this.isVideo,
  });

  @override
  State<GradCamSection> createState() => _GradCamSectionState();
}

class _GradCamSectionState extends State<GradCamSection> {
  bool _showOverlay = true;

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final gc = widget.gradCam;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.isVideo
                        ? 'Key Video Frames (Grad-CAM)'
                        : 'Grad-CAM Model Explanation',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                toggled: _showOverlay,
                label: _showOverlay
                    ? 'Hide Grad-CAM heatmap overlay'
                    : 'Show Grad-CAM heatmap overlay',
                child: FilterChip(
                  selected: _showOverlay,
                  onSelected: (v) => setState(() => _showOverlay = v),
                  label: Text(_showOverlay ? 'Heatmap On' : 'Heatmap Off'),
                  avatar: Icon(
                    Icons.gradient_rounded,
                    size: 16,
                    color: _showOverlay
                        ? palette.primaryText
                        : palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.isVideo
                ? 'Top ${gc.topVideoFrames.length} most influential frames selected out of 10 sampled frames based on model gradients (${gc.layerName}) for the ${gc.targetLabel} verdict.'
                : 'Regions in the analyzed 128×128 input with the strongest positive gradient (${gc.layerName}) supporting the ${gc.targetLabel} verdict.',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),

          if (widget.isVideo && gc.topVideoFrames.isNotEmpty)
            _buildVideoFramesGrid(gc, palette)
          else
            _buildImageGradCamPreview(gc, palette),

          const SizedBox(height: 12),
          _ColorScaleLegend(palette: palette),
        ],
      ),
    );
  }

  Widget _buildImageGradCamPreview(
    GradCamEvidence gc,
    DeepGuardPalette palette,
  ) {
    final Uint8List? cropBytes = gc.analyzedCropBytes;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          height: 220,
          color: palette.brandNavy,
          child: Semantics(
            image: true,
            label:
                'Grad-CAM heatmap highlighting model attention for ${gc.targetLabel} verdict.',
            child: _showOverlay
                ? GradCamHeatmapOverlay(
                    heatmap: gc.heatmap,
                    width: gc.width,
                    height: gc.height,
                    child: cropBytes != null
                        ? Image.memory(cropBytes, fit: BoxFit.cover)
                        : const SizedBox.expand(),
                  )
                : (cropBytes != null
                    ? Image.memory(cropBytes, fit: BoxFit.cover)
                    : const SizedBox.expand()),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoFramesGrid(GradCamEvidence gc, DeepGuardPalette palette) {
    final frames = gc.topVideoFrames;
    final totalEnergy = frames.fold<double>(
      0.0,
      (sum, f) => sum + (f.importanceScore > 0 ? f.importanceScore : 0.0),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final stack = constraints.maxWidth < 310 || textScale > 1.25;

        final cards = <Widget>[
          for (var rank = 0; rank < frames.length; rank++)
            _VideoGradCamTile(
              rank: rank + 1,
              frame: frames[rank],
              sharePercent: totalEnergy > 0
                  ? (frames[rank].importanceScore / totalEnergy) * 100
                  : (100 / frames.length),
              width: gc.width,
              height: gc.height,
              showOverlay: _showOverlay,
              palette: palette,
            ),
        ];

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VideoGradCamTile extends StatelessWidget {
  final int rank;
  final VideoFrameGradCam frame;
  final double sharePercent;
  final int width;
  final int height;
  final bool showOverlay;
  final DeepGuardPalette palette;

  const _VideoGradCamTile({
    required this.rank,
    required this.frame,
    required this.sharePercent,
    required this.width,
    required this.height,
    required this.showOverlay,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = frame.thumbnailBytes;
    return Semantics(
      label:
          'Key frame rank $rank, Frame ${frame.frameIndex + 1} of ${frame.totalFrames}, '
          '${sharePercent.toStringAsFixed(0)} percent top-frame weight, with Grad-CAM heatmap.',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: palette.brandNavy,
                  child: showOverlay
                      ? GradCamHeatmapOverlay(
                          heatmap: frame.heatmap,
                          width: width,
                          height: height,
                          child: thumb != null
                              ? Image.memory(thumb, fit: BoxFit.cover)
                              : const SizedBox.expand(),
                        )
                      : (thumb != null
                          ? Image.memory(thumb, fit: BoxFit.cover)
                          : const SizedBox.expand()),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Frame ${frame.frameIndex + 1}/${frame.totalFrames}',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Top #$rank · ${sharePercent.toStringAsFixed(0)}%',
              style: TextStyle(
                color: palette.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorScaleLegend extends StatelessWidget {
  final DeepGuardPalette palette;

  const _ColorScaleLegend({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Low',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0055FF),
                  Color(0xFF00E5FF),
                  Color(0xFFFFFF00),
                  Color(0xFFFF1744),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'High Focus',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
