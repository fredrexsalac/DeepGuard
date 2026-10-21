import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page data — each slide has its own visual identity
// ─────────────────────────────────────────────────────────────────────────────
class _OBPage {
  final String terminalTag;   // types itself like a terminal command
  final String headline;      // glitches then resolves
  final String body;
  final Color accent;
  final _HeroType heroType;

  const _OBPage({
    required this.terminalTag,
    required this.headline,
    required this.body,
    required this.accent,
    required this.heroType,
  });
}

enum _HeroType { faceScan, uploadScan, cameraScan, networkScan }

const _kPages = [
  _OBPage(
    terminalTag: r'> INIT deepguard --scan face',
    headline: 'Is This\nFace Real?',
    body: 'DeepGuard runs a hybrid CNN–RNN model directly on your device — '
        'extracting spatial artefacts and temporal inconsistencies that '
        'deepfake generators leave behind.',
    accent: Color(0xFF00D4FF),
    heroType: _HeroType.faceScan,
  ),
  _OBPage(
    terminalTag: r'> LOAD media --analyse frames',
    headline: 'Upload.\nInspect.\nVerify.',
    body: 'Feed any photo or video into DeepGuard. '
        'Every frame is preprocessed, resized to 128×128 and passed '
        'through the model. Prediction confidence returned in milliseconds.',
    accent: Color(0xFF7B2FF7),
    heroType: _HeroType.uploadScan,
  ),
  _OBPage(
    terminalTag: r'> CAPTURE media --photo --video',
    headline: 'Capture.\nThen\nAnalyse.',
    body: 'Take a photo or record a video with your camera. '
        'Analysis starts only after capture — the Hybrid CNN–RNN pipeline '
        'runs on the saved file, never on the live preview.',
    accent: Color(0xFF00E5FF),
    heroType: _HeroType.cameraScan,
  ),
  _OBPage(
    terminalTag: r'> MODEL cnn_rnn --image 84.82% --video 71.67%',
    headline: 'CNN–RNN\nHybrid\nEngine.',
    body: 'Convolutional layers extract per-frame features. '
        'Recurrent layers track inconsistencies across time. '
        'Neuro-symbolic gates refuse to pass borderline predictions without evidence.',
    accent: Color(0xFFFF2D95),
    heroType: _HeroType.networkScan,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen — cinematic logo reveal
// ─────────────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ring;
  late final AnimationController _text;
  late final AnimationController _scanLine;

  // Logo fades + scales in
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  // Wordmark reveal
  late final Animation<double> _wordFade;
  late final Animation<double> _wordSlide;
  // Scan line sweeps down the logo
  late final Animation<double> _scan;

  String _displayWord = 'DEEPGUARD';
  Timer? _glitchTimer;
  final _rng = Random();
  final _chars = '01ABCDEF<>[]#@%&';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _ring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _text = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scanLine = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _ring, curve: Curves.easeOutBack));
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ring,
            curve: const Interval(0.3, 0.9, curve: Curves.easeIn)));

    _wordFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _text, curve: Curves.easeIn));
    _wordSlide = Tween<double>(begin: 18, end: 0).animate(
        CurvedAnimation(parent: _text, curve: Curves.easeOut));

    _scan = Tween<double>(begin: -1, end: 1).animate(
        CurvedAnimation(parent: _scanLine, curve: Curves.linear));

    _ring.forward().then((_) async {
      await _text.forward();
      _startGlitch();
      await Future.delayed(const Duration(milliseconds: 900));
      _glitchTimer?.cancel();
      setState(() => _displayWord = 'DEEPGUARD');
      await _scanLine.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      widget.onDone();
    });
  }

  void _startGlitch() {
    int step = 0;
    _glitchTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted) return;
      step++;
      if (step > 14) {
        setState(() => _displayWord = 'DEEPGUARD');
        _glitchTimer?.cancel();
        return;
      }
      final buf = StringBuffer();
      for (int i = 0; i < 9; i++) {
        // Resolve characters left-to-right over time
        if (i < (step * 9 ~/ 14)) {
          buf.write('DEEPGUARD'[i]);
        } else {
          buf.write(_chars[_rng.nextInt(_chars.length)]);
        }
      }
      setState(() => _displayWord = buf.toString());
    });
  }

  @override
  void dispose() {
    _glitchTimer?.cancel();
    _ring.dispose();
    _text.dispose();
    _scanLine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060918),
      body: Stack(children: [
        const Positioned.fill(child: _HexGrid()),
        // Data stream rails
        const Positioned(left: 0, top: 0, bottom: 0, width: 22,
            child: _DataRail()),
        const Positioned(right: 0, top: 0, bottom: 0, width: 22,
            child: _DataRail(reverse: true)),
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_ring, _text, _scanLine]),
            builder: (_, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with scan line
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: _SplashLogo(scanValue: _scan.value),
                  ),
                ),
                const SizedBox(height: 32),
                // Glitch wordmark
                Transform.translate(
                  offset: Offset(0, _wordSlide.value),
                  child: Opacity(
                    opacity: _wordFade.value,
                    child: Text(
                      _displayWord,
                      style: const TextStyle(
                        color: DeepGuardColors.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: _wordFade.value,
                  child: const Text(
                    'DEEPFAKE · DETECTION · AI',
                    style: TextStyle(
                      color: DeepGuardColors.primary,
                      fontSize: 10,
                      letterSpacing: 5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash logo — ring draw + scan line
// ─────────────────────────────────────────────────────────────────────────────
class _SplashLogo extends StatelessWidget {
  final double scanValue; // -1 (above) → 1 (below), 0 = center
  const _SplashLogo({required this.scanValue});

  @override
  Widget build(BuildContext context) {
    const size = 120.0;
    return SizedBox(
      width: size + 40,
      height: size + 40,
      child: Stack(alignment: Alignment.center, children: [
        // Outer glow
        Container(
          width: size + 30,
          height: size + 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: DeepGuardColors.primary.withAlpha(60),
              blurRadius: 36, spreadRadius: 6)],
          ),
        ),
        // Ring
        CustomPaint(
          size: const Size(size + 20, size + 20),
          painter: _RingPainter(color: DeepGuardColors.primary),
        ),
        // Logo face
        ClipOval(
          child: Container(
            width: size, height: size,
            color: const Color(0xFF0D1035),
            child: Image.asset('assets/images/deepguard_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield, size: 60, color: DeepGuardColors.primary)),
          ),
        ),
        // Scan line sweeping over the logo
        if (scanValue > -1.05 && scanValue < 1.05)
          Positioned(
            top: (size + 40) / 2 + scanValue * (size / 2),
            left: 10, right: 10,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  DeepGuardColors.primary.withAlpha(200),
                  DeepGuardColors.primary,
                  DeepGuardColors.primary.withAlpha(200),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  const _RingPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    // Dashed segmented ring
    final paint = Paint()
      ..color = color.withAlpha(180)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const segments = 24;
    const gap = 0.04; // radians
    for (int i = 0; i < segments; i++) {
      final start = i * 2 * pi / segments;
      final sweep = 2 * pi / segments - gap;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), start, sweep, false, paint);
    }
    // Corner tick marks
    final tick = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2 - pi / 4;
      final x = c.dx + r * cos(angle);
      final y = c.dy + r * sin(angle);
      final nx = cos(angle), ny = sin(angle);
      canvas.drawLine(Offset(x - ny * 6, y + nx * 6),
          Offset(x + ny * 6, y - nx * 6), tick);
    }
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding carousel
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PageController();
  int _page = 0;

  late final AnimationController _enterAnim;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;

  @override
  void initState() {
    super.initState();
    _enterAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _enterFade = CurvedAnimation(parent: _enterAnim, curve: Curves.easeOut);
    _enterSlide = Tween<Offset>(
        begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterAnim, curve: Curves.easeOut));
    _enterAnim.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _enterAnim.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _kPages.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOutCubic);
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _kPages[_page].accent;
    return Scaffold(
      backgroundColor: const Color(0xFF060918),
      body: FadeTransition(
        opacity: _enterFade,
        child: SlideTransition(
          position: _enterSlide,
          child: Stack(children: [
            // Hex grid bg
            const Positioned.fill(child: _HexGrid()),
            // Data rails
            const Positioned(left: 0, top: 0, bottom: 0, width: 22,
                child: _DataRail()),
            const Positioned(right: 0, top: 0, bottom: 0, width: 22,
                child: _DataRail(reverse: true)),
            // Page content
            PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _kPages.length,
              itemBuilder: (_, i) => _PageSlide(page: _kPages[i]),
            ),
            // Skip button
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              right: 24,
              child: AnimatedOpacity(
                opacity: _page < _kPages.length - 1 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: widget.onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: DeepGuardColors.textMuted.withAlpha(60)),
                      color: Colors.black.withAlpha(40),
                    ),
                    child: const Text('skip',
                        style: TextStyle(
                            color: DeepGuardColors.textMuted,
                            fontSize: 12,
                            letterSpacing: 1)),
                  ),
                ),
              ),
            ),
            // Bottom bar
            Positioned(
              left: 0, right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 28,
              child: Column(children: [
                // Segmented progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: List.generate(_kPages.length, (i) {
                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i <= _page
                                ? accent
                                : DeepGuardColors.textMuted.withAlpha(60),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _page == _kPages.length - 1
                      ? _GetStartedBtn(
                          accent: accent, onTap: _next)
                      : _NextBtn(accent: accent, onTap: _next),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual page slide
// ─────────────────────────────────────────────────────────────────────────────
class _PageSlide extends StatefulWidget {
  final _OBPage page;
  const _PageSlide({required this.page});
  @override
  State<_PageSlide> createState() => _PageSlideState();
}

class _PageSlideState extends State<_PageSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  // terminal tag: types character by character
  String _typedTag = '';
  int _typeIdx = 0;
  Timer? _typeTimer;

  // headline glitch
  String _headline = '';
  bool _glitched = false;
  Timer? _glitchTimer;
  final _rng = Random();
  final _glitchChars = '01#@%<>[]ABCDEF';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anim.forward();
    _headline = widget.page.headline;
    _startTypewriter();
  }

  void _startTypewriter() {
    _typeTimer = Timer.periodic(const Duration(milliseconds: 38), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_typeIdx < widget.page.terminalTag.length) {
        setState(() {
          _typeIdx++;
          _typedTag = widget.page.terminalTag.substring(0, _typeIdx);
        });
      } else {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 120), _startGlitch);
      }
    });
  }

  void _startGlitch() {
    if (!mounted) return;
    int step = 0;
    _glitchTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      step++;
      if (step > 12) {
        setState(() => _headline = widget.page.headline);
        _glitchTimer?.cancel();
        _glitched = true;
        return;
      }
      final resolved = step * widget.page.headline.length ~/ 12;
      final buf = StringBuffer();
      final flat = widget.page.headline.replaceAll('\n', '↵');
      for (int i = 0; i < flat.length; i++) {
        if (flat[i] == '↵') { buf.write('\n'); continue; }
        buf.write(i < resolved
            ? flat[i]
            : _glitchChars[_rng.nextInt(_glitchChars.length)]);
      }
      setState(() => _headline = buf.toString());
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _glitchTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final t = _anim.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.11),
              // Hero visual
              Center(
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * t,
                    child: _HeroVisual(
                        heroType: p.heroType, accent: p.accent),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.045),
              // Terminal tag
              Opacity(
                opacity: t,
                child: Text(
                  _typedTag,
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Glitch headline
              Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - t)),
                  child: Text(
                    _headline,
                    style: TextStyle(
                      color: _glitched
                          ? DeepGuardColors.textPrimary
                          : p.accent.withAlpha(220),
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Body
              Opacity(
                opacity: (t * 1.5 - 0.5).clamp(0.0, 1.0),
                child: Text(
                  p.body,
                  style: TextStyle(
                    color: DeepGuardColors.textSecondary.withAlpha(200),
                    fontSize: 13.5,
                    height: 1.7,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero visuals — each page gets a unique biometric-style diagram
// ─────────────────────────────────────────────────────────────────────────────
class _HeroVisual extends StatefulWidget {
  final _HeroType heroType;
  final Color accent;
  const _HeroVisual({required this.heroType, required this.accent});
  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;
  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))..repeat();
  }
  @override
  void dispose() { _loop.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (_, __) => CustomPaint(
        size: const Size(220, 200),
        painter: _heroPainter(widget.heroType, widget.accent, _loop.value),
      ),
    );
  }
}

CustomPainter _heroPainter(_HeroType t, Color accent, double v) {
  switch (t) {
    case _HeroType.faceScan:    return _FaceScanPainter(accent, v);
    case _HeroType.uploadScan:  return _UploadScanPainter(accent, v);
    case _HeroType.cameraScan:  return _CameraScanPainter(accent, v);
    case _HeroType.networkScan: return _NetworkPainter(accent, v);
  }
}

// ── Face biometric scan ──────────────────────────────────────────────────────
class _FaceScanPainter extends CustomPainter {
  final Color a; final double v;
  const _FaceScanPainter(this.a, this.v);
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2; final cy = s.height / 2;
    final p = Paint()..color = a.withAlpha(30)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    // Oval face outline
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 10),
        width: 100, height: 120), p..color = a.withAlpha(80)..strokeWidth = 1.5);
    // Face landmark dots
    final dots = [
      Offset(cx - 20, cy - 20), Offset(cx + 20, cy - 20), // eyes
      Offset(cx, cy + 5),                                   // nose
      Offset(cx - 18, cy + 26), Offset(cx + 18, cy + 26),  // mouth
    ];
    for (final d in dots) {
      canvas.drawCircle(d, 3, Paint()..color = a.withAlpha(200));
      canvas.drawCircle(d, 7,
          Paint()..color = a.withAlpha(40)..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    // Connecting mesh lines
    final mesh = Paint()..color = a.withAlpha(40)..strokeWidth = 0.8;
    for (int i = 0; i < dots.length; i++) {
      for (int j = i + 1; j < dots.length; j++) {
        canvas.drawLine(dots[i], dots[j], mesh);
      }
    }
    // Animated scan line
    final scanY = cy - 60 + v * 120;
    final scanPaint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent, a.withAlpha(180), a, a.withAlpha(180), Colors.transparent
      ]).createShader(Rect.fromLTWH(cx - 60, scanY, 120, 2));
    canvas.drawRect(Rect.fromLTWH(cx - 60, scanY, 120, 2), scanPaint);
    // Corner brackets
    _drawBrackets(canvas, Offset(cx, cy - 10), 56, 66, a);
    // Confidence reading
    _drawLabel(canvas, Offset(cx + 62, cy - 40),
        '${(85 + (v * 10).toInt())}%', a);
  }
  @override bool shouldRepaint(_FaceScanPainter o) => o.v != v;
}

// ── Upload / frame analysis ──────────────────────────────────────────────────
class _UploadScanPainter extends CustomPainter {
  final Color a; final double v;
  const _UploadScanPainter(this.a, this.v);
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2; final cy = s.height / 2;
    // Frame stack
    for (int i = 2; i >= 0; i--) {
      final offset = i * 6.0;
      final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - offset, cy + offset),
              width: 90, height: 110),
          const Radius.circular(8));
      canvas.drawRRect(rect, Paint()
        ..color = a.withAlpha(20 + i * 15)
        ..style = PaintingStyle.fill);
      canvas.drawRRect(rect, Paint()
        ..color = a.withAlpha(60 + i * 20)
        ..style = PaintingStyle.stroke..strokeWidth = 1);
    }
    // Scan progress bar on front frame
    final barH = 110 * v;
    final clip = Rect.fromLTWH(cx - 45, cy - 55, 90, barH);
    canvas.save();
    canvas.clipRect(clip);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: 90, height: 110),
            const Radius.circular(8)),
        Paint()..color = a.withAlpha(35));
    canvas.restore();
    // Scan line
    final lineY = cy - 55 + barH;
    canvas.drawLine(Offset(cx - 45, lineY), Offset(cx + 45, lineY),
        Paint()..color = a..strokeWidth = 1.5);
    _drawLabel(canvas, Offset(cx + 52, lineY - 6),
        '${(v * 100).toInt()}%', a);
    _drawBrackets(canvas, Offset(cx, cy), 48, 58, a);
  }
  @override bool shouldRepaint(_UploadScanPainter o) => o.v != v;
}

// ── Camera capture ─────────────────────────────────────────────────────────
class _CameraScanPainter extends CustomPainter {
  final Color a; final double v;
  const _CameraScanPainter(this.a, this.v);
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2; final cy = s.height / 2;
    // Viewfinder body
    final vf = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 130, height: 100),
        const Radius.circular(10));
    canvas.drawRRect(vf, Paint()..color = a.withAlpha(15));
    canvas.drawRRect(vf, Paint()
      ..color = a.withAlpha(80)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // Lens circle
    canvas.drawCircle(Offset(cx, cy), 28,
        Paint()..color = a.withAlpha(20));
    canvas.drawCircle(Offset(cx, cy), 28,
        Paint()..color = a.withAlpha(100)
          ..style = PaintingStyle.stroke..strokeWidth = 1.2);
    canvas.drawCircle(Offset(cx, cy), 14,
        Paint()..color = a.withAlpha(140));
    // Pulse ring
    final r = 32 + 10 * sin(v * 2 * pi);
    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = a.withAlpha((60 * (1 - (r - 32) / 10)).toInt())
          ..style = PaintingStyle.stroke..strokeWidth = 1);
    // Capture mode labels
    _drawLabel(canvas, Offset(cx + 70, cy - 42), 'PHOTO', a);
    _drawLabel(canvas, Offset(cx + 70, cy - 26), 'VIDEO', a);
    _drawBrackets(canvas, Offset(cx, cy), 68, 54, a);
  }
  @override bool shouldRepaint(_CameraScanPainter o) => o.v != v;
}

// ── Neural network graph ─────────────────────────────────────────────────────
class _NetworkPainter extends CustomPainter {
  final Color a; final double v;
  const _NetworkPainter(this.a, this.v);
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2; final cy = s.height / 2;
    // Three layers: input (4), hidden (5), output (2)
    final layers = [
      [Offset(cx - 80, cy - 40), Offset(cx - 80, cy - 13),
       Offset(cx - 80, cy + 14), Offset(cx - 80, cy + 41)],
      [Offset(cx, cy - 52), Offset(cx, cy - 26), Offset(cx, cy),
       Offset(cx, cy + 26), Offset(cx, cy + 52)],
      [Offset(cx + 80, cy - 18), Offset(cx + 80, cy + 18)],
    ];
    // Connections with animated activation
    final connPaint = Paint()..strokeWidth = 0.7;
    for (int li = 0; li < layers.length - 1; li++) {
      for (final from in layers[li]) {
        for (final to in layers[li + 1]) {
          final active = sin(v * 2 * pi + from.dy * 0.1 + to.dy * 0.1) > 0.3;
          connPaint.color = active
              ? a.withAlpha(80)
              : a.withAlpha(20);
          canvas.drawLine(from, to, connPaint);
        }
      }
    }
    // Nodes
    for (int li = 0; li < layers.length; li++) {
      for (final n in layers[li]) {
        final active = sin(v * 2 * pi + n.dy * 0.15) > 0;
        canvas.drawCircle(n, 7,
            Paint()..color = active ? a.withAlpha(160) : a.withAlpha(30));
        canvas.drawCircle(n, 7,
            Paint()..color = a.withAlpha(active ? 220 : 80)
              ..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
    }
    // Output labels
    _drawLabel(canvas, layers[2][0] + const Offset(12, -4), 'FAKE', a);
    _drawLabel(canvas, layers[2][1] + const Offset(12, -4), 'REAL', a);
  }
  @override bool shouldRepaint(_NetworkPainter o) => o.v != v;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared painter helpers
// ─────────────────────────────────────────────────────────────────────────────
void _drawBrackets(Canvas c, Offset center, double hw, double hh, Color a) {
  const len = 14.0;
  final p = Paint()..color = a..strokeWidth = 2
    ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
  final corners = [
    Offset(center.dx - hw, center.dy - hh),
    Offset(center.dx + hw, center.dy - hh),
    Offset(center.dx - hw, center.dy + hh),
    Offset(center.dx + hw, center.dy + hh),
  ];
  final dx = [len, -len, len, -len];
  final dy = [len, len, -len, -len];
  for (int i = 0; i < 4; i++) {
    c.drawLine(corners[i], corners[i] + Offset(dx[i], 0), p);
    c.drawLine(corners[i], corners[i] + Offset(0, dy[i]), p);
  }
}

void _drawLabel(Canvas c, Offset pos, String text, Color a) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
          color: a, fontSize: 9,
          fontFamily: 'monospace', letterSpacing: 0.5),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, pos);
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex-grid background — looks like a neural network substrate
// ─────────────────────────────────────────────────────────────────────────────
class _HexGrid extends StatefulWidget {
  const _HexGrid();
  @override
  State<_HexGrid> createState() => _HexGridState();
}

class _HexGridState extends State<_HexGrid> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => CustomPaint(
      size: Size.infinite,
      painter: _HexPainter(t: _ctrl.value),
    ),
  );
}

class _HexPainter extends CustomPainter {
  final double t;
  const _HexPainter({required this.t});

  @override
  void paint(Canvas canvas, Size s) {
    const r = 22.0;
    const h = r * sqrt3;
    const colW = r * 1.5;
    final cols = (s.width / colW).ceil() + 2;
    final rows = (s.height / h).ceil() + 2;
    final paint = Paint()
      ..color = DeepGuardColors.primary.withAlpha(14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (int col = -1; col < cols; col++) {
      for (int row = -1; row < rows; row++) {
        final cx = col * colW;
        final cy = row * h + (col.isOdd ? h / 2 : 0);
        // Pulse some hexagons based on time
        final phase = (cx * 0.008 + cy * 0.006 + t * 2 * pi);
        final alpha = (sin(phase) * 0.5 + 0.5) * 18 + 6;
        paint.color = DeepGuardColors.primary.withAlpha(alpha.toInt());
        _hexPath(canvas, Offset(cx, cy), r, paint);
      }
    }
  }

  void _hexPath(Canvas c, Offset center, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = pi / 3 * i - pi / 6;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_HexPainter o) => o.t != t;
}

const sqrt3 = 1.7320508;

// ─────────────────────────────────────────────────────────────────────────────
// Data stream rail — scrolling hex digits on screen edges
// ─────────────────────────────────────────────────────────────────────────────
class _DataRail extends StatefulWidget {
  final bool reverse;
  const _DataRail({this.reverse = false});
  @override
  State<_DataRail> createState() => _DataRailState();
}

class _DataRailState extends State<_DataRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Random _rng;
  late final List<String> _chars;

  @override
  void initState() {
    super.initState();
    _rng = Random(widget.reverse ? 99 : 1);
    _chars = List.generate(60, (_) => _rng.nextInt(256)
        .toRadixString(16).padLeft(2, '0').toUpperCase());
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => ClipRect(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RailPainter(
            chars: _chars,
            t: widget.reverse ? 1 - _ctrl.value : _ctrl.value,
            color: DeepGuardColors.primary),
      ),
    ),
  );
}

class _RailPainter extends CustomPainter {
  final List<String> chars;
  final double t;
  final Color color;
  const _RailPainter({required this.chars, required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size s) {
    const lineH = 14.0;
    final offset = t * chars.length * lineH;
    for (int i = 0; i < chars.length * 2; i++) {
      final y = (i * lineH - offset) % (chars.length * lineH);
      if (y < 0 || y > s.height) continue;
      final alpha = (sin(y / s.height * pi) * 80 + 20).toInt().clamp(0, 255);
      final tp = TextPainter(
        text: TextSpan(
          text: chars[i % chars.length],
          style: TextStyle(
              color: color.withAlpha(alpha),
              fontSize: 8,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(s.width / 2 - tp.width / 2, y));
    }
  }

  @override
  bool shouldRepaint(_RailPainter o) => o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────
class _NextBtn extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;
  const _NextBtn({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(140), width: 1.5),
          color: accent.withAlpha(18),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('NEXT',
              style: TextStyle(
                  color: accent, fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontFamily: 'monospace')),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, color: accent, size: 20),
        ]),
      ),
    );
  }
}

class _GetStartedBtn extends StatefulWidget {
  final Color accent;
  final VoidCallback onTap;
  const _GetStartedBtn({required this.accent, required this.onTap});
  @override
  State<_GetStartedBtn> createState() => _GetStartedBtnState();
}

class _GetStartedBtnState extends State<_GetStartedBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final glow = sin(_pulse.value * 2 * pi) * 0.5 + 0.5;
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(colors: [
                widget.accent,
                DeepGuardColors.secondary,
              ]),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withAlpha((80 + 60 * glow).toInt()),
                  blurRadius: 20 + 10 * glow,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text('ACTIVATE DEEPGUARD',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                          fontFamily: 'monospace')),
                ]),
          ),
        );
      },
    );
  }
}
