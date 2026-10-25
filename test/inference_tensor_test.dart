import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:flutter_test/flutter_test.dart';

import 'package:deepfake_flutter_app/services/inference_tensor.dart';

/// Pins the byte layout of the buffers fed to the deployed TFLite models.
///
/// This is the contract that broke once already during development: the models
/// expect raw [0,255] float32 because EfficientNetB0 rescales internally, and
/// dividing by 255 silently collapses every verdict to "Authentic". A test is
/// worth more than a comment here, because the failure mode is silent and the
/// symptom (everything is real) is indistinguishable from a working app.
///
/// inference_tensor.dart deliberately imports nothing from tflite_flutter, so
/// these run on the host VM where the native TFLite library cannot be loaded.
void main() {
  /// A 128×128 image with an unambiguous per-pixel signature: r encodes x,
  /// g encodes y, b encodes (x+y) mod 256. Any transpose, stride error or
  /// channel reorder changes at least one of the three.
  img.Image signatureFrame() {
    final frame = img.Image(width: 128, height: 128, numChannels: 3);
    for (var y = 0; y < 128; y++) {
      for (var x = 0; x < 128; x++) {
        frame.setPixelRgb(x, y, x, y, (x + y) % 256);
      }
    }
    return frame;
  }

  int offset(int x, int y, int c) => 3 * (128 * y + x) + c;

  group('imageFlat layout', () {
    test('produces exactly one float32 per input element', () {
      final flat = InferenceTensors.imageFlat(signatureFrame());
      expect(flat.length, InferenceTensors.imageElementCount);
      expect(flat.length, 128 * 128 * 3);
      expect(flat.buffer.asUint8List().length, InferenceTensors.imageByteLength);
      expect(InferenceTensors.imageByteLength, 196608);
    });

    test('NHWC row-major: pixel (x,y) lands at 3 * (size*y + x)', () {
      final flat = InferenceTensors.imageFlat(signatureFrame());
      for (final spot in [
        [0, 0],
        [1, 0],
        [0, 1],
        [63, 64],
        [127, 127],
      ]) {
        final x = spot[0], y = spot[1];
        expect(flat[offset(x, y, 0)], x.toDouble(), reason: 'R at ($x,$y)');
        expect(flat[offset(x, y, 1)], y.toDouble(), reason: 'G at ($x,$y)');
        expect(flat[offset(x, y, 2)], ((x + y) % 256).toDouble(),
            reason: 'B at ($x,$y)');
      }
    });

    test('values stay in [0,255] — no /255 normalisation anywhere', () {
      // The regression this guards is invisible from the outside: a /255 makes
      // the model answer ~0.0 (Authentic) for literally every input.
      final flat = InferenceTensors.imageFlat(signatureFrame());
      double min = flat[0], max = flat[0];
      for (final v in flat) {
        if (v < min) min = v;
        if (v > max) max = v;
      }
      expect(min, 0.0);
      expect(max, 254.0); // highest channel value the signature can produce
      expect(max, greaterThan(1.0));
    });

    test('the flat buffer is little-endian float32 when viewed as bytes', () {
      // This is what lets the worker call Tensor.setTo(bytes) instead of
      // run(nestedList): the package's own converter writes each float as
      // little-endian 4 bytes, so a raw Float32List view is byte-identical on
      // Android (ARM64, little-endian).
      final flat = InferenceTensors.imageFlat(signatureFrame());
      final bytes =
          flat.buffer.asUint8List(flat.offsetInBytes, flat.lengthInBytes);
      final view = ByteData.sublistView(bytes);
      expect(view.getFloat32(0, Endian.little), flat[0]);
      expect(view.getFloat32(4, Endian.little), flat[1]);
      expect(view.getFloat32(12, Endian.little), flat[3]);
    });

    test('flat buffer is element-for-element the nested list the app shipped',
        () {
      // referenceNested is copied verbatim from the pre-isolate
      // DeepGuardTFLiteService._buildImageTensor: it reads the pixels directly
      // rather than unflattening the buffer under test, so agreement is a real
      // cross-check of the ordering claim and not a tautology.
      List<List<List<List<double>>>> referenceNested(img.Image frame) => [
            List.generate(128, (y) => List.generate(128, (x) {
                  final p = frame.getPixel(x, y);
                  return [
                    p.r.toInt().clamp(0, 255).toDouble(),
                    p.g.toInt().clamp(0, 255).toDouble(),
                    p.b.toInt().clamp(0, 255).toDouble(),
                  ];
                })),
          ];

      final frame = signatureFrame();
      final fromFlat =
          InferenceTensors.nestedFromImageFlat(InferenceTensors.imageFlat(frame));
      final fromPixels = referenceNested(frame);

      expect(fromFlat.length, fromPixels.length);
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          expect(fromFlat[0][y][x], fromPixels[0][y][x],
              reason: 'channel mismatch at ($x,$y)');
        }
      }
    });

    test('refuses a frame that was not resized to 128x128', () {
      final wrong = img.Image(width: 256, height: 256, numChannels: 3);
      expect(() => InferenceTensors.imageFlat(wrong), throwsArgumentError);
    });
  });

  group('videoFlat layout', () {
    img.Image frame(int seed) {
      final f = img.Image(width: 64, height: 64, numChannels: 3);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          f.setPixelRgb(x, y, (x + seed) % 256, (y * 3 + seed) % 256, seed);
        }
      }
      return f;
    }

    test('pads to ten frames worth of elements', () {
      final flat = InferenceTensors.videoFlat(
        List.generate(InferenceTensors.videoFrames, frame),
      );
      expect(flat.length, InferenceTensors.videoElementCount);
      expect(flat.length, 10 * InferenceTensors.imageElementCount);
    });

    test('frame f starts at f * imageElementCount', () {
      final flat = InferenceTensors.videoFlat(
        List.generate(InferenceTensors.videoFrames, frame),
      );
      final secondFrameStart = InferenceTensors.imageElementCount;
      // Frame 1 was built with seed 1, so its (0,0) blue channel is 1.
      expect(flat[secondFrameStart + 2], 1.0);
      expect(flat[2 * secondFrameStart + 2], 2.0);
    });

    test('refuses the wrong frame count instead of guessing', () {
      expect(() => InferenceTensors.videoFlat([frame(0)]), throwsArgumentError);
      expect(
        () => InferenceTensors.videoFlat(
            List.generate(11, frame)),
        throwsArgumentError,
      );
    });
  });

  group('constants', () {
    test('agree with the tensor shapes documented in the service', () {
      expect(InferenceTensors.imgSize, 128);
      expect(InferenceTensors.videoFrames, 10);
      expect(InferenceTensors.imageElementCount * 4,
          InferenceTensors.imageByteLength);
      expect(InferenceTensors.videoElementCount * 4,
          InferenceTensors.videoByteLength);
    });
  });
}
