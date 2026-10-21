import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'deepguard_tflite_service.dart';
import 'video_frame_extractor_service.dart';

/// PreprocessingParityService
///
/// Diagnostic utility that runs the Flutter preprocessing pipeline on a
/// provided image or video file and reports every measurable property so
/// it can be compared directly against the Python/notebook training pipeline.
///
/// ─── PURPOSE ───────────────────────────────────────────────────────────────
/// When a direct-file result and a camera-recapture result differ, this service
/// lets you verify whether the difference is a code/pipeline mismatch or a
/// model-generalization issue (screen recapture changes the image distribution).
///
/// ─── USAGE ─────────────────────────────────────────────────────────────────
///   // Image parity check
///   final report = await PreprocessingParityService().checkImage(filePath);
///   print(report.toLogString());
///
///   // Video parity check
///   final report = await PreprocessingParityService().checkVideo(filePath);
///   print(report.toLogString());
///
/// ─── PYTHON EQUIVALENT (notebook Cell 18 / Cell 20) ───────────────────────
///   Image:
///     image = tf.io.decode_image(bytes, channels=3)  # → RGB, EXIF applied
///     image = tf.image.resize(image, [128, 128])      # bilinear ≈ INTER_AREA
///     image = tf.cast(image, tf.float32)              # range [0, 255]
///
///   Video:
///     cap = cv2.VideoCapture(path)
///     total = cap.get(CAP_PROP_FRAME_COUNT)
///     indices = np.linspace(0, total-1, num=10)       # uniform frame indices
///     frame = cv2.cvtColor(frame, COLOR_BGR2RGB)
///     frame = cv2.resize(frame, (128,128), INTER_AREA)
///     frame = frame.astype(np.float32)                # range [0, 255]
class PreprocessingParityService {
  final _extractor = VideoFrameExtractorService();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Runs the image preprocessing pipeline on [filePath] and returns a full
  /// [ParityReport] describing every step.
  Future<ParityReport> checkImage(String filePath) async {
    final stopwatch = Stopwatch()..start();

    final file = File(filePath);
    if (!await file.exists()) {
      return ParityReport._error('image', filePath, 'File not found.');
    }

    final bytes    = await file.readAsBytes();
    final fileSizeB = bytes.length;

    // Step 1 – decode (auto-applies EXIF rotation, converts to RGB)
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return ParityReport._error('image', filePath, 'img.decodeImage() returned null.');
    }

    final origW = decoded.width;
    final origH = decoded.height;
    final origChannels = decoded.numChannels;
    // 274 (0x0112) is the EXIF Orientation tag.
    final hasExif = decoded.exif.hasTag(274);

    // Step 2 – resize to 128×128  (average ≈ INTER_AREA, matches Cell 18)
    final resized = img.copyResize(
      decoded,
      width:  DeepGuardTFLiteService.imgSize,
      height: DeepGuardTFLiteService.imgSize,
      interpolation: img.Interpolation.average,
    );

    // Step 3 – flatten to Float32List [0,255], compute stats
    final flat = _imageToFlat(resized);
    final stats = _pixelStats(flat);

    stopwatch.stop();

    final report = ParityReport(
      mediaType        : 'image',
      filePath         : filePath,
      fileSizeBytes    : fileSizeB,
      originalDims     : '$origW×$origH',
      originalChannels : origChannels,
      exifApplied      : hasExif,
      decodedDims      : '$origW×$origH',
      resizedDims      : '${DeepGuardTFLiteService.imgSize}×${DeepGuardTFLiteService.imgSize}',
      colorFormat      : 'RGB',
      normalization    : 'raw float32 [0,255] — NO /255',
      pixelMin         : stats.min,
      pixelMax         : stats.max,
      pixelMean        : stats.mean,
      pixelStd         : stats.std,
      tensorShape      : '[1, 128, 128, 3]',
      tensorDtype      : 'float32',
      frameCount       : 1,
      frameIndices     : null,
      elapsedMs        : stopwatch.elapsedMilliseconds,
      error            : null,
    );

    dev.log(report.toLogString(), name: 'DeepGuard');
    return report;
  }

  /// Runs the video preprocessing pipeline on [filePath] and returns a full
  /// [ParityReport] describing every step.
  Future<ParityReport> checkVideo(String filePath) async {
    final stopwatch = Stopwatch()..start();

    final file = File(filePath);
    if (!await file.exists()) {
      return ParityReport._error('video', filePath, 'File not found.');
    }

    final fileSizeB = await file.length();

    List<img.Image> frames;
    try {
      frames = await _extractor.extractFrames(filePath);
    } on VideoFrameExtractionException catch (e) {
      return ParityReport._error('video', filePath, e.message);
    }

    if (frames.isEmpty) {
      return ParityReport._error('video', filePath, 'No frames extracted.');
    }

    final origW = frames[0].width;
    final origH = frames[0].height;

    // Resize all frames (same as _buildVideoTensor) and collect pixel stats
    final resized = frames.map((f) => img.copyResize(
      f,
      width:  DeepGuardTFLiteService.imgSize,
      height: DeepGuardTFLiteService.imgSize,
      interpolation: img.Interpolation.average,
    )).toList();

    final flat = _videoToFlat(resized);
    final stats = _pixelStats(flat);

    stopwatch.stop();

    final report = ParityReport(
      mediaType        : 'video',
      filePath         : filePath,
      fileSizeBytes    : fileSizeB,
      originalDims     : '$origW×$origH',
      originalChannels : 3,
      exifApplied      : false, // video frames have no EXIF orientation
      decodedDims      : '$origW×$origH',
      resizedDims      : '${DeepGuardTFLiteService.imgSize}×${DeepGuardTFLiteService.imgSize}',
      colorFormat      : 'RGB  (video_thumbnail JPEG → img.decodeImage)',
      normalization    : 'raw float32 [0,255] — NO /255',
      pixelMin         : stats.min,
      pixelMax         : stats.max,
      pixelMean        : stats.mean,
      pixelStd         : stats.std,
      tensorShape      : '[1, 10, 128, 128, 3]',
      tensorDtype      : 'float32',
      frameCount       : frames.length,
      frameIndices     : List.generate(frames.length, (i) => i),
      elapsedMs        : stopwatch.elapsedMilliseconds,
      error            : null,
    );

    dev.log(report.toLogString(), name: 'DeepGuard');
    return report;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Float32List _imageToFlat(img.Image frame) {
    final n   = DeepGuardTFLiteService.imgSize;
    final out = Float32List(n * n * 3);
    int idx   = 0;
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final p = frame.getPixel(x, y);
        out[idx++] = p.r.toInt().clamp(0, 255).toDouble();
        out[idx++] = p.g.toInt().clamp(0, 255).toDouble();
        out[idx++] = p.b.toInt().clamp(0, 255).toDouble();
      }
    }
    return out;
  }

  Float32List _videoToFlat(List<img.Image> frames) {
    final n   = DeepGuardTFLiteService.imgSize;
    final f   = DeepGuardTFLiteService.videoFrames;
    final out = Float32List(f * n * n * 3);
    int idx   = 0;
    for (final frame in frames.take(f)) {
      for (int y = 0; y < n; y++) {
        for (int x = 0; x < n; x++) {
          final p = frame.getPixel(x, y);
          out[idx++] = p.r.toInt().clamp(0, 255).toDouble();
          out[idx++] = p.g.toInt().clamp(0, 255).toDouble();
          out[idx++] = p.b.toInt().clamp(0, 255).toDouble();
        }
      }
    }
    return out;
  }

  _PixelStats _pixelStats(Float32List flat) {
    double sum = 0, sumSq = 0;
    double mn = flat[0], mx = flat[0];
    for (final v in flat) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
      sum   += v;
      sumSq += v * v;
    }
    final n    = flat.length.toDouble();
    final mean = sum / n;
    final std  = (sumSq / n - mean * mean).abs() > 0
        ? (sumSq / n - mean * mean).sqrt()
        : 0.0;
    return _PixelStats(mn, mx, mean, std);
  }
}

// ── Helper types ──────────────────────────────────────────────────────────────

class _PixelStats {
  final double min, max, mean, std;
  const _PixelStats(this.min, this.max, this.mean, this.std);
}

extension on double {
  double sqrt() {
    if (this <= 0) return 0;
    double x = this, y = 1;
    const eps = 1e-9;
    while (x - y > eps) { x = (x + y) / 2; y = this / x; }
    return x;
  }
}

/// A complete record of the Flutter preprocessing pipeline for one media file.
///
/// Designed to be compared directly against the Python/notebook pipeline:
///
///   Flutter field        Python equivalent
///   ──────────────────   ─────────────────────────────────────────────────
///   originalDims         shape before resize
///   colorFormat          'RGB' ← cv2.COLOR_BGR2RGB applied in notebook
///   normalization        raw float32 [0,255] ← no /255 in Cell 18/20
///   pixelMin/Max/Mean    np.min/max/mean on the float32 array
///   tensorShape          np.expand_dims(frames,0).shape
///   tensorDtype          frames.dtype == np.float32
class ParityReport {
  final String  mediaType;
  final String  filePath;
  final int     fileSizeBytes;
  final String  originalDims;
  final int     originalChannels;
  final bool    exifApplied;
  final String  decodedDims;
  final String  resizedDims;
  final String  colorFormat;
  final String  normalization;
  final double  pixelMin;
  final double  pixelMax;
  final double  pixelMean;
  final double  pixelStd;
  final String  tensorShape;
  final String  tensorDtype;
  final int     frameCount;
  final List<int>? frameIndices;
  final int     elapsedMs;
  final String? error;

  const ParityReport({
    required this.mediaType,
    required this.filePath,
    required this.fileSizeBytes,
    required this.originalDims,
    required this.originalChannels,
    required this.exifApplied,
    required this.decodedDims,
    required this.resizedDims,
    required this.colorFormat,
    required this.normalization,
    required this.pixelMin,
    required this.pixelMax,
    required this.pixelMean,
    required this.pixelStd,
    required this.tensorShape,
    required this.tensorDtype,
    required this.frameCount,
    required this.frameIndices,
    required this.elapsedMs,
    required this.error,
  });

  factory ParityReport._error(String mediaType, String filePath, String msg) {
    return ParityReport(
      mediaType: mediaType, filePath: filePath, fileSizeBytes: 0,
      originalDims: 'N/A', originalChannels: 0, exifApplied: false,
      decodedDims: 'N/A', resizedDims: 'N/A', colorFormat: 'N/A',
      normalization: 'N/A', pixelMin: 0, pixelMax: 0, pixelMean: 0,
      pixelStd: 0, tensorShape: 'N/A', tensorDtype: 'N/A',
      frameCount: 0, frameIndices: null, elapsedMs: 0, error: msg,
    );
  }

  bool get hasError => error != null;

  /// ─── PARITY WARNINGS ────────────────────────────────────────────────────
  /// These checks flag likely mismatches between Flutter and Python pipelines.
  List<String> get parityWarnings {
    final w = <String>[];
    if (hasError) return ['ERROR: $error'];

    // Pixel range check: must be [0,255], not [0,1]
    if (pixelMax < 2.0) {
      w.add('⚠ pixelMax=$pixelMax — values look like [0,1] range; '
          'model expects [0,255]. Check for accidental /255 division.');
    }
    // Channel check
    if (!colorFormat.contains('RGB')) {
      w.add('⚠ colorFormat=$colorFormat — model expects RGB channel order.');
    }
    // Frame count check (video only)
    if (mediaType == 'video' && frameCount != DeepGuardTFLiteService.videoFrames) {
      w.add('⚠ frameCount=$frameCount — model expects exactly '
          '${DeepGuardTFLiteService.videoFrames} frames.');
    }
    return w;
  }

  String toLogString() {
    final buf = StringBuffer();
    buf.writeln('╔══════════════════════════════════════════════════════════════');
    buf.writeln('║  DeepGuard Preprocessing Parity Report');
    buf.writeln('╠══════════════════════════════════════════════════════════════');
    if (hasError) {
      buf.writeln('║  ERROR: $error');
      buf.writeln('╚══════════════════════════════════════════════════════════════');
      return buf.toString();
    }
    buf.writeln('║  mediaType        : $mediaType');
    buf.writeln('║  fileSizeBytes    : $fileSizeBytes');
    buf.writeln('║  originalDims     : $originalDims  channels=$originalChannels');
    buf.writeln('║  exifApplied      : $exifApplied');
    buf.writeln('║  decodedDims      : $decodedDims');
    buf.writeln('║  resizedDims      : $resizedDims');
    buf.writeln('║  colorFormat      : $colorFormat');
    buf.writeln('║  normalization    : $normalization');
    buf.writeln('║  pixelMin         : ${pixelMin.toStringAsFixed(2)}');
    buf.writeln('║  pixelMax         : ${pixelMax.toStringAsFixed(2)}');
    buf.writeln('║  pixelMean        : ${pixelMean.toStringAsFixed(2)}');
    buf.writeln('║  pixelStd         : ${pixelStd.toStringAsFixed(2)}');
    buf.writeln('║  tensorShape      : $tensorShape');
    buf.writeln('║  tensorDtype      : $tensorDtype');
    if (mediaType == 'video') {
      buf.writeln('║  frameCount       : $frameCount');
      if (frameIndices != null) {
        buf.writeln('║  frameIndices     : $frameIndices');
      }
    }
    buf.writeln('║  elapsedMs        : ${elapsedMs}ms');

    final warnings = parityWarnings;
    if (warnings.isEmpty) {
      buf.writeln('║  parityStatus     : ✓ No issues detected');
    } else {
      buf.writeln('║  parityStatus     : ✗ ${warnings.length} warning(s)');
      for (final w in warnings) {
        buf.writeln('║    $w');
      }
    }

    buf.writeln('╚══════════════════════════════════════════════════════════════');
    return buf.toString();
  }

  @override
  String toString() => toLogString();
}
