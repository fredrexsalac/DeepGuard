import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onAnalyzeTap;
  const HomeScreen({super.key, required this.onAnalyzeTap});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _hexCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  // Realtime Wi-Fi / Internet connectivity
  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _hexCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
            begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();

    _initConnectivity();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _hexCtrl.dispose();
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  /// Verifies active internet connectivity using network interfaces and a reachability probe.
  Future<bool> _checkInternetConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) return false;

      // Fast DNS reachability probe
      try {
        final lookup = await InternetAddress.lookup('example.com')
            .timeout(const Duration(milliseconds: 2500));
        return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      } catch (_) {
        try {
          final lookup2 = await InternetAddress.lookup('google.com')
              .timeout(const Duration(milliseconds: 2000));
          return lookup2.isNotEmpty && lookup2[0].rawAddress.isNotEmpty;
        } catch (_) {
          return false;
        }
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _initConnectivity() async {
    final online = await _checkInternetConnection();
    if (!mounted) return;
    setState(() => _isOnline = online);
  }

  void _listenConnectivity() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        if (mounted && _isOnline) {
          setState(() => _isOnline = false);
        }
        return;
      }
      final online = await _checkInternetConnection();
      if (!mounted) return;
      if (online != _isOnline) {
        setState(() => _isOnline = online);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060918),
      body: Stack(children: [
        // Hex grid background
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _hexCtrl,
            builder: (_, __) => CustomPaint(
              painter: _HexBgPainter(t: _hexCtrl.value),
            ),
          ),
        ),
        // Data rails
        const Positioned(left: 0, top: 0, bottom: 0, width: 20,
            child: _DataRail()),
        const Positioned(right: 0, top: 0, bottom: 0, width: 20,
            child: _DataRail(reverse: true)),
        // Content
        FadeTransition(
          opacity: _entryFade,
          child: SlideTransition(
            position: _entrySlide,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 28),
                    _buildHeroCTA(),
                    const SizedBox(height: 28),
                    _buildCapabilityRow(),
                    const SizedBox(height: 28),
                    _buildSectionLabel('DETECTION PIPELINE'),
                    const SizedBox(height: 14),
                    _buildPipeline(),
                    const SizedBox(height: 28),
                    _buildSectionLabel('HOW IT WORKS'),
                    const SizedBox(height: 14),
                    _buildStep('01', 'Select Media',
                        'Take a photo, record a video, or import from the gallery',
                        Icons.input_rounded, DeepGuardColors.primary),
                    const SizedBox(height: 10),
                    _buildStep('02', 'AI Processing',
                        'CNN extracts spatial features, RNN tracks temporal drift',
                        Icons.memory_outlined, DeepGuardColors.secondary),
                    const SizedBox(height: 10),
                    _buildStep('03', 'Verdict',
                        'Prediction confidence + AUTHENTIC / MANIPULATED classification returned',
                        Icons.analytics_outlined, DeepGuardColors.accent),
                    const SizedBox(height: 24),
                    _buildAccuracyBadge(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final Color statusColor =
        _isOnline ? DeepGuardColors.authentic : DeepGuardColors.fake;
    return Row(children: [
      AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                colors: DeepGuardColors.primaryGradient),
            boxShadow: [BoxShadow(
              color: DeepGuardColors.primary
                  .withAlpha((40 + 40 * _pulseCtrl.value).toInt()),
              blurRadius: 16 + 8 * _pulseCtrl.value,
              spreadRadius: 1,
            )],
          ),
          child: ClipOval(
            child: Image.asset('assets/images/deepguard_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield, color: Colors.white, size: 22)),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DEEPGUARD',
            style: TextStyle(
              color: DeepGuardColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              fontFamily: 'monospace',
            )),
        Text('v1.0 · CNN–RNN HYBRID',
            style: TextStyle(
              color: DeepGuardColors.primary.withAlpha(180),
              fontSize: 9,
              letterSpacing: 2.5,
              fontFamily: 'monospace',
            )),
      ]),
      const Spacer(),
      // Live status indicator — dynamically reflects realtime Wi-Fi / internet connectivity
      Tooltip(
        message: _isOnline
            ? 'Network Status: Connected (Online)'
            : 'Network Status: Disconnected (Offline mode active)',
        child: GestureDetector(
          onTap: () async {
            final online = await _checkInternetConnection();
            if (!mounted) return;
            setState(() => _isOnline = online);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  online
                      ? 'Network Status: ONLINE (Wi-Fi/Internet Connected)'
                      : 'Network Status: OFFLINE (No Internet Connection)',
                  style: const TextStyle(fontSize: 12),
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: online
                    ? DeepGuardColors.surfaceCard
                    : const Color(0xFF2A0D15),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: statusColor.withAlpha(80),
              ),
              color: statusColor.withAlpha(15),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOnline
                        ? statusColor.withAlpha(
                            (150 + 105 * _pulseCtrl.value).toInt())
                        : statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isOnline ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Hero CTA ──────────────────────────────────────────────────────────────
  Widget _buildHeroCTA() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DeepGuardColors.primary.withAlpha(50)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DeepGuardColors.primary.withAlpha(12),
            DeepGuardColors.secondary.withAlpha(8),
          ],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('> deepguard --detect',
            style: TextStyle(
              color: DeepGuardColors.primary.withAlpha(160),
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            )),
        const SizedBox(height: 10),
        const Text(
          'Detect AI-\nManipulated\nMedia.',
          style: TextStyle(
            color: DeepGuardColors.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Hybrid CNN–RNN model processes every frame. '
          'Spatial artefacts and temporal drift — nothing hides.',
          style: TextStyle(
            color: DeepGuardColors.textSecondary.withAlpha(200),
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: _CyberButton(
            label: 'ANALYSE FILE',
            icon: Icons.upload_file_outlined,
            accent: DeepGuardColors.primary,
            onTap: widget.onAnalyzeTap,
          )),
        ]),
      ]),
    );
  }

  // ── Capability row ────────────────────────────────────────────────────────
  Widget _buildCapabilityRow() {
    return Row(children: [
      _buildCapTile('IMG', 'Image\nDetect', Icons.image_outlined,
          DeepGuardColors.primary),
      const SizedBox(width: 10),
      _buildCapTile('VID', 'Video\nDetect', Icons.videocam_outlined,
          DeepGuardColors.secondary),
      const SizedBox(width: 10),
      _buildCapTile('CAM', 'Camera\nCapture', Icons.camera_alt_outlined,
          const Color(0xFF00E5FF)),
    ]);
  }

  Widget _buildCapTile(
      String code, String label, IconData icon, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withAlpha(50)),
          color: accent.withAlpha(10),
        ),
        child: Column(children: [
          Text(code,
              style: TextStyle(
                  color: accent, fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Icon(icon, color: accent, size: 26),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: DeepGuardColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3)),
        ]),
      ),
    );
  }

  // ── Pipeline ──────────────────────────────────────────────────────────────
  Widget _buildPipeline() {
    final steps = [
      ('INPUT', DeepGuardColors.primary),
      ('PREPROCESS', DeepGuardColors.primary),
      ('CNN', DeepGuardColors.secondary),
      ('RNN', DeepGuardColors.secondary),
      ('FUSION', DeepGuardColors.accent),
      ('OUTPUT', DeepGuardColors.authentic),
    ];
    return SizedBox(
      height: 48,
      child: Row(
        children: steps.asMap().entries.map((e) {
          final isLast = e.key == steps.length - 1;
          return Expanded(
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: e.value.$2.withAlpha(60)),
                    color: e.value.$2.withAlpha(12),
                  ),
                  child: Center(
                    child: Text(e.value.$1,
                        style: TextStyle(
                            color: e.value.$2,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            fontFamily: 'monospace')),
                  ),
                ),
              ),
              if (!isLast)
                Icon(Icons.chevron_right,
                    size: 14, color: DeepGuardColors.textMuted.withAlpha(100)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ── Step card ─────────────────────────────────────────────────────────────
  Widget _buildStep(
      String num, String title, String sub, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(40)),
        color: accent.withAlpha(8),
      ),
      child: Row(children: [
        Text(num,
            style: TextStyle(
              color: accent.withAlpha(120),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            )),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: DeepGuardColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(sub,
                style: TextStyle(
                    color: DeepGuardColors.textSecondary.withAlpha(180),
                    fontSize: 12,
                    height: 1.4)),
          ],
        )),
        Icon(icon, color: accent.withAlpha(120), size: 22),
      ]),
    );
  }

  // ── Dataset test accuracy badge ───────────────────────────────────────────
  Widget _buildAccuracyBadge() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: DeepGuardColors.authentic.withAlpha(50)),
        color: DeepGuardColors.authentic.withAlpha(8),
      ),
      child: Row(children: [
        const Icon(Icons.verified_outlined,
            color: DeepGuardColors.authentic, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MODEL TEST ACCURACY',
                style: TextStyle(
                  color: DeepGuardColors.authentic,
                  fontSize: 9,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                )),
            const SizedBox(height: 4),
            const Text('84.82% Image  ·  71.67% Video',
                style: TextStyle(
                    color: DeepGuardColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            // Safeguard: dataset-level evaluation metric, explicitly separated
            // from the Prediction Confidence shown for each individual file.
            const Text(
                'Dataset-level test evaluation — not the Prediction '
                'Confidence of individual files.  ·  TFLite on-device',
                style: TextStyle(
                    color: DeepGuardColors.textMuted,
                    fontSize: 11,
                    height: 1.35)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: DeepGuardColors.textMuted,
      fontSize: 10,
      letterSpacing: 3,
      fontWeight: FontWeight.w700,
      fontFamily: 'monospace',
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cyber button
// ─────────────────────────────────────────────────────────────────────────────
class _CyberButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  const _CyberButton({
    required this.label, required this.icon,
    required this.accent, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          colors: [accent, DeepGuardColors.secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [BoxShadow(
          color: accent.withAlpha(80),
          blurRadius: 20, spreadRadius: 1, offset: const Offset(0, 4),
        )],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontFamily: 'monospace',
            )),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex background (shared with onboarding)
// ─────────────────────────────────────────────────────────────────────────────
const _sqrt3 = 1.7320508;

class _HexBgPainter extends CustomPainter {
  final double t;
  const _HexBgPainter({required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    const r = 26.0;
    const h = r * _sqrt3;
    const colW = r * 1.5;
    final cols = (s.width / colW).ceil() + 2;
    final rows = (s.height / h).ceil() + 2;
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6;
    for (int col = -1; col < cols; col++) {
      for (int row = -1; row < rows; row++) {
        final cx = col * colW;
        final cy = row * h + (col.isOdd ? h / 2 : 0);
        final phase = cx * 0.007 + cy * 0.005 + t * 2 * 3.14159;
        final alpha = (sin(phase) * 0.5 + 0.5) * 16 + 4;
        p.color = DeepGuardColors.primary.withAlpha(alpha.toInt());
        _hex(canvas, Offset(cx, cy), r, p);
      }
    }
  }
  void _hex(Canvas c, Offset center, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = 3.14159 / 3 * i - 3.14159 / 6;
      final x = center.dx + r * cos(a);
      final y = center.dy + r * sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    c.drawPath(path, p);
  }
  @override
  bool shouldRepaint(_HexBgPainter o) => o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// Data rail (shared with onboarding)
// ─────────────────────────────────────────────────────────────────────────────
class _DataRail extends StatefulWidget {
  final bool reverse;
  const _DataRail({this.reverse = false});
  @override
  State<_DataRail> createState() => _DataRailState();
}

class _DataRailState extends State<_DataRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _rng = Random(7);
  late final List<String> _chars;

  @override
  void initState() {
    super.initState();
    _chars = List.generate(60,
        (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase());
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 7))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => ClipRect(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RailPainter(
          chars: _chars,
          t: widget.reverse ? 1 - _c.value : _c.value,
        ),
      ),
    ),
  );
}

class _RailPainter extends CustomPainter {
  final List<String> chars;
  final double t;
  const _RailPainter({required this.chars, required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    const lh = 14.0;
    final offset = t * chars.length * lh;
    for (int i = 0; i < chars.length * 2; i++) {
      final y = (i * lh - offset) % (chars.length * lh);
      if (y < 0 || y > s.height) continue;
      final alpha = (sin(y / s.height * 3.14159) * 70 + 15).toInt().clamp(0, 255);
      final tp = TextPainter(
        text: TextSpan(
          text: chars[i % chars.length],
          style: TextStyle(
            color: DeepGuardColors.primary.withAlpha(alpha),
            fontSize: 8, fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(s.width / 2 - tp.width / 2, y));
    }
  }
  @override
  bool shouldRepaint(_RailPainter o) => o.t != t;
}
