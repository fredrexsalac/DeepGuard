import 'package:flutter_test/flutter_test.dart';

import 'package:deepfake_flutter_app/services/face_crop_service.dart';

/// Covers the crop geometry that decides what the deployed image model is
/// actually shown. The ML Kit call itself is Android-only and is not exercised
/// here; every rule below is pure arithmetic on the detection result.
void main() {
  group('cropForFace', () {
    test('a face that fills a square crop leaves it untouched', () {
      // The property that justifies the whole change: the training images are
      // already 256×256 face-filling squares, so framing them must be a no-op
      // and the held-out accuracy measured on them still describes the app.
      final crop = FaceCropService.cropForFace(
        faceLeft: 8, faceTop: 10, faceWidth: 240, faceHeight: 236,
        imageWidth: 256, imageHeight: 256,
      )!;
      expect(crop.isIdentity(256, 256), isTrue);
      expect(crop.side, 256);
    });

    test('a small face in a wide photo is centred and grown with margin', () {
      // 4000×3000 frame, face ~200×260 near the middle: without a crop the
      // face reaches the model as ~9×12 px after the 128×128 resize.
      final crop = FaceCropService.cropForFace(
        faceLeft: 1900, faceTop: 1100, faceWidth: 200, faceHeight: 260,
        imageWidth: 4000, imageHeight: 3000,
      )!;
      expect(crop.side, (260 * FaceCropService.defaultMargin).round());
      expect(crop.left + crop.side ~/ 2, closeTo(2000, 1));
      expect(crop.top + crop.side ~/ 2, closeTo(1230, 1));
      expect(crop.right, lessThanOrEqualTo(4000));
      expect(crop.bottom, lessThanOrEqualTo(3000));
    });

    test('a face at the edge is slid back inside the frame', () {
      final crop = FaceCropService.cropForFace(
        faceLeft: 0, faceTop: 0, faceWidth: 120, faceHeight: 150,
        imageWidth: 1080, imageHeight: 1920,
      )!;
      expect(crop.left, 0);
      expect(crop.top, 0);
      expect(crop.side, (150 * FaceCropService.defaultMargin).round());
    });

    test('crop never exceeds the shortest edge of the image', () {
      final crop = FaceCropService.cropForFace(
        faceLeft: 10, faceTop: 10, faceWidth: 900, faceHeight: 1200,
        imageWidth: 1000, imageHeight: 1500,
      )!;
      expect(crop.side, 1000); // clamped to the width, not 1200 * margin
      expect(crop.bottom, lessThanOrEqualTo(1500));
    });

    test('degenerate detections are rejected rather than cropped blindly', () {
      expect(
        FaceCropService.cropForFace(
            faceLeft: 0, faceTop: 0, faceWidth: 0, faceHeight: 10,
            imageWidth: 100, imageHeight: 100),
        isNull,
      );
      expect(
        FaceCropService.cropForFace(
            faceLeft: 0, faceTop: 0, faceWidth: 10, faceHeight: 10,
            imageWidth: 0, imageHeight: 100),
        isNull,
      );
    });

    test('invariant: the square always sits fully inside the image', () {
      // Sweep plausible detector output across several photo shapes.
      const shapes = [(4000, 3000), (1080, 1920), (256, 256), (640, 480)];
      for (final (w, h) in shapes) {
        for (var fw = 4; fw <= w; fw += (w ~/ 7).clamp(1, 1 << 30)) {
          for (var fh = 4; fh <= h; fh += (h ~/ 5).clamp(1, 1 << 30)) {
            if (fw > w || fh > h) continue;
            for (final pos in [(0, 0), (w - fw, h - fh), ((w - fw) ~/ 2, (h - fh) ~/ 2)]) {
              final crop = FaceCropService.cropForFace(
                faceLeft: pos.$1, faceTop: pos.$2, faceWidth: fw, faceHeight: fh,
                imageWidth: w, imageHeight: h,
              )!;
              expect(crop.left, greaterThanOrEqualTo(0));
              expect(crop.top, greaterThanOrEqualTo(0));
              expect(crop.right, lessThanOrEqualTo(w));
              expect(crop.bottom, lessThanOrEqualTo(h));
              expect(crop.side, crop.bottom - crop.top);
            }
          }
        }
      }
    });
  });

  group('SquareCrop', () {
    test('identity only when it is literally the whole image', () {
      const full = SquareCrop(0, 0, 256);
      expect(full.isIdentity(256, 256), isTrue);
      expect(const SquareCrop(4, 0, 256).isIdentity(256, 256), isFalse);
      expect(const SquareCrop(0, 0, 255).isIdentity(256, 256), isFalse);
    });
  });
}
