import 'package:flutter/material.dart';

import '../models/analysis_framing.dart';
import '../theme/app_theme.dart';

/// FramingEvidenceOverlay
///
/// Paints, on top of the media the user submitted, the two rectangles that
/// actually determined their result: the face the on-device detector located,
/// and the square that was cropped and resized to the model's 128x128 input.
///
/// INTEGRITY RULE: These marks show WHAT WAS LOOKED AT. They never claim to
/// show WHERE manipulation was found.
class FramingEvidenceOverlay extends StatelessWidget {
  final AnalysisFraming? framing;
  final Widget child;

  /// The analysed square. Sky cyan rather than green/red so it never implies a verdict.
  static const Color analysedColor = Color(0xFF38BDF8);

  /// The detected face box: a locator for the crop, nothing more.
  static const Color faceColor = Color(0xE6FFFFFF);

  const FramingEvidenceOverlay({
    super.key,
    required this.framing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final f = framing;
    if (f == null || f.frameWidth <= 0 || f.frameHeight <= 0) return child;

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth <= 0 || c.maxHeight <= 0) return child;
      final box = Size(c.maxWidth, c.maxHeight);
      final src = Size(f.frameWidth.toDouble(), f.frameHeight.toDouble());

      final fit = applyBoxFit(BoxFit.contain, src, box);
      final dest = fit.destination;
      if (dest.width <= 0 || dest.height <= 0) return child;

      final imageRect = Rect.fromLTWH(
        (box.width - dest.width) / 2.0,
        (box.height - dest.height) / 2.0,
        dest.width,
        dest.height,
      );

      return Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FramingPainter(
                  framing: f,
                  imageRect: imageRect,
                  scale: dest.width / src.width,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _FramingPainter extends CustomPainter {
  final AnalysisFraming framing;
  final Rect imageRect;
  final double scale;

  const _FramingPainter({
    required this.framing,
    required this.imageRect,
    required this.scale,
  });

  Rect _map(BoxRect r) => Rect.fromLTWH(
        imageRect.left + r.left * scale,
        imageRect.top + r.top * scale,
        r.width * scale,
        r.height * scale,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final analysed = imageRect.intersect(_map(framing.analysedBox));
    if (analysed.isEmpty) return;

    final coversFrame = analysed.width >= imageRect.width - 0.5 &&
        analysed.height >= imageRect.height - 0.5;
    if (!coversFrame) {
      final outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(imageRect),
        Path()..addRect(analysed),
      );
      canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    }

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = FramingEvidenceOverlay.analysedColor;
    canvas.drawRect(analysed, edge);
    _label(
      canvas,
      analysed,
      framing.cropApplied ? 'analysed' : 'whole frame',
      FramingEvidenceOverlay.analysedColor,
      inside: true,
    );

    final face = framing.faceRect;
    if (face == null || !face.isValid) return;
    final mapped = imageRect.intersect(_map(face));
    if (mapped.isEmpty) return;

    canvas.drawRect(
      mapped,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = FramingEvidenceOverlay.faceColor,
    );
    _label(
      canvas,
      mapped,
      'face located',
      FramingEvidenceOverlay.faceColor,
      inside: false,
    );
  }

  void _label(
    Canvas canvas,
    Rect r,
    String text,
    Color color, {
    required bool inside,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (tp.width + 6 > r.width || tp.height + 4 > r.height) return;

    final bg = Paint()..color = const Color(0xD90B0E14);
    final offset = inside
        ? Offset(r.left + 3, r.top + 3)
        : Offset(r.left + 3, r.top - tp.height - 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx - 3, offset.dy - 2, tp.width + 6, tp.height + 4),
        const Radius.circular(3),
      ),
      bg,
    );
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_FramingPainter old) =>
      old.framing != framing ||
      old.imageRect != imageRect ||
      old.scale != scale;
}

/// Companion legend explaining what [FramingEvidenceOverlay] displays.
class FramingEvidenceLegend extends StatelessWidget {
  final AnalysisFraming? framing;
  final Color? mutedColor;

  const FramingEvidenceLegend({
    super.key,
    required this.framing,
    this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final f = framing;
    if (f == null || f.frameWidth <= 0) return const SizedBox.shrink();

    final palette = DeepGuardPalette.of(context);
    final textColor = palette.textSecondary;

    final whatHappened = f.cropApplied
        ? '${f.faceCount} face${f.faceCount == 1 ? '' : 's'} found. '
            'A ${f.analysedBox.width}x${f.analysedBox.height} px square '
            '(${f.coveragePercent.toStringAsFixed(1)}% of the frame) was '
            'cropped and resized to 128x128 — the only pixels the classifier '
            'received.'
        : f.faceFound
            ? 'A face was found but already fills the frame, so nothing was '
                'cropped. The whole ${f.frameWidth}x${f.frameHeight} image was '
                'resized to 128x128.'
            : 'No face was found, so the entire '
                '${f.frameWidth}x${f.frameHeight} frame was resized to 128x128. '
                'A subject that occupies a few percent of the image reaches the '
                'model as a few pixels, which is outside the framing it was '
                'trained on.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _key(
              FramingEvidenceOverlay.analysedColor,
              'region analysed',
              palette,
            ),
            _key(
              palette.isDark
                  ? FramingEvidenceOverlay.faceColor
                  : palette.brandNavy,
              'face located',
              palette,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          whatHappened,
          style: TextStyle(
            color: textColor,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'These marks show what was looked at. They do not locate '
          'manipulation — the classifier returns one verdict for the whole '
          'square, so no region here should be read as the affected area.',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _key(Color color, String label, DeepGuardPalette palette) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
