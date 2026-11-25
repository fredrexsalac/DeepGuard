import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DeepGuard AI Processing Stage Checklist & Animated Status Ring.
///
/// Supports both Light Mode and Dark Mode, respects system reduced-motion
/// preferences (`MediaQuery.disableAnimations`), and accurately reflects 0-based
/// [currentStep] progress without claiming completion early.
class ProcessingAnimation extends StatefulWidget {
  final int currentStep;
  final List<ProcessingStep> steps;
  final bool isCompleted;

  const ProcessingAnimation({
    super.key,
    this.currentStep = 0,
    required this.steps,
    this.isCompleted = false,
  });

  @override
  State<ProcessingAnimation> createState() => _ProcessingAnimationState();
}

class _ProcessingAnimationState extends State<ProcessingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant ProcessingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionPreference();
  }

  void _syncMotionPreference() {
    final reduce = shouldReduceMotion(context) || widget.isCompleted;
    if (reduce && _ringController.isAnimating) {
      _ringController.stop();
    } else if (!reduce && !_ringController.isAnimating) {
      _ringController.repeat();
    }
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final reduceMotion = shouldReduceMotion(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Animated processing ring (or calm static badge when reduced motion)
        ExcludeSemantics(
          child: Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: AnimatedBuilder(
                animation: _ringController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ProcessingRingPainter(
                      progress: reduceMotion ? 0.25 : _ringController.value,
                      primaryColor: widget.isCompleted
                          ? palette.success
                          : palette.primaryButton,
                      accentColor: widget.isCompleted
                          ? palette.success
                          : palette.accent,
                      trackColor: palette.border,
                      isStatic: reduceMotion || widget.isCompleted,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        child: Container(
                          key: ValueKey(widget.isCompleted),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isCompleted
                                ? palette.successContainer
                                : palette.processingContainer,
                          ),
                          child: Icon(
                            widget.isCompleted
                                ? Icons.check_rounded
                                : Icons.face_retouching_natural,
                            color: widget.isCompleted
                                ? palette.successText
                                : palette.primaryText,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Step-by-step truthful stage list
        ...List.generate(widget.steps.length, (index) {
          final step = widget.steps[index];
          final bool stepDone =
              widget.isCompleted || index < widget.currentStep;
          final bool stepActive =
              !widget.isCompleted && index == widget.currentStep;
          final String stateLabel = stepDone
              ? 'Completed'
              : stepActive
                  ? 'In progress'
                  : 'Pending';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Semantics(
              label:
                  'Stage ${index + 1} of ${widget.steps.length}: ${step.title}, $stateLabel.${stepActive ? " ${step.description}" : ""}',
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: stepActive
                      ? palette.processingContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: stepActive
                        ? palette.primary.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stepDone
                              ? palette.successContainer
                              : stepActive
                                  ? palette.primaryButton
                                  : palette.surfaceElevated,
                          border: Border.all(
                            color: stepDone
                                ? palette.success
                                : stepActive
                                    ? palette.primaryButton
                                    : palette.controlBorder,
                            width: 1.4,
                          ),
                        ),
                        child: Center(
                          child: stepDone
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: palette.successText,
                                )
                              : stepActive
                                  ? (reduceMotion
                                      ? Icon(
                                          Icons.more_horiz_rounded,
                                          size: 16,
                                          color: palette.onPrimaryButton,
                                        )
                                      : SizedBox(
                                          width: 13,
                                          height: 13,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: palette.onPrimaryButton,
                                          ),
                                        ))
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: palette.textMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.title,
                              style: TextStyle(
                                color: stepDone || stepActive
                                    ? palette.textPrimary
                                    : palette.textMuted,
                                fontSize: 15,
                                fontWeight: stepActive
                                    ? FontWeight.w700
                                    : (stepDone
                                        ? FontWeight.w600
                                        : FontWeight.w500),
                              ),
                            ),
                            if (stepActive && step.description.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                step.description,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        stateLabel,
                        style: TextStyle(
                          color: stepDone
                              ? palette.successText
                              : stepActive
                                  ? palette.primaryText
                                  : palette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ProcessingRingPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;
  final Color trackColor;
  final bool isStatic;

  const _ProcessingRingPainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
    required this.trackColor,
    required this.isStatic,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 4;
    final innerR = outerR - 8;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerR, trackPaint);

    if (isStatic) {
      final completePaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(center, outerR, completePaint);
      return;
    }

    final startAngle = progress * 2 * pi - pi / 2;
    final arcPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR),
      startAngle,
      pi * 0.85,
      false,
      arcPaint,
    );

    final innerArcPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerR),
      -startAngle,
      pi * 0.55,
      false,
      innerArcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProcessingRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.isStatic != isStatic;
  }
}

class ProcessingStep {
  final String title;
  final String description;

  const ProcessingStep(this.title, this.description);
}
