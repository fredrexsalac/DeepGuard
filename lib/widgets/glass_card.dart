import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A glassmorphism-style card widget with frosted glass effect.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? height;
  final double? width;
  final double borderRadius;
  final List<Color>? gradient;
  final Color? borderColor;
  final bool glow;
  final Color? glowColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.height,
    this.width,
    this.borderRadius = 16,
    this.gradient,
    this.borderColor,
    this.glow = false,
    this.glowColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient != null
            ? LinearGradient(colors: gradient!)
            : null,
        color: gradient != null ? null : DeepGuardColors.glassBg,
        border: Border.all(
          color: borderColor ?? DeepGuardColors.glassBorder,
          width: 0.5,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: (glowColor ?? DeepGuardColors.primary).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(20),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated gradient border card for highlighted sections.
class GradientBorderCard extends StatelessWidget {
  final Widget child;
  final List<Color> borderGradient;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GradientBorderCard({
    super.key,
    required this.child,
    this.borderGradient = DeepGuardColors.primaryGradient,
    this.borderRadius = 16,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius + 2),
        gradient: LinearGradient(colors: borderGradient),
      ),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: DeepGuardColors.surfaceCard,
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}