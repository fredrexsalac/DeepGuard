import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated confidence gauge widget for displaying prediction confidence.
class ConfidenceGauge extends StatelessWidget {
  final double confidence; // 0.0 to 1.0
  final double size;
  final Color? color;

  const ConfidenceGauge({
    super.key,
    required this.confidence,
    this.size = 180,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (confidence * 100).clamp(0.0, 100.0).toDouble();
    final gaugeColor = color ?? _getGaugeColor(confidence);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          percentage: percentage,
          color: gaugeColor,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.bold,
                  color: gaugeColor,
                  shadows: [
                    Shadow(
                      color: gaugeColor.withValues(alpha: 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Prediction\nConfidence',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size * 0.062,
                  color: DeepGuardColors.textMuted,
                  letterSpacing: 1.2,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getGaugeColor(double conf) {
    if (conf >= 0.7) return DeepGuardColors.authentic;
    if (conf >= 0.4) return DeepGuardColors.warning;
    return DeepGuardColors.fake;
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color color;

  _GaugePainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 14.0;

    // Background arc
    final bgPaint = Paint()
      ..color = DeepGuardColors.surfaceLight.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Foreground arc (animated segment)
    final progress = percentage / 100;
    final sweepAngle = 2 * pi * progress;

    final fgPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.6), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
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

    // Outer glow ring
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8;

    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage;
}