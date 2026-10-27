import 'package:flutter/material.dart';

import '../models/analysis_framing.dart';

/// FramingEvidenceOverlay
///
/// Paints, on top of the media the user submitted, the two rectangles that
/// actually determined their result: the face the on-device detector located,
/// and the square that was cropped and resized to the model's 128x128 input.
///
/// ── INTEGRITY RULE, DO NOT RELAX ────────────────────────────────────────────
/// These marks show WHAT WAS LOOKED AT. They must never be presented as showing
/// WHERE manipulation was found. `deepguard_image.tflite` is a whole-square
/// classifier: it receives one 128x128 crop and emits one probability, and it
/// contains no localization, no attention map and no region scoring of any kind.
/// A box drawn around a face beneath a MANIPULATED header reads as "this area is
/// fake", which is a claim the system cannot support. Hence:
///   - The colours below are deliberately NOT [DeepGuardColors.authentic] or
///     [DeepGuardColors.fake]. Verdict colours on a geometric mark would imply
///     the mark carries verdict meaning.
///   - [FramingEvidenceLegend] always ends with the sentence that states this.
///   - Nothing here may be rendered on a video result, where no crop exists.
class FramingEvidenceOverlay extends StatelessWidget {
  final AnalysisFraming? framing;
  final Widget child;

  /// The analysed square. Sky rather than green/red — see the rule above.
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
    // No framing means nothing honest can be drawn. Legacy history records and
    // every video result land here, and both get the untouched media.
    if (f == null || f.frameWidth <= 0 || f.frameHeight <= 0) return child;

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth <= 0 || c.maxHeight <= 0) return child;
      final box = Size(c.maxWidth, c.maxHeight);
      final src = Size(f.frameWidth.toDouble(), f.frameHeight.toDouble());

      // The media is laid out with BoxFit.contain, so it is letterboxed inside
      // this box. Mapping image pixels onto widget pixels has to reproduce that
      // letterboxing or every rectangle drifts off the subject.
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

    // Dim everything the classifier never received. On a whole-frame result
    // this covers nothing; on a crop it shows exactly how much was discarded,
    // which is the fact that explains most "why did it miss" questions.
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
    _label(canvas, analysed, framing.cropApplied ? 'analysed' : 'whole frame',
        FramingEvidenceOverlay.analysedColor, inside: true);

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
    _label(canvas, mapped, 'face located',
        FramingEvidenceOverlay.faceColor, inside: false);
  }

  /// Tiny monospace tag. Suppressed when the box is too small to hold it, so a
  /// distant face produces a clean rectangle rather than a smear of text.
  void _label(Canvas canvas, Rect r, String text, Color color,
      {required bool inside}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        // 11px, not 9px: this is real text on a real background, so it carries
        // the same floor as everything else in the app, and 9px was below what
        // anyone can read on a phone. Both labels sit on the opaque
        // 0xCC0B0E14 plate — sky measures ~7:1 and white ~13:1 against it.
        style: TextStyle(
            color: color, fontSize: 11, fontFamily: 'monospace', height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (tp.width + 6 > r.width || tp.height + 4 > r.height) return;

    final bg = Paint()..color = const Color(0xCC0B0E14);
    final offset = inside
        ? Offset(r.left + 2, r.top + 2)
        : Offset(r.left + 2, r.top - tp.height - 4);
    canvas.drawRect(
      Rect.fromLTWH(offset.dx - 2, offset.dy - 1, tp.width + 5, tp.height + 3),
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

/// The caption that makes the overlay's meaning explicit. Ship the overlay and
/// this together; the overlay alone is exactly the ambiguity the rule above
/// exists to prevent.
class FramingEvidenceLegend extends StatelessWidget {
  final AnalysisFraming? framing;
  final Color mutedColor;

  const FramingEvidenceLegend({
    super.key,
    required this.framing,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final f = framing;
    if (f == null || f.frameWidth <= 0) return const SizedBox.shrink();

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
        const SizedBox(height: 10),
        Row(children: [
          _key(FramingEvidenceOverlay.analysedColor, 'region analysed'),
          const SizedBox(width: 14),
          _key(FramingEvidenceOverlay.faceColor, 'face located'),
        ]),
        const SizedBox(height: 6),
        Text(whatHappened,
            style: TextStyle(
                color: mutedColor, fontSize: 11, height: 1.45,
                fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text(
          'These marks show what was looked at. They do not locate '
          'manipulation — the classifier returns one verdict for the whole '
          'square, so no region here should be read as the affected area.',
          style: TextStyle(color: mutedColor, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  Widget _key(Color color, String label) => Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: mutedColor, fontSize: 11, fontFamily: 'monospace')),
      ]);
}
