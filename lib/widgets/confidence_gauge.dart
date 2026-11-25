import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Accessible, text-scale-resilient Model Confidence gauge.
///
/// Clearly labels the single-file prediction score as **Model Confidence**
/// (never accuracy) and scales cleanly up to 200%+ system font sizes without
/// text clipping or ring overflow.
class ConfidenceGauge extends StatelessWidget {
  final double confidence; // 0.0 to 1.0
  final double size;
  final Color? color;
  final Color? textColor;

  const ConfidenceGauge({
    super.key,
    required this.confidence,
    this.size = 164,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final percentage = (confidence * 100).clamp(0.0, 100.0).toDouble();
    final arcColor = color ?? _defaultArcColor(confidence, palette);
    final labelColor = textColor ?? palette.textSafe(arcColor);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final placeCaptionOutside = textScale > 1.35;

    return Semantics(
      label: 'Model Confidence: ${percentage.toStringAsFixed(1)} percent',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _GaugePainter(
                  percentage: percentage,
                  color: arcColor,
                  trackColor: palette.border,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: labelColor,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (!placeCaptionOutside) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Model\nConfidence',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (placeCaptionOutside) ...[
              const SizedBox(height: 8),
              Text(
                'Model Confidence',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _defaultArcColor(double conf, DeepGuardPalette palette) {
    if (conf >= 0.7) return palette.realClassification;
    if (conf >= 0.4) return palette.warning;
    return palette.aiClassification;
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.percentage,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 12.0;

    final bgPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final progress = (percentage / 100).clamp(0.0, 1.0);
    final sweepAngle = 2 * pi * progress;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
