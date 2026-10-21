import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// TfliteService
///
/// Legacy service retained only for backward-compatibility. No active code path
/// calls this class (it is not exported from index.dart and not imported by any
/// screen or service). All production inference now goes through
/// [DeepGuardTFLiteService].
///
/// Model dimensions:
///   Image: deepguard_image.tflite   IN [1,128,128,3]   OUT [1,1]
///   Video: deepguard_video.tflite   IN [1,10,128,128,3] OUT [1,1]
///
/// ⚠️  NORMALIZATION (must match training notebook Cell 18 / Cell 20):
///   Both models expect raw float32 pixel values in [0.0, 255.0].
///   Do NOT divide by 255.0 — EfficientNetB0 contains its own internal
///   Rescaling(1/255) layer. Dividing here would feed [0,1] values to a
///   layer that rescales again, producing near-zero feature maps and
///   collapsing every prediction to ~0 (Authentic).
///
/// New code should use [DeepGuardTFLiteService] directly.
class TfliteService {
  static final TfliteService _instance = TfliteService._internal();
  factory TfliteService() => _instance;
  TfliteService._internal();

  static const String _imageModelPath = 'assets/models/deepguard_image.tflite';
  static const String _videoModelPath = 'assets/models/deepguard_video.tflite';
  static const int _imgSize     = 128;
  static const int _videoFrames = 10;

  Interpreter? _imageInterpreter;
  Interpreter? _videoInterpreter;
  bool _isReady = false;

  bool get isReady => _isReady;

  Future<void> initialize() async {
    if (_isReady) return;
    try {
      final opts = InterpreterOptions()..threads = 2;
      _imageInterpreter = await Interpreter.fromAsset(
          _imageModelPath, options: opts);
      _imageInterpreter!.allocateTensors();

      _videoInterpreter = await Interpreter.fromAsset(
          _videoModelPath, options: opts);
      _videoInterpreter!.allocateTensors();

      _isReady = true;

      dev.log('[TfliteService] Both models loaded.', name: 'DeepGuard');
      dev.log('[TfliteService] Image IN=${_imageInterpreter!.getInputTensor(0).shape}'
          ' OUT=${_imageInterpreter!.getOutputTensor(0).shape}',
          name: 'DeepGuard');
      dev.log('[TfliteService] Video IN=${_videoInterpreter!.getInputTensor(0).shape}'
          ' OUT=${_videoInterpreter!.getOutputTensor(0).shape}',
          name: 'DeepGuard');
    } catch (e) {
      _isReady = false;
      rethrow;
    }
  }

  // ── Image inference ────────────────────────────────────────────────────────

  Future<double> predictImage(Uint8List imageBytes) async {
    if (!_isReady) await initialize();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Could not decode image');

    // Use average interpolation — matches cv2.INTER_AREA used in training
    // (Cell 20: cv2.resize(frame, IMAGE_SIZE, interpolation=cv2.INTER_AREA))
    final resized = img.copyResize(decoded,
        width: _imgSize, height: _imgSize,
        interpolation: img.Interpolation.average);

    return predictFrame(resized);
  }

  /// Runs inference on a single decoded frame. Input shape: [1, 128, 128, 3].
  Future<double> predictFrame(img.Image frame) async {
    if (!_isReady) await initialize();

    final input  = _buildImageTensor(frame);
    final output = [List<double>.filled(1, 0.0)];

    _imageInterpreter!.run(input, output);

    final score = (output[0][0] as num).toDouble();
    dev.log('[TfliteService] predictFrame fakeProbability=$score',
        name: 'DeepGuard');
    return score.clamp(0.0, 1.0);
  }

  // ── Video inference ────────────────────────────────────────────────────────

  Future<double> predictVideo(List<Uint8List> frameBytes) async {
    if (!_isReady) await initialize();
    if (frameBytes.isEmpty) throw Exception('No frames provided');

    final sampled = _sampleFrames(frameBytes, _videoFrames);
    final frames  = <img.Image>[];

    for (final fb in sampled) {
      final decoded = img.decodeImage(fb);
      if (decoded == null) continue;
      // Use average interpolation — matches cv2.INTER_AREA used in training
      // (Cell 20: cv2.resize(frame, IMAGE_SIZE, interpolation=cv2.INTER_AREA))
      frames.add(img.copyResize(decoded,
          width: _imgSize, height: _imgSize,
          interpolation: img.Interpolation.average));
    }

    while (frames.length < _videoFrames) {
      frames.add(frames.isNotEmpty
          ? frames.last
          : img.Image(width: _imgSize, height: _imgSize));
    }

    final input  = _buildVideoTensor(frames);
    final output = [List<double>.filled(1, 0.0)];

    _videoInterpreter!.run(input, output);

    final score = (output[0][0] as num).toDouble();
    dev.log('[TfliteService] predictVideo fakeProbability=$score',
        name: 'DeepGuard');
    return score.clamp(0.0, 1.0);
  }

  // ── Tensor builders ────────────────────────────────────────────────────────

  List<List<List<List<double>>>> _buildImageTensor(img.Image frame) {
    return [
      List.generate(_imgSize, (y) =>
        List.generate(_imgSize, (x) {
          final p = frame.getPixel(x, y);
          return [
            p.r.toInt().clamp(0, 255).toDouble(),
            p.g.toInt().clamp(0, 255).toDouble(),
            p.b.toInt().clamp(0, 255).toDouble(),
          ];
        }),
      ),
    ];
  }

  List<List<List<List<List<double>>>>> _buildVideoTensor(
      List<img.Image> frames) {
    return [
      List.generate(_videoFrames, (f) =>
        List.generate(_imgSize, (y) =>
          List.generate(_imgSize, (x) {
            final p = frames[f].getPixel(x, y);
            return [
              p.r.toInt().clamp(0, 255).toDouble(),
              p.g.toInt().clamp(0, 255).toDouble(),
              p.b.toInt().clamp(0, 255).toDouble(),
            ];
          }),
        ),
      ),
    ];
  }

  List<T> _sampleFrames<T>(List<T> frames, int count) {
    if (frames.length == count) return frames;
    if (frames.length < count) {
      final r = List<T>.from(frames);
      while (r.length < count) {
        r.add(frames.last);
      }
      return r;
    }
    final step = (frames.length - 1) / (count - 1);
    return List.generate(count,
        (i) => frames[(i * step).round().clamp(0, frames.length - 1)]);
  }

  void dispose() {
    _imageInterpreter?.close();
    _videoInterpreter?.close();
    _imageInterpreter = null;
    _videoInterpreter = null;
    _isReady = false;
  }
}
