import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DeepGuard AI Processing Animation
///
/// Shows neural network-inspired animated rings with step-by-step
/// processing status, mirroring the Django processing.html template.
class ProcessingAnimation extends StatefulWidget {
  final int currentStep;
  final List<ProcessingStep> steps;

  const ProcessingAnimation({
    super.key,
    this.currentStep = 0,
    this.steps = const [
      ProcessingStep('Loading Model', 'Initializing AI engine...'),
      ProcessingStep('Preprocessing', 'Analyzing media file...'),
      ProcessingStep('Extracting Features', 'Running CNN extractor...'),
      ProcessingStep('Running Prediction', 'Hybrid CNN-RNN inference...'),
      ProcessingStep('Generating Results', 'Neuro-symbolic analysis...'),
    ],
  });

  @override
  State<ProcessingAnimation> createState() => _ProcessingAnimationState();
}

class _ProcessingAnimationState extends State<ProcessingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Neural network animation rings
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring 1
                  _buildRing(140, _pulseController.value * 0.3, DeepGuardColors.primary),
                  // Outer ring 2
                  _buildRing(110, 0.3 + _pulseController.value * 0.3, DeepGuardColors.secondary),
                  // Outer ring 3
                  _buildRing(80, 0.6 + _pulseController.value * 0.3, DeepGuardColors.accent),
                  // Core icon
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: DeepGuardColors.primaryGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: DeepGuardColors.primary.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.visibility,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        // Step indicators
        ...List.generate(widget.steps.length, (index) {
          final step = widget.steps[index];
          final isActive = index == widget.currentStep;
          final isCompleted = index < widget.currentStep;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? DeepGuardColors.primary.withValues(alpha: 0.2)
                        : isActive
                            ? DeepGuardColors.primary.withValues(alpha: 0.3)
                            : DeepGuardColors.surfaceLight,
                    border: Border.all(
                      color: isCompleted || isActive
                          ? DeepGuardColors.primary
                          : DeepGuardColors.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 14, color: DeepGuardColors.primary)
                        : isActive
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: DeepGuardColors.primary,
                                ),
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: DeepGuardColors.textMuted,
                                  fontWeight: FontWeight.w600,
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
                          color: isCompleted || isActive
                              ? DeepGuardColors.textPrimary
                              : DeepGuardColors.textMuted,
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (isActive)
                        Text(
                          step.description,
                          style: const TextStyle(
                            color: DeepGuardColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isCompleted)
                  const Icon(Icons.check_circle, size: 16, color: DeepGuardColors.primary),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRing(double size, double opacity, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity * 0.5),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.85,
          height: size * 0.85,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: opacity * 0.2),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class ProcessingStep {
  final String title;
  final String description;

  const ProcessingStep(this.title, this.description);
}