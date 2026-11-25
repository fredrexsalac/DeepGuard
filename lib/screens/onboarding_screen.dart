import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding slide data — clear, user-friendly presentation
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingSlideData {
  final String stepLabel;
  final String headline;
  final String body;

  const _OnboardingSlideData({
    required this.stepLabel,
    required this.headline,
    required this.body,
  });
}

const List<_OnboardingSlideData> _kPages = [
  _OnboardingSlideData(
    stepLabel: 'Welcome to DeepGuard',
    headline: 'Assess Media Authenticity',
    body:
        'Analyze photos and videos directly on your device to check for signs of AI generation or facial manipulation.',
  ),
  _OnboardingSlideData(
    stepLabel: 'Images & Videos',
    headline: 'Upload or Capture Media',
    body:
        'Select an image or video from your gallery, or capture a new sample with your camera and preview it before starting analysis.',
  ),
  _OnboardingSlideData(
    stepLabel: 'Transparent Analysis',
    headline: 'Clear REAL & A.I. Results',
    body:
        'Follow real-time facial and frame analysis stages and review clear REAL or A.I. verdicts with Grad-CAM visual explanations.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen — biometric reticle & cyan forensic scan launch
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _scanSweep;
  late final Animation<double> _ringPulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    _scale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _scanSweep = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.85, curve: Curves.easeInOutCubic),
    );
    _ringPulse = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.90, curve: Curves.easeOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onDone();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final reduceMotion = shouldReduceMotion(context);

    final emblem = ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final sweep = reduceMotion ? 0.5 : _scanSweep.value;
          final pulse = reduceMotion ? 1.0 : _ringPulse.value;
          return SizedBox(
            width: 148,
            height: 148,
            child: CustomPaint(
              painter: _SplashReticlePainter(
                progress: pulse,
                scanProgress: sweep,
                primaryColor: palette.primary,
                accentColor: palette.accent,
              ),
              child: Center(
                child: ScaleTransition(
                  scale: reduceMotion ? const AlwaysStoppedAnimation(1.0) : _scale,
                  child: Container(
                    width: 102,
                    height: 102,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: palette.accent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withValues(alpha: 0.24),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/deepguard_logo.png',
                            fit: BoxFit.cover,
                          ),
                          if (!reduceMotion)
                            CustomPaint(
                              painter: _ScanBeamPainter(
                                progress: sweep,
                                accentColor: palette.accent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    return Scaffold(
      backgroundColor: palette.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                emblem,
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    'DEEPGUARD',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI-Powered Deepfake Detection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashReticlePainter extends CustomPainter {
  final double progress;
  final double scanProgress;
  final Color primaryColor;
  final Color accentColor;

  const _SplashReticlePainter({
    required this.progress,
    required this.scanProgress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (size.width / 2) - 4;

    // Subtle pulsing radar ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = primaryColor.withValues(alpha: (0.45 * (1.0 - progress * 0.45)).clamp(0.1, 0.5));
    canvas.drawCircle(center, outerRadius * (0.88 + 0.12 * progress), ringPaint);

    // Rotating dashed forensic arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = accentColor.withValues(alpha: 0.78);
    final startAngle = scanProgress * math.pi * 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius - 6),
      startAngle,
      math.pi * 0.55,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius - 6),
      startAngle + math.pi,
      math.pi * 0.55,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashReticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.scanProgress != scanProgress;
}

class _ScanBeamPainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  const _ScanBeamPainter({
    required this.progress,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01 || progress >= 0.99) return;
    final y = size.height * progress;
    final beamRect = Rect.fromLTWH(0, (y - 16).clamp(0.0, size.height), size.width, 32);
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.0),
          accentColor.withValues(alpha: 0.45),
          accentColor.withValues(alpha: 0.0),
        ],
      ).createShader(beamRect);
    canvas.drawRect(beamRect, beamPaint);

    final linePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.92)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanBeamPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding carousel — deepfake-forensics animations + full accessibility
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _slideAnimController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Finite per-slide animation cycle so motion feels alive without blocking
    // automated test pumpAndSettle().
    _slideAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    )..forward();
  }

  @override
  void dispose() {
    _slideAnimController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    if (!shouldReduceMotion(context)) {
      _slideAnimController
        ..reset()
        ..forward();
    }
  }

  void _next() {
    if (_page < _kPages.length - 1) {
      if (shouldReduceMotion(context)) {
        _pageController.jumpToPage(_page + 1);
      } else {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DeepGuardPalette.of(context);
    final isLastPage = _page == _kPages.length - 1;
    final reduceMotion = shouldReduceMotion(context);

    return Scaffold(
      backgroundColor: palette.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with accessible Skip button (omitted on final slide so
            // screen readers never focus an invisible element)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
              child: Row(
                children: [
                  Semantics(
                    label: 'Onboarding step ${_page + 1} of ${_kPages.length}',
                    child: ExcludeSemantics(
                      child: Text(
                        'Step ${_page + 1} of ${_kPages.length}',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!isLastPage)
                    TextButton(
                      onPressed: widget.onDone,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 48),
                      ),
                      child: const Text('Skip'),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),

            // Slide pages — scrollable to support 200%+ dynamic font scaling
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _kPages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final slide = _kPages[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),
                        ExcludeSemantics(
                          child: AnimatedBuilder(
                            animation: _slideAnimController,
                            builder: (context, _) {
                              final t = reduceMotion
                                  ? 0.72
                                  : _slideAnimController.value;
                              return _ForensicOnboardingHero(
                                slideIndex: index,
                                progress: t,
                                palette: palette,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 26),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surfaceElevated,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: palette.border),
                          ),
                          child: Text(
                            slide.stepLabel,
                            style: TextStyle(
                              color: palette.primaryText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            slide.headline,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Progress bar & primary navigation button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_kPages.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 28 : 10,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: active
                                ? palette.primaryButton
                                : palette.border,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(
                        isLastPage
                            ? Icons.shield_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      label: Text(isLastPage ? 'Get Started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom animated deepfake-forensics illustration per onboarding slide.
class _ForensicOnboardingHero extends StatelessWidget {
  final int slideIndex;
  final double progress;
  final DeepGuardPalette palette;

  const _ForensicOnboardingHero({
    required this.slideIndex,
    required this.progress,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      height: 172,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.processingContainer,
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _OnboardingHeroPainter(
            slideIndex: slideIndex,
            progress: progress,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

class _OnboardingHeroPainter extends CustomPainter {
  final int slideIndex;
  final double progress;
  final DeepGuardPalette palette;

  const _OnboardingHeroPainter({
    required this.slideIndex,
    required this.progress,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Subtle forensic grid lines
    final gridPaint = Paint()
      ..color = palette.primary.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    for (double x = 24; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 24; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (slideIndex == 0) {
      _paintFaceScan(canvas, size, cx, cy);
    } else if (slideIndex == 1) {
      _paintMediaFrames(canvas, size, cx, cy);
    } else {
      _paintGradCamVerdict(canvas, size, cx, cy);
    }
  }

  /// Slide 1: Portrait face mesh + locking corner brackets + cyan laser sweep.
  void _paintFaceScan(Canvas canvas, Size size, double cx, double cy) {
    // Portrait head + shoulders silhouette
    final facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = palette.primaryText;
    canvas.drawCircle(Offset(cx, cy - 10), 26, facePaint);
    final shoulderPath = Path()
      ..moveTo(cx - 34, cy + 44)
      ..quadraticBezierTo(cx, cy + 16, cx + 34, cy + 44);
    canvas.drawPath(shoulderPath, facePaint);

    // Biometric landmark dots
    final dotPaint = Paint()..color = palette.accent;
    for (final pt in [
      Offset(cx - 10, cy - 14),
      Offset(cx + 10, cy - 14),
      Offset(cx, cy - 5),
      Offset(cx - 8, cy + 5),
      Offset(cx + 8, cy + 5),
    ]) {
      canvas.drawCircle(pt, 2.3, dotPaint);
    }

    // Animated corner reticle locking onto face
    final lock = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final half = 48.0 - 6.0 * lock;
    final box = Rect.fromCenter(center: Offset(cx, cy + 4), width: half * 2, height: half * 2);
    _drawCornerBrackets(canvas, box, palette.accent, 14, 2.8);

    // Cyan horizontal scan beam sweeping down and back
    final wave = 0.5 - 0.5 * math.cos(progress * math.pi * 2);
    final beamY = box.top + box.height * wave;
    final beamPaint = Paint()
      ..color = palette.accent.withValues(alpha: 0.9)
      ..strokeWidth = 2.2;
    canvas.drawLine(Offset(box.left + 4, beamY), Offset(box.right - 4, beamY), beamPaint);
  }

  /// Slide 2: Multi-frame video filmstrip + active frame highlight.
  void _paintMediaFrames(Canvas canvas, Size size, double cx, double cy) {
    final shift = (1.0 - Curves.easeOutCubic.transform(progress)) * 18.0;
    final activeIdx = ((progress * 3).floor()).clamp(0, 2);

    for (var i = 0; i < 3; i++) {
      final offset = (i - 1) * 38.0 + shift * (i - 1) * 0.4;
      final isActive = i == activeIdx;
      final cardRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx + offset, cy + (isActive ? -6 : 4)),
          width: isActive ? 54 : 44,
          height: isActive ? 68 : 56,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        cardRect,
        Paint()..color = palette.surface.withValues(alpha: isActive ? 0.96 : 0.72),
      );
      canvas.drawRRect(
        cardRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 2.4 : 1.4
          ..color = isActive ? palette.accent : palette.primary.withValues(alpha: 0.45),
      );

      // Mini face icon inside each frame
      canvas.drawCircle(
        Offset(cx + offset, cy + (isActive ? -12 : 0)),
        isActive ? 9 : 7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = isActive ? palette.primaryText : palette.textMuted,
      );
    }

    // Play/frame indicator pill at bottom
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 48), width: 64, height: 14),
      const Radius.circular(7),
    );
    canvas.drawRRect(pillRect, Paint()..color = palette.brandNavy);
    final fillW = 14.0 + 44.0 * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 29, cy + 44, fillW, 6),
        const Radius.circular(3),
      ),
      Paint()..color = palette.accent,
    );
  }

  /// Slide 3: Grad-CAM thermal focus glow + REAL / A.I. verification badge.
  void _paintGradCamVerdict(Canvas canvas, Size size, double cx, double cy) {
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 6), width: 82, height: 82),
      const Radius.circular(14),
    );
    canvas.drawRRect(frameRect, Paint()..color = palette.brandNavy);

    // Animated Grad-CAM thermal heatmap blobs inside the frame
    final pulse = Curves.easeOut.transform(progress);
    final heatCenter = Offset(cx - 4, cy - 12);
    final heatPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF1744).withValues(alpha: 0.78 * pulse),
          const Color(0xFFFFFF00).withValues(alpha: 0.55 * pulse),
          const Color(0xFF00E5FF).withValues(alpha: 0.28 * pulse),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: heatCenter, radius: 34));
    canvas.drawCircle(heatCenter, 34 * (0.65 + 0.35 * pulse), heatPaint);

    // Face outline over heatmap
    canvas.drawCircle(
      Offset(cx, cy - 10),
      20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Split REAL / A.I. badge below frame
    final realPill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx - 22, cy + 48), width: 38, height: 18),
      const Radius.circular(9),
    );
    final aiPill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + 22, cy + 48), width: 38, height: 18),
      const Radius.circular(9),
    );
    canvas.drawRRect(realPill, Paint()..color = palette.realClassification);
    canvas.drawRRect(aiPill, Paint()..color = palette.aiClassification);
  }

  void _drawCornerBrackets(
    Canvas canvas,
    Rect rect,
    Color color,
    double len,
    double strokeWidth,
  ) {
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(len, 0), p);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, len), p);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-len, 0), p);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, len), p);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(len, 0), p);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -len), p);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-len, 0), p);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -len), p);
  }

  @override
  bool shouldRepaint(covariant _OnboardingHeroPainter oldDelegate) =>
      oldDelegate.slideIndex != slideIndex || oldDelegate.progress != progress;
}
