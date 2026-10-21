import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../services/preprocessing_service.dart';
import '../widgets/upload_confirmation_sheet.dart';

/// Tracks whether a media file came from the hardware camera or the gallery.
/// This enum is threaded through the processing pipeline so the diagnostic log
/// can report the capture method alongside every TFLite inference call.
enum MediaSource {
  camera,
  gallery,
}

class UploadScreen extends StatefulWidget {
  final void Function(String filePath, String mediaType, MediaSource source) onFileSelected;
  const UploadScreen({super.key, required this.onFileSelected});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
  final _preprocessing = PreprocessingService();
  String? _filePath;
  String? _mediaType;
  MediaSource _source = MediaSource.gallery; // tracks camera vs gallery

  // Video player for video preview
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  late final AnimationController _hexCtrl;
  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _hexCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))..repeat();
    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _scanCtrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── Feedback ─────────────────────────────────────────────────────────────
  /// Lightweight toast for picker outcomes. White text on a fixed dark
  /// surface so it stays legible on phones in either system light or dark
  /// mode (independent of the platform SnackBar theme).
  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF14161F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── File picking ───────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) {
      _notify('No photo selected.');
      return;
    }
    _setFile(x.path, source: MediaSource.gallery);
  }

  Future<void> _pickVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) {
      _notify('No video selected.');
      return;
    }
    _setFile(x.path, source: MediaSource.gallery);
  }

  Future<void> _captureFromCamera() async {
    // imageQuality is intentionally omitted (defaults to no re-compression).
    // Applying imageQuality:90 would add JPEG block artefacts to the captured
    // file before it reaches the TFLite model, creating a preprocessing
    // mismatch vs. gallery images and degrading inference accuracy.
    // The model receives the raw camera file; resizing to 128×128 happens
    // inside DeepGuardTFLiteService using average (≈ INTER_AREA) interpolation,
    // exactly matching the training pipeline (notebook Cell 18).
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (x == null) {
      _notify('Photo capture cancelled.');
      return;
    }
    _setFile(x.path, source: MediaSource.camera);
  }

  Future<void> _recordShortVideo() async {
    // maxDuration is set to 60 s so the model always receives a manageable
    // clip. The 10-frame extractor samples uniformly regardless of length,
    // but very long recordings increase extraction time without improving
    // detection quality.
    final x = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxDuration: const Duration(seconds: 60),
    );
    if (x == null) {
      _notify('Video recording cancelled.');
      return;
    }
    _setFile(x.path, source: MediaSource.camera);
  }

  /// Step 1 — validate + set preview state. Does NOT start analysis yet.
  void _setFile(String path, {required MediaSource source}) {
    final file = File(path);
    if (!file.existsSync()) { _err('File not found.'); return; }
    if (!_preprocessing.isValidMedia(path)) {
      _err('Unsupported format.'); return;
    }
    if (!_preprocessing.isValidFileSize(file.lengthSync())) {
      _err('File exceeds 100 MB limit.'); return;
    }
    final mediaType = _preprocessing.getMediaType(path);
    setState(() {
      _filePath = path;
      _mediaType = mediaType;
      _source = source;
      _videoReady = false;
    });
    if (mediaType == 'video') _initVideoPlayer(path);
  }

  /// Step 2 — user taps RUN ANALYSIS: show confirmation sheet then proceed.
  Future<void> _submit() async {
    if (_filePath == null || _mediaType == null) return;
    _videoCtrl?.pause();

    final confirmed = await UploadConfirmationSheet.show(
      context: context,
      filePath: _filePath!,
    );

    if (confirmed == true && mounted) {
      widget.onFileSelected(_filePath!, _mediaType!, _source);
    }
  }

  Future<void> _initVideoPlayer(String path) async {
    await _videoCtrl?.dispose();
    _videoCtrl = VideoPlayerController.file(File(path));
    bool ok = false;
    try {
      await _videoCtrl!.initialize();
      await _videoCtrl!.setLooping(true);
      await _videoCtrl!.seekTo(Duration.zero); // show first frame as thumbnail
      ok = _videoCtrl!.value.isInitialized;
    } catch (_) {
      // If video can't be previewed, show placeholder — analysis still works
    }
    // Only mark ready when the controller actually initialized, otherwise the
    // preview would build an AspectRatio on a zero/uninitialized controller.
    if (mounted) setState(() => _videoReady = ok);
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
      backgroundColor: DeepGuardColors.fake,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ));
  }

  void _clear() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    setState(() {
      _filePath = null;
      _mediaType = null;
      _source = MediaSource.gallery;
      _videoReady = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060918),
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _hexCtrl,
            builder: (_, __) => CustomPaint(
                painter: _HexBgPainter(t: _hexCtrl.value)),
          ),
        ),
        const Positioned(left: 0, top: 0, bottom: 0, width: 20,
            child: _DataRail()),
        const Positioned(right: 0, top: 0, bottom: 0, width: 20,
            child: _DataRail(reverse: true)),
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: _filePath != null
                  ? _buildPreview()
                  : _buildSelectZone(),
            )),
          ]),
        ),
      ]),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Row(children: [
      Text('> LOAD_MEDIA',
          style: TextStyle(
            color: DeepGuardColors.primary.withAlpha(180),
            fontSize: 12, fontFamily: 'monospace', letterSpacing: 1,
          )),
      const Spacer(),
      Text('ANALYSE',
          style: TextStyle(
            color: DeepGuardColors.textMuted.withAlpha(120),
            fontSize: 10, letterSpacing: 3, fontFamily: 'monospace',
          )),
    ]),
  );

  // ── Select zone ────────────────────────────────────────────────────────────
  Widget _buildSelectZone() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      const Text('SELECT MEDIA',
          style: TextStyle(
            color: DeepGuardColors.textPrimary,
            fontSize: 24, fontWeight: FontWeight.w900,
            letterSpacing: 1,
          )),
      const SizedBox(height: 6),
      Text('Capture with the camera or import from the gallery — DeepGuard analyses every frame after capture.',
          style: TextStyle(
            color: DeepGuardColors.textSecondary.withAlpha(180),
            fontSize: 13, height: 1.5,
          )),
      const SizedBox(height: 24),
      // Drop zone
      AnimatedBuilder(
        animation: _scanCtrl,
        builder: (_, __) => _DropZone(scanValue: _scanCtrl.value),
      ),
      const SizedBox(height: 24),
      const Text('QUICK SELECT',
          style: TextStyle(
            color: DeepGuardColors.textMuted,
            fontSize: 10, letterSpacing: 3,
            fontWeight: FontWeight.w700, fontFamily: 'monospace',
          )),
      const SizedBox(height: 14),
      // Row 1: Camera capture — take/record first, analysis starts only after
      Row(children: [
        Expanded(child: _SourceTile(
          code: 'CAM', label: 'Take Photo', icon: Icons.camera_alt_outlined,
          accent: DeepGuardColors.accent, onTap: _captureFromCamera,
        )),
        const SizedBox(width: 10),
        Expanded(child: _SourceTile(
          code: 'REC', label: 'Record Video', icon: Icons.videocam_outlined,
          accent: const Color(0xFF00E5FF), onTap: _recordShortVideo,
        )),
      ]),
      const SizedBox(height: 10),
      // Row 2: Gallery picks — select existing media, analysis starts after
      Row(children: [
        Expanded(child: _SourceTile(
          code: 'IMG', label: 'Input Photo', icon: Icons.photo_library_outlined,
          accent: DeepGuardColors.primary, onTap: _pickImage,
        )),
        const SizedBox(width: 10),
        Expanded(child: _SourceTile(
          code: 'VID', label: 'Input Video', icon: Icons.video_library_outlined,
          accent: DeepGuardColors.secondary, onTap: _pickVideo,
        )),
      ]),
      const SizedBox(height: 24),
      _buildFormatTable(),
    ],
  );

  Widget _buildFormatTable() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: DeepGuardColors.primary.withAlpha(30)),
      color: DeepGuardColors.primary.withAlpha(6),
    ),
    child: Column(children: [
      _fmtRow(Icons.image_outlined,
          PreprocessingService.allowedImageExtensions
              .map((e) => e.toUpperCase()).join('  '),
          DeepGuardColors.primary),
      const SizedBox(height: 10),
      _fmtRow(Icons.videocam_outlined,
          PreprocessingService.allowedVideoExtensions
              .map((e) => e.toUpperCase()).join('  '),
          DeepGuardColors.secondary),
      const SizedBox(height: 10),
      _fmtRow(Icons.storage_outlined, 'MAX  100 MB',
          DeepGuardColors.textMuted),
    ]),
  );

  Widget _fmtRow(IconData icon, String text, Color color) => Row(children: [
    Icon(icon, size: 14, color: color.withAlpha(160)),
    const SizedBox(width: 10),
    Text(text,
        style: TextStyle(
          color: color.withAlpha(180), fontSize: 11,
          fontFamily: 'monospace', letterSpacing: 0.8,
        )),
  ]);

  // ── Preview ────────────────────────────────────────────────────────────────
  Widget _buildPreview() {
    final isImg = _mediaType == 'image';
    final file = File(_filePath!);
    final name = _filePath!.split('/').last;
    final sizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text('> FILE LOADED — $_mediaType'.toUpperCase(),
          style: TextStyle(
            color: DeepGuardColors.authentic.withAlpha(180),
            fontSize: 11, fontFamily: 'monospace', letterSpacing: 1,
          )),
      const SizedBox(height: 16),
      // Media preview frame
      AnimatedBuilder(
        animation: _scanCtrl,
        builder: (_, __) => Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: DeepGuardColors.primary.withAlpha(
                  (40 + 40 * sin(_scanCtrl.value * 2 * pi)).toInt()),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(fit: StackFit.expand, children: [
              // ── Image preview ──────────────────────────────────────────
              if (isImg)
                Image.file(file, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _NoPreview()),
              // ── Video preview with player ──────────────────────────────
              if (!isImg) ...[
                if (_videoReady && _videoCtrl != null)
                  _VideoPreview(controller: _videoCtrl!)
                else
                  const _NoPreview(isVideo: true, loading: true),
              ],
              // Scan overlay line
              Positioned(
                top: _scanCtrl.value * 220,
                left: 0, right: 0,
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      DeepGuardColors.primary.withAlpha(160),
                      DeepGuardColors.primary,
                      DeepGuardColors.primary.withAlpha(160),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              // Corner brackets
              Positioned.fill(
                child: CustomPaint(
                  painter: _BracketPainter(DeepGuardColors.primary.withAlpha(140)),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 14),
      // File metadata row
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: DeepGuardColors.primary.withAlpha(30)),
          color: DeepGuardColors.primary.withAlpha(8),
        ),
        child: Row(children: [
          Icon(isImg ? Icons.image_outlined : Icons.videocam_outlined,
              color: DeepGuardColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: DeepGuardColors.textPrimary,
                      fontSize: 12, fontWeight: FontWeight.w600,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              Text('$sizeMb MB  ·  ${isImg ? 'IMAGE' : 'VIDEO'}',
                  style: TextStyle(
                      color: DeepGuardColors.textMuted.withAlpha(180),
                      fontSize: 10, fontFamily: 'monospace')),
            ],
          )),
          // Checkmark
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DeepGuardColors.authentic.withAlpha(30),
            ),
            child: const Icon(Icons.check,
                color: DeepGuardColors.authentic, size: 14),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      // Actions
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _clear,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: DeepGuardColors.textMuted.withAlpha(50)),
              ),
              child: const Center(
                child: Text('CLEAR',
                    style: TextStyle(
                      color: DeepGuardColors.textMuted,
                      fontSize: 12, letterSpacing: 2,
                      fontFamily: 'monospace',
                    )),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _submit,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                    colors: DeepGuardColors.primaryGradient),
                boxShadow: [BoxShadow(
                  color: DeepGuardColors.primary.withAlpha(70),
                  blurRadius: 16, spreadRadius: 1,
                )],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology_outlined,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('RUN ANALYSIS',
                      style: TextStyle(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2, fontFamily: 'monospace',
                      )),
                ],
              ),
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop zone widget
// ─────────────────────────────────────────────────────────────────────────────
class _DropZone extends StatelessWidget {
  final double scanValue;
  const _DropZone({required this.scanValue});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DeepGuardColors.primary.withAlpha(
              (30 + 30 * sin(scanValue * 2 * 3.14159)).toInt()),
          width: 1.5,
        ),
        color: DeepGuardColors.primary.withAlpha(8),
      ),
      child: Stack(alignment: Alignment.center, children: [
        // Scan line
        Positioned(
          top: scanValue * 160,
          left: 0, right: 0,
          child: Container(
            height: 1,
            color: DeepGuardColors.primary.withAlpha(
                (80 * sin(scanValue * 3.14159)).toInt().clamp(0, 255)),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_photo_alternate_outlined,
              color: DeepGuardColors.primary.withAlpha(140), size: 36),
          const SizedBox(height: 10),
          const Text('TAP BELOW TO SELECT',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DeepGuardColors.textMuted,
                fontSize: 11, letterSpacing: 3,
                fontFamily: 'monospace',
              )),
          const SizedBox(height: 6),
          Text('JPG · PNG · MP4 · MOV · AVI',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DeepGuardColors.textMuted.withAlpha(120),
                fontSize: 10, letterSpacing: 1,
              )),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source tile
// ─────────────────────────────────────────────────────────────────────────────
class _SourceTile extends StatelessWidget {
  final String code, label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  const _SourceTile({
    required this.code, required this.label, required this.icon,
    required this.accent, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(60)),
        color: accent.withAlpha(12),
      ),
      child: Column(children: [
        Text(code,
            style: TextStyle(
                color: accent, fontSize: 8, fontWeight: FontWeight.w800,
                letterSpacing: 2, fontFamily: 'monospace')),
        const SizedBox(height: 8),
        Icon(icon, color: accent, size: 26),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
                color: DeepGuardColors.textPrimary,
                fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
class _NoPreview extends StatelessWidget {
  final bool isVideo;
  final bool loading;
  const _NoPreview({this.isVideo = false, this.loading = false});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF0D1035),
    child: Center(child: loading
        ? const Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
                color: DeepGuardColors.primary, strokeWidth: 2),
            SizedBox(height: 10),
            Text('Loading preview…',
                style: TextStyle(color: DeepGuardColors.textMuted,
                    fontSize: 11, fontFamily: 'monospace')),
          ])
        : Icon(
            isVideo ? Icons.videocam_outlined : Icons.image_outlined,
            color: DeepGuardColors.primary.withAlpha(60), size: 48,
          )),
  );
}

/// Inline video player with play/pause tap control.
class _VideoPreview extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoPreview({required this.controller});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  bool _showIcon = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent can hand us a different controller when a new file is picked.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  /// Rebuild whenever the controller reports new state (isPlaying, position).
  /// Without this the play/pause button never updates and playback looks dead.
  void _onTick() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final ctrl = widget.controller;
    if (!ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _showIcon = true);
    } else {
      ctrl.play();
      setState(() => _showIcon = true);
      // Hide the overlay shortly after playback starts; the listener keeps the
      // icon accurate if the video pauses/stalls on its own.
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && ctrl.value.isPlaying) setState(() => _showIcon = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    // Guard against a controller that failed to initialize: aspectRatio would
    // be 0 and VideoPlayer would render nothing / break the layout.
    if (!ctrl.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white54, size: 40),
        ),
      );
    }
    final aspectRatio = ctrl.value.aspectRatio;

    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          // Video
          Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          // Progress bar at bottom
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: VideoProgressIndicator(
              ctrl,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: DeepGuardColors.primary,
                bufferedColor: DeepGuardColors.primary.withAlpha(60),
                backgroundColor: Colors.white.withAlpha(20),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            ),
          ),
          // Play/pause icon overlay
          if (!ctrl.value.isPlaying || _showIcon)
            Center(
              child: AnimatedOpacity(
                opacity: (!ctrl.value.isPlaying || _showIcon) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withAlpha(140),
                    border: Border.all(
                        color: DeepGuardColors.primary.withAlpha(160),
                        width: 1.5),
                  ),
                  child: Icon(
                    ctrl.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: DeepGuardColors.primary,
                    size: 32,
                  ),
                ),
              ),
            ),
          // Duration badge
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: ctrl,
                builder: (_, val, __) {
                  final dur = val.duration;
                  final pos = val.position;
                  String fmt(Duration d) =>
                      '${d.inMinutes.toString().padLeft(2, '0')}:'
                      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
                  return Text('${fmt(pos)} / ${fmt(dur)}',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 9,
                        fontFamily: 'monospace',
                      ));
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color..strokeWidth = 2
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    const len = 16.0;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx, 0), p);
      canvas.drawLine(o, o + Offset(0, dy), p);
    }
    corner(Offset.zero, len, len);
    corner(Offset(s.width, 0), -len, len);
    corner(Offset(0, s.height), len, -len);
    corner(Offset(s.width, s.height), -len, -len);
  }
  @override
  bool shouldRepaint(_BracketPainter o) => o.color != color;
}

class _HexBgPainter extends CustomPainter {
  final double t;
  const _HexBgPainter({required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    const r = 26.0;
    const h = r * 1.7320508;
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
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final a = 3.14159 / 3 * i - 3.14159 / 6;
          final x = cx + r * cos(a);
          final y = cy + r * sin(a);
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        path.close();
        canvas.drawPath(path, p);
      }
    }
  }
  @override
  bool shouldRepaint(_HexBgPainter o) => o.t != t;
}

class _DataRail extends StatefulWidget {
  final bool reverse;
  const _DataRail({this.reverse = false});
  @override
  State<_DataRail> createState() => _DataRailState();
}

class _DataRailState extends State<_DataRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _rng = Random(3);
  late final List<String> _chars;
  @override
  void initState() {
    super.initState();
    _chars = List.generate(60,
        (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase());
    _c = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => ClipRect(child: CustomPaint(
      size: Size.infinite,
      painter: _RailP(chars: _chars,
          t: widget.reverse ? 1 - _c.value : _c.value),
    )),
  );
}

class _RailP extends CustomPainter {
  final List<String> chars; final double t;
  const _RailP({required this.chars, required this.t});
  @override
  void paint(Canvas canvas, Size s) {
    const lh = 14.0;
    final off = t * chars.length * lh;
    for (int i = 0; i < chars.length * 2; i++) {
      final y = (i * lh - off) % (chars.length * lh);
      if (y < 0 || y > s.height) continue;
      final alpha = (sin(y / s.height * 3.14159) * 70 + 15).toInt().clamp(0, 255);
      final tp = TextPainter(
        text: TextSpan(text: chars[i % chars.length],
            style: TextStyle(
                color: DeepGuardColors.primary.withAlpha(alpha),
                fontSize: 8, fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(s.width / 2 - tp.width / 2, y));
    }
  }
  @override
  bool shouldRepaint(_RailP o) => o.t != t;
}
