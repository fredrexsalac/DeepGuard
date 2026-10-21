import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/deepguard_detection_result.dart';
import '../screens/upload_screen.dart' show MediaSource;

/// DeepGuardTFLiteService
///
/// Owns and manages the two separate TFLite interpreters:
///   - deepguard_image.tflite  →  analyzeImage()
///   - deepguard_video.tflite  →  analyzeVideo()
///
/// ─── CONFIRMED TENSOR LAYOUTS (binary + notebook inspection) ───────────────
///
///   IMAGE MODEL
///     IN  [0] 'serving_default_image_input_tflite_compatible:0'
///             shape=[1, 128, 128, 3]  dtype=float32
///     OUT [0] 'StatefulPartitionedCall_1:0'
///             shape=[1, 1]            dtype=float32
///     Output is a raw sigmoid scalar.
///     >= 0.5  →  Fake  (MANIPULATED)
///     <  0.5  →  Real  (AUTHENTIC)
///
///   VIDEO MODEL
///     IN  [0] 'serving_default_video_input:0'
///             shape=[1, 10, 128, 128, 3]  dtype=float32
///     OUT [0] 'StatefulPartitionedCall_1:0'
///             shape=[1, 1]               dtype=float32
///     Same sigmoid interpretation as image.
///
/// ─── PREPROCESSING PIPELINE (must match training notebook exactly) ─────────
///
///   The training pipeline (Cell 18 / Cell 20 / Cell 78) does:
///     1. Decode image → RGB channels
///     2. Resize to 128 × 128  (INTER_AREA / tf.image.resize)
///     3. Cast to float32
///     4. Feed directly to model  ← NO /255.0 normalization
///
///   EfficientNetB0 contains its own internal rescaling layer.
///   The model therefore expects raw pixel values in [0.0, 255.0].
///
///   ⚠️  DO NOT divide pixel values by 255.0.
///   ⚠️  Doing so produces values in [0.0, 1.0] which makes
///       EfficientNetB0's internal rescaling produce near-zero
///       feature maps, collapsing every prediction to ~0.0 (Authentic).
///
/// ─── CONFIRMED BY COLAB TFLite VERIFICATION (Cell 78) ─────────────────────
///   A real image fed WITHOUT /255.0 -> output 0.01437  (low/Real  — correct)
///   A real video fed WITHOUT /255.0 -> output 0.6449   (high/Fake — a FALSE
///       POSITIVE: the video branch is weakly calibrated, NOT inverted. The
///       deployed .tflite matches the original .keras within ~0.01, so this is
///       a model-quality limit, not a pipeline/conversion bug.)
class DeepGuardTFLiteService {
  // ── Asset paths ────────────────────────────────────────────────────────────
  static const String _imageModelAsset = 'assets/models/deepguard_image.tflite';
  static const String _videoModelAsset = 'assets/models/deepguard_video.tflite';

  // ── Model dimensions ───────────────────────────────────────────────────────
  static const int imgSize    = 128;
  static const int videoFrames = 10;

  // ── Interpreters ───────────────────────────────────────────────────────────
  Interpreter? _imageInterpreter;
  Interpreter? _videoInterpreter;

  bool _imageReady = false;
  bool _videoReady = false;

  bool get imageModelReady => _imageReady;
  bool get videoModelReady => _videoReady;
  bool get allModelsReady  => _imageReady && _videoReady;

  // ── Singleton ──────────────────────────────────────────────────────────────
  static final DeepGuardTFLiteService _instance =
      DeepGuardTFLiteService._internal();
  factory DeepGuardTFLiteService() => _instance;
  DeepGuardTFLiteService._internal();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> loadModels() async {
    await _loadImageModel();
    await _loadVideoModel();
  }

  Future<void> _loadImageModel() async {
    if (_imageReady && _imageInterpreter != null) return;
    try {
      final opts = InterpreterOptions()..threads = 2;
      _imageInterpreter = await Interpreter.fromAsset(
          _imageModelAsset, options: opts);
      _imageInterpreter!.allocateTensors();
      _imageReady = true;
      dev.log('[DeepGuard] Image model loaded | '
          'IN=${_imageInterpreter!.getInputTensor(0).shape}  '
          'OUT=${_imageInterpreter!.getOutputTensor(0).shape}',
          name: 'DeepGuard');
    } catch (e, st) {
      _imageReady = false;
      dev.log('[DeepGuard] Image model load FAILED: $e\n$st',
          name: 'DeepGuard');
      rethrow;
    }
  }

  Future<void> _loadVideoModel() async {
    if (_videoReady && _videoInterpreter != null) return;
    try {
      final opts = InterpreterOptions()..threads = 2;
      _videoInterpreter = await Interpreter.fromAsset(
          _videoModelAsset, options: opts);
      _videoInterpreter!.allocateTensors();
      _videoReady = true;
      dev.log('[DeepGuard] Video model loaded | '
          'IN=${_videoInterpreter!.getInputTensor(0).shape}  '
          'OUT=${_videoInterpreter!.getOutputTensor(0).shape}',
          name: 'DeepGuard');
    } catch (e, st) {
      _videoReady = false;
      dev.log('[DeepGuard] Video model load FAILED: $e\n$st',
          name: 'DeepGuard');
      rethrow;
    }
  }

  void disposeModels() {
    _imageInterpreter?.close();
    _imageInterpreter = null;
    _imageReady = false;
    _videoInterpreter?.close();
    _videoInterpreter = null;
    _videoReady = false;
    dev.log('[DeepGuard] Models disposed.', name: 'DeepGuard');
  }

  // ── Image inference ────────────────────────────────────────────────────────

  /// Runs deepfake detection on a decoded [img.Image].
  ///
  /// Preprocessing pipeline (matches training notebook exactly):
  ///   1. Resize to 128 × 128
  ///   2. Extract RGB channels as float32 in [0.0, 255.0]  ← NO /255.0
  ///   3. Shape: [1, 128, 128, 3]
  ///
  /// EfficientNetB0 handles its own internal rescaling.
  ///
  /// [source] is used only for diagnostic logging — it does not affect output.
  Future<DeepGuardDetectionResult> analyzeImage(
    img.Image rawImage, {
    MediaSource source = MediaSource.gallery,
  }) async {
    if (!_imageReady) await _loadImageModel();

    final start = DateTime.now().millisecondsSinceEpoch;
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';

    try {
      // Original decoded dimensions (EXIF already applied by img.decodeImage)
      final origW = rawImage.width;
      final origH = rawImage.height;
      final origChannels = rawImage.numChannels;

      // Resize to 128×128  (average ≈ cv2.INTER_AREA — matches training Cell 18)
      final resized = img.copyResize(
        rawImage,
        width: imgSize,
        height: imgSize,
        interpolation: img.Interpolation.average,
      );

      // Build [1, 128, 128, 3] tensor — raw float32, range [0.0, 255.0]
      final input  = _buildImageTensor(resized);
      final output = List.generate(1, (_) => List<double>.filled(1, 0.0));

      _imageInterpreter!.run(input, output);

      final fakeProbability =
          (output[0][0] as num).toDouble().clamp(0.0, 1.0);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - start;
      final isFake = fakeProbability >= 0.5;
      final confidence = isFake ? fakeProbability : (1.0 - fakeProbability);

      // ── FULL DIAGNOSTIC LOG (all 15 required fields) ──────────────────────
      final samplePixel = resized.getPixel(64, 64);
      final sampleR = samplePixel.r.toInt();
      final sampleG = samplePixel.g.toInt();
      final sampleB = samplePixel.b.toInt();

      dev.log(
        '[DeepGuard][IMAGE][INFERENCE]\n'
        '  1.  mediaType           : image\n'
        '  2.  source              : $sourceLabel\n'
        '  3.  originalDimensions  : $origW×$origH  channels=$origChannels\n'
        '  4.  decodedDimensions   : $origW×$origH  (EXIF auto-applied)\n'
        '  5.  resizedDimensions   : $imgSize×$imgSize\n'
        '  6.  colorFormat         : RGB\n'
        '  7.  normalization       : raw float32  range=[0,255]  NO /255 division\n'
        '  8.  samplePixel(64,64)  : R=$sampleR G=$sampleG B=$sampleB\n'
        '  9.  tensorShape         : [1, $imgSize, $imgSize, 3]\n'
        ' 10.  tensorDtype         : float32\n'
        ' 11.  modelInputShape     : [1, 128, 128, 3]\n'
        ' 12.  rawTFLiteOutput     : ${fakeProbability.toStringAsFixed(6)}\n'
        ' 13.  threshold           : 0.5\n'
        ' 14.  predictedClass      : ${isFake ? "Fake" : "Real"}  (Real=0  Fake=1)\n'
        ' 15.  displayLabel        : ${isFake ? "MANIPULATED" : "AUTHENTIC"}\n'
        '      confidence          : ${(confidence * 100).toStringAsFixed(2)}%\n'
        '      latencyMs           : ${latencyMs}ms',
        name: 'DeepGuard',
      );

      return DeepGuardDetectionResult.fromFakeProbability(
        fakeProbability: fakeProbability,
        latencyMs: latencyMs,
      );
    } catch (e, st) {
      dev.log('[DeepGuard] analyzeImage ERROR: $e\n$st', name: 'DeepGuard');
      rethrow;
    }
  }

  /// Runs deepfake detection on a 10-frame video sequence.
  ///
  /// Preprocessing pipeline (matches training notebook exactly):
  ///   1. Resize each frame to 128 × 128
  ///   2. Extract RGB channels as float32 in [0.0, 255.0]  ← NO /255.0
  ///   3. Assemble [1, 10, 128, 128, 3]
  ///
  /// [source] is used only for diagnostic logging — it does not affect output.
  Future<DeepGuardDetectionResult> analyzeVideo(
    List<img.Image> frames, {
    MediaSource source = MediaSource.gallery,
  }) async {
    if (!_videoReady) await _loadVideoModel();
    if (frames.isEmpty) {
      throw ArgumentError('analyzeVideo: frames list must not be empty.');
    }

    final start = DateTime.now().millisecondsSinceEpoch;
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';

    try {
      // Pad to exactly videoFrames if necessary
      final padded = List<img.Image>.from(frames);
      while (padded.length < videoFrames) {
        padded.add(padded.last);
      }
      final sequence = padded.sublist(0, videoFrames);

      // Original frame dimensions before resize
      final origW = sequence[0].width;
      final origH = sequence[0].height;

      // Build [1, 10, 128, 128, 3] tensor — raw float32, range [0.0, 255.0]
      final input  = _buildVideoTensor(sequence);
      final output = List.generate(1, (_) => List<double>.filled(1, 0.0));

      _videoInterpreter!.run(input, output);

      final fakeProbability =
          (output[0][0] as num).toDouble().clamp(0.0, 1.0);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - start;
      final isFake = fakeProbability >= 0.5;
      final confidence = isFake ? fakeProbability : (1.0 - fakeProbability);

      // ── FULL DIAGNOSTIC LOG (all 15 required fields) ──────────────────────
      // Sample pixel from frame 0 to confirm range is [0, 255] not [0, 1].
      // Note: _buildVideoTensor resizes internally; sample from the already-
      // resized result by using an intermediate crop.
      final resizedFrame0 = img.copyResize(
        sequence[0], width: imgSize, height: imgSize,
        interpolation: img.Interpolation.average,
      );
      final sp = resizedFrame0.getPixel(64, 64);

      dev.log(
        '[DeepGuard][VIDEO][INFERENCE]\n'
        '  1.  mediaType           : video\n'
        '  2.  source              : $sourceLabel\n'
        '  3.  originalDimensions  : $origW×$origH\n'
        '  4.  framesExtracted     : ${frames.length}\n'
        '  5.  framesPadded        : ${padded.length}  (target=$videoFrames)\n'
        '  6.  resizedDimensions   : $imgSize×$imgSize  per frame\n'
        '  7.  colorFormat         : RGB  (video_thumbnail returns JPEG→RGB)\n'
        '  8.  normalization       : raw float32  range=[0,255]  NO /255 division\n'
        '  9.  samplePixelF0(64,64): R=${sp.r.toInt()} G=${sp.g.toInt()} B=${sp.b.toInt()}\n'
        ' 10.  tensorShape         : [1, $videoFrames, $imgSize, $imgSize, 3]\n'
        ' 11.  tensorDtype         : float32\n'
        ' 12.  modelInputShape     : [1, 10, 128, 128, 3]\n'
        ' 13.  rawTFLiteOutput     : ${fakeProbability.toStringAsFixed(6)}\n'
        ' 14.  threshold           : 0.5\n'
        ' 15.  predictedClass      : ${isFake ? "Fake" : "Real"}  (Real=0  Fake=1)\n'
        '      displayLabel        : ${isFake ? "MANIPULATED" : "AUTHENTIC"}\n'
        '      confidence          : ${(confidence * 100).toStringAsFixed(2)}%\n'
        '      latencyMs           : ${latencyMs}ms',
        name: 'DeepGuard',
      );

      return DeepGuardDetectionResult.fromFakeProbability(
        fakeProbability: fakeProbability,
        latencyMs: latencyMs,
      );
    } catch (e, st) {
      dev.log('[DeepGuard] analyzeVideo ERROR: $e\n$st', name: 'DeepGuard');
      rethrow;
    }
  }

  // ── Tensor builders ────────────────────────────────────────────────────────

  /// Builds [1, 128, 128, 3] float32 tensor.
  ///
  /// ⚠️  Pixel values are in [0.0, 255.0] — NOT divided by 255.
  ///     EfficientNetB0 has its own internal Rescaling(1/255) layer.
  ///     Dividing here would give the model near-zero inputs and
  ///     collapse all predictions to ~0 (Authentic).
  List<List<List<List<double>>>> _buildImageTensor(img.Image frame) {
    return [
      List.generate(imgSize, (y) =>
        List.generate(imgSize, (x) {
          final p = frame.getPixel(x, y);
          // Raw uint8 → float32, range [0.0, 255.0]
          return [
            p.r.toInt().clamp(0, 255).toDouble(),
            p.g.toInt().clamp(0, 255).toDouble(),
            p.b.toInt().clamp(0, 255).toDouble(),
          ];
        }),
      ),
    ];
  }

  /// Builds [1, 10, 128, 128, 3] float32 tensor.
  ///
  /// ⚠️  Same no-normalization rule as _buildImageTensor.
  List<List<List<List<List<double>>>>> _buildVideoTensor(
      List<img.Image> frames) {
    return [
      List.generate(videoFrames, (f) {
        final resized = img.copyResize(
          frames[f],
          width: imgSize,
          height: imgSize,
          interpolation: img.Interpolation.average, // matches INTER_AREA
        );
        return List.generate(imgSize, (y) =>
          List.generate(imgSize, (x) {
            final p = resized.getPixel(x, y);
            // Raw uint8 → float32, range [0.0, 255.0]
            return [
              p.r.toInt().clamp(0, 255).toDouble(),
              p.g.toInt().clamp(0, 255).toDouble(),
              p.b.toInt().clamp(0, 255).toDouble(),
            ];
          }),
        );
      }),
    ];
  }

  // ── Diagnostic mode ────────────────────────────────────────────────────────

  /// Runs a full diagnostic inference pass and returns an
  /// [InferenceDiagnosticReport] that exposes every step of the pipeline.
  ///
  /// For images, pass [image] and leave [videoFrames] null.
  /// For videos, pass [videoFrames] and leave [image] null.
  ///
  /// The report is also written to the Dart developer log under the
  /// 'DeepGuard' name so it appears in Logcat / Flutter DevTools.
  Future<InferenceDiagnosticReport> runDiagnostic({
    img.Image? image,
    List<img.Image>? videoFrameList,
  }) async {
    assert(
      (image != null) ^ (videoFrameList != null),
      'Provide exactly one of image or videoFrameList.',
    );

    final isImage = image != null;
    final mediaType = isImage ? 'image' : 'video';

    // ── Build the tensor using the exact same path as analyzeImage/analyzeVideo
    late final Float32List flat;
    late final List<int> tensorShape;

    if (isImage) {
      if (!_imageReady) await _loadImageModel();
      final resized = img.copyResize(
        image,
        width: imgSize,
        height: imgSize,
        interpolation: img.Interpolation.average,
      );
      tensorShape = [1, imgSize, imgSize, 3];
      flat = _imageToFlat(resized);
    } else {
      if (!_videoReady) await _loadVideoModel();
      final padded = List<img.Image>.from(videoFrameList!);
      while (padded.length < videoFrames) {
        padded.add(padded.last);
      }
      final sequence = padded.sublist(0, videoFrames);
      tensorShape = [1, videoFrames, imgSize, imgSize, 3];
      flat = _videoToFlat(sequence);
    }

    // ── Pixel range audit
    double minVal = flat[0], maxVal = flat[0];
    for (final v in flat) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    // ── Run actual inference
    final start = DateTime.now().millisecondsSinceEpoch;
    double rawOutput;

    if (isImage) {
      final input  = _buildImageTensor(
        img.copyResize(image, width: imgSize, height: imgSize,
            interpolation: img.Interpolation.average));
      final output = List.generate(1, (_) => List<double>.filled(1, 0.0));
      _imageInterpreter!.run(input, output);
      rawOutput = (output[0][0] as num).toDouble().clamp(0.0, 1.0);
    } else {
      final padded = List<img.Image>.from(videoFrameList!);
      while (padded.length < videoFrames) {
        padded.add(padded.last);
      }
      final input  = _buildVideoTensor(padded.sublist(0, videoFrames));
      final output = List.generate(1, (_) => List<double>.filled(1, 0.0));
      _videoInterpreter!.run(input, output);
      rawOutput = (output[0][0] as num).toDouble().clamp(0.0, 1.0);
    }

    final latencyMs = DateTime.now().millisecondsSinceEpoch - start;
    final isFake    = rawOutput >= 0.5;
    final confidence = isFake ? rawOutput : (1.0 - rawOutput);

    final report = InferenceDiagnosticReport(
      mediaType          : mediaType,
      inputTensorShape   : tensorShape,
      inputDtype         : 'float32',
      pixelRangeMin      : minVal,
      pixelRangeMax      : maxVal,
      rawTFLiteOutput    : rawOutput,
      fakeProbability    : rawOutput,
      classMapping       : '0=Real (AUTHENTIC)  1=Fake (MANIPULATED)',
      threshold          : 0.5,
      predictedClass     : isFake ? 'Fake' : 'Real',
      displayedConfidence: '${(confidence * 100).toStringAsFixed(2)}%',
      latencyMs          : latencyMs,
    );

    // Write full diagnostic to developer log
    dev.log(report.toLogString(), name: 'DeepGuard');

    // Warn if pixel range looks wrong (would indicate accidental /255 somewhere)
    if (maxVal < 2.0) {
      dev.log(
        '[DeepGuard][DIAGNOSTIC] ⚠ WARNING: maxPixel=$maxVal — values appear '
        'to be in [0,1] range. The model expects [0,255]. '
        'Check for an accidental /255.0 division in the preprocessing path.',
        name: 'DeepGuard',
      );
    }

    return report;
  }

  // ── Flat tensor helpers (diagnostic only) ─────────────────────────────────

  /// Flattens a resized [img.Image] to a Float32List in [0,255] range.
  Float32List _imageToFlat(img.Image frame) {
    final out = Float32List(imgSize * imgSize * 3);
    int idx = 0;
    for (int y = 0; y < imgSize; y++) {
      for (int x = 0; x < imgSize; x++) {
        final p = frame.getPixel(x, y);
        out[idx++] = p.r.toInt().clamp(0, 255).toDouble();
        out[idx++] = p.g.toInt().clamp(0, 255).toDouble();
        out[idx++] = p.b.toInt().clamp(0, 255).toDouble();
      }
    }
    return out;
  }

  /// Flattens a 10-frame video sequence to a Float32List in [0,255] range.
  Float32List _videoToFlat(List<img.Image> frames) {
    final out = Float32List(videoFrames * imgSize * imgSize * 3);
    int idx = 0;
    for (int f = 0; f < videoFrames; f++) {
      final resized = img.copyResize(frames[f],
          width: imgSize, height: imgSize,
          interpolation: img.Interpolation.average);
      for (int y = 0; y < imgSize; y++) {
        for (int x = 0; x < imgSize; x++) {
          final p = resized.getPixel(x, y);
          out[idx++] = p.r.toInt().clamp(0, 255).toDouble();
          out[idx++] = p.g.toInt().clamp(0, 255).toDouble();
          out[idx++] = p.b.toInt().clamp(0, 255).toDouble();
        }
      }
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic support
// ─────────────────────────────────────────────────────────────────────────────

/// Full diagnostic report produced by [DeepGuardTFLiteService.runDiagnostic].
///
/// Exposes every step of the inference pipeline so mismatches between
/// the Flutter app and the training notebook can be traced.
///
/// Diagnostic items logged (to match task requirements):
///   1.  mediaType          — 'image' or 'video'
///   2.  inputTensorShape   — e.g. [1, 128, 128, 3]
///   3.  inputDtype         — always 'float32'
///   4.  pixelRangeMin/Max  — should be ~0 / ~255, never ~0 / ~1
///   5.  rawTFLiteOutput    — the exact scalar from the model
///   6.  fakeProbability    — same as rawTFLiteOutput (already a sigmoid scalar)
///   7.  classMapping       — '0=Real  1=Fake'
///   8.  threshold          — 0.5
///   9.  predictedClass     — 'Real' or 'Fake'
///   10. displayedConfidence — e.g. '87.45%'
class InferenceDiagnosticReport {
  final String mediaType;
  final List<int> inputTensorShape;
  final String inputDtype;
  final double pixelRangeMin;
  final double pixelRangeMax;
  final double rawTFLiteOutput;
  final double fakeProbability;
  final String classMapping;
  final double threshold;
  final String predictedClass;
  final String displayedConfidence;
  final int latencyMs;

  const InferenceDiagnosticReport({
    required this.mediaType,
    required this.inputTensorShape,
    required this.inputDtype,
    required this.pixelRangeMin,
    required this.pixelRangeMax,
    required this.rawTFLiteOutput,
    required this.fakeProbability,
    required this.classMapping,
    required this.threshold,
    required this.predictedClass,
    required this.displayedConfidence,
    required this.latencyMs,
  });

  /// Pretty-prints the full diagnostic as a single log-friendly string.
  String toLogString() => '''
╔══════════════════════════════════════════════════════════════
║  DeepGuard Inference Diagnostic
╠══════════════════════════════════════════════════════════════
║  1. mediaType           : $mediaType
║  2. inputTensorShape    : $inputTensorShape
║  3. inputDtype          : $inputDtype
║  4. pixelRangeMin       : ${pixelRangeMin.toStringAsFixed(2)}
║     pixelRangeMax       : ${pixelRangeMax.toStringAsFixed(2)}
║     ⚠  Expected range   : [0, 255]  (NOT [0, 1])
║  5. rawTFLiteOutput     : ${rawTFLiteOutput.toStringAsFixed(6)}
║  6. fakeProbability     : ${fakeProbability.toStringAsFixed(6)}
║  7. classMapping        : $classMapping
║  8. threshold           : $threshold
║  9. predictedClass      : $predictedClass
║ 10. displayedConfidence : $displayedConfidence
║     latencyMs           : ${latencyMs}ms
╚══════════════════════════════════════════════════════════════''';

  @override
  String toString() => toLogString();
}
