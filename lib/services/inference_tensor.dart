import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// InferenceTensors
///
/// The exact input buffers fed to the two DeepGuard TFLite models, isolated in
/// a file that imports nothing from `tflite_flutter`. That is deliberate: the
/// native TFLite library cannot be loaded by `flutter test` on the host, so
/// keeping the tensor construction here is what makes the byte layout testable
/// at all. Everything that touches an `Interpreter` lives in
/// [InferenceIsolate](inference_isolate.dart) instead.
///
/// ─── LAYOUT CONTRACT ───────────────────────────────────────────────────────
///
/// Both models take NHWC float32, row-major, raw pixel values in [0.0, 255.0]:
///
///   image  [1, 128, 128, 3]   49,152 floats   196,608 bytes
///   video  [1, 10, 128, 128, 3]  491,520 floats  1,966,080 bytes
///
/// Element (0, y, x, c) sits at flat index `3 * (size * y + x) + c`, so pixel
/// (0,0) contributes R,G,B at indices 0,1,2 and pixel (1,0) at 3,4,5.
///
/// ⚠  NO /255 NORMALISATION. EfficientNetB0 carries its own internal
///    Rescaling(1/255). Dividing here collapses every prediction to ~0.0
///    (Authentic). See DeepGuardTFLiteService's class comment for the
///    Colab-verified evidence.
class InferenceTensors {
  const InferenceTensors._();

  // ── Model dimensions ───────────────────────────────────────────────────────
  static const int imgSize = 128;
  static const int videoFrames = 10;

  static const int imageElementCount = imgSize * imgSize * 3;
  static const int videoElementCount = videoFrames * imgSize * imgSize * 3;

  /// Number of bytes the interpreter's input tensor must be.
  static const int imageByteLength = imageElementCount * 4;
  static const int videoByteLength = videoElementCount * 4;

  // ── Flat buffers (the path actually used at runtime) ───────────────────────

  /// Builds the [1, 128, 128, 3] input as a flat float32 buffer.
  ///
  /// [frame] must ALREADY be resized to [imgSize] x [imgSize]; see
  /// [resizeForImage].
  static Float32List imageFlat(img.Image frame) {
    _expectSquare(frame);
    final out = Float32List(imageElementCount);
    var idx = 0;
    for (var y = 0; y < imgSize; y++) {
      for (var x = 0; x < imgSize; x++) {
        final p = frame.getPixel(x, y);
        out[idx++] = _channel(p.r);
        out[idx++] = _channel(p.g);
        out[idx++] = _channel(p.b);
      }
    }
    return out;
  }

  /// Builds the [1, 10, 128, 128, 3] input as a flat float32 buffer.
  ///
  /// Resizes each frame internally, matching the historical behaviour of
  /// `_buildVideoTensor`. [frames] must already be padded/trimmed to exactly
  /// [videoFrames].
  static Float32List videoFlat(List<img.Image> frames) {
    if (frames.length != videoFrames) {
      throw ArgumentError(
          'videoFlat: expected exactly $videoFrames frames, got '
          '${frames.length}. Pad before calling.');
    }
    final out = Float32List(videoElementCount);
    var idx = 0;
    for (var f = 0; f < videoFrames; f++) {
      final resized = resizeForImage(frames[f]);
      for (var y = 0; y < imgSize; y++) {
        for (var x = 0; x < imgSize; x++) {
          final p = resized.getPixel(x, y);
          out[idx++] = _channel(p.r);
          out[idx++] = _channel(p.g);
          out[idx++] = _channel(p.b);
        }
      }
    }
    return out;
  }

  /// The resize both branches apply: 128x128 with average interpolation,
  /// which is the Dart equivalent of the `cv2.INTER_AREA` /
  /// `tf.image.resize` used in training (notebook Cell 18 / Cell 20).
  static img.Image resizeForImage(img.Image source) => img.copyResize(
        source,
        width: imgSize,
        height: imgSize,
        interpolation: img.Interpolation.average,
      );

  // ── Reference nested builder ───────────────────────────────────────────────

  /// Reconstructs the nested form from a flat buffer.
  ///
  /// The app used to hand `Interpreter.run` a nested list of exactly this
  /// shape. It is retained so a test can assert that the flat buffer the
  /// worker now passes is element-for-element the same data, i.e. that moving
  /// to a raw byte transfer changed nothing about what the model sees.
  static List<List<List<List<double>>>> nestedFromImageFlat(Float32List flat) {
    _expectLength(flat, imageElementCount, 'image');
    return [
      List.generate(imgSize, (y) => List.generate(imgSize, (x) {
            final o = 3 * (imgSize * y + x);
            return [flat[o], flat[o + 1], flat[o + 2]];
          })),
    ];
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static double _channel(num v) => v.toInt().clamp(0, 255).toDouble();

  static void _expectSquare(img.Image frame) {
    if (frame.width != imgSize || frame.height != imgSize) {
      throw ArgumentError(
          'imageFlat: expected a $imgSize x $imgSize frame, got '
          '${frame.width} x ${frame.height}. Call resizeForImage() first.');
    }
  }

  static void _expectLength(Float32List flat, int expected, String label) {
    if (flat.length != expected) {
      throw ArgumentError(
          '$label flat buffer must hold $expected float32 values, got '
          '${flat.length}.');
    }
  }
}
