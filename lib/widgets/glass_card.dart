import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A clean, theme-aware surface card for DeepGuard Light and Dark modes.
///
/// Retains the [GlassCard] class name and parameters so existing screens work
/// seamlessly while replacing low-contrast translucent glass edges with clear,
/// WCAG-compliant card boundaries and expandable height.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? height;
  final double? width;
  final double borderRadius;
  final List<Color>? gradient;
  final Color? borderColor;
  final Color? backgroundColor;
  final bool glow;
  final Color? glowColor;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.height,
    this.width,
    this.borderRadius = 14,
    this.gradient,
    this.borderColor,
    this.backgroundColor,
    this.glow = false,
    this.glowColor,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final isLight = !palette.isDark;
    final resolvedBorder = borderColor ??
        (onTap != null ? palette.controlBorder : palette.border);

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: content,
          ),
        ),
      );
      if (semanticLabel != null) {
        content = Semantics(
          button: true,
          label: semanticLabel,
          child: content,
        );
      }
    }

    return Container(
      height: height,
      width: width,
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient != null ? LinearGradient(colors: gradient!) : null,
        color: gradient != null ? null : (backgroundColor ?? palette.surface),
        border: Border.all(
          color: resolvedBorder,
          width: glow ? 1.5 : 1.0,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: (glowColor ?? palette.primary)
                      .withValues(alpha: isLight ? 0.14 : 0.22),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      ),
    );
  }
}

/// Highlighted border card using DeepGuard's brand palette.
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
    this.borderRadius = 14,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius + 1.5),
        gradient: LinearGradient(colors: borderGradient),
      ),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: palette.surface,
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(18),
          child: child,
        ),
      ),
    );
  }
}
