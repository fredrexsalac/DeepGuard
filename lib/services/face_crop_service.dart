import 'app_log.dart' as dev;
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/analysis_framing.dart';

/// FaceCropService
///
/// Frames the IMAGE branch of the classifier on the detected face, using the
/// already-deployed deepguard_image.tflite UNCHANGED.
///
/// WHY THIS EXISTS
/// Every training image in the dataset is a 256x256 square in which the face
/// fills the frame (verified against the archive: 20,000 real + 20,000 fake,
/// all 256x256). The model therefore never learned to look at a wide photograph
/// — it learned to look at a face that occupies the image. DeepGuard's own
/// preprocessing then resizes WHOLE frames to 128x128, so an ordinary camera
/// photo in which the face is 10% of the frame reaches the model as a face of
/// roughly 13 pixels and its artifacts are gone before inference begins.
/// Cropping first puts the input back into the shape the weights expect.
///
/// WHAT DOES NOT CHANGE
///   - The model, its tensors, the [0,255] raw-float rule and the 0.5 threshold.
///   - The video branch: DFD clip framing was not verified, so video keeps its
///     existing whole-frame path rather than inheriting an unproven assumption.
///   - The media shown to the user: the preview stays the original file. Only
///     the bytes fed to the interpreter are the crop.
///
/// SAFETY RULES
/// Nothing here may invent a verdict. If no face is found, if detection fails,
/// or if the platform has no ML Kit (desktop, tests), the original whole-frame
/// image is returned untouched and the reason is logged. Behaviour in those
/// cases is exactly what it was before this file existed.

/// A square region inside a decoded image, in pixel coordinates.
class SquareCrop {
  final int left;
  final int top;

  /// Side length in pixels — width and height are always equal, because every
  /// training image is square.
  final int side;

  const SquareCrop(this.left, this.top, this.side);

  int get right => left + side;
  int get bottom => top + side;

  /// True when the crop is the entire image, i.e. cropping would change nothing.
  bool isIdentity(int imageWidth, int imageHeight) =>
      left == 0 && top == 0 && side == imageWidth && side == imageHeight;

  @override
  String toString() => '[$left,$top ${side}x$side]';
}

/// Result of framing one image for analysis.
class FaceCropOutcome {
  /// The image to hand to the classifier — the crop, or the original.
  final img.Image image;

  /// Faces ML Kit reported, so a log can distinguish "one big face" from
  /// "twelve strangers in a crowd shot".
  final int faceCount;

  /// The region actually used, or null when the whole frame was kept.
  final SquareCrop? crop;

  /// Human-readable reason the crop was or was not applied (diagnostics only).
  final String note;

  /// The largest detected face, in decoded-frame coordinates. Recorded even
  /// when no crop followed from it, because "a face was found and already
  /// filled the frame" and "no face was found at all" produce identical
  /// verdicts whose reliability differs completely.
  final BoxRect? faceRect;

  /// Size of the decoded frame those coordinates belong to, EXIF already
  /// applied — the same space `img.decodeImage` produced.
  final int frameWidth;
  final int frameHeight;

  const FaceCropOutcome({
    required this.image,
    required this.faceCount,
    required this.crop,
    required this.note,
    required this.frameWidth,
    required this.frameHeight,
    this.faceRect,
  });

  bool get applied => crop != null;

  factory FaceCropOutcome.wholeFrame(img.Image image, String why,
          {int faceCount = 0, BoxRect? faceRect}) =>
      FaceCropOutcome(
          image: image,
          faceCount: faceCount,
          crop: null,
          note: why,
          faceRect: faceRect,
          frameWidth: image.width,
          frameHeight: image.height);

  /// The framing record handed to the UI and persisted with the history entry.
  /// Centralised here so no call site can quietly drop the geometry again.
  AnalysisFraming toFraming() => AnalysisFraming(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        faceCount: faceCount,
        faceRect: faceRect,
        analysedRect: crop == null
            ? null
            : BoxRect(crop!.left, crop!.top, crop!.side, crop!.side),
        note: note,
      );
}

class FaceCropService {
  static final FaceCropService _instance = FaceCropService._internal();
  factory FaceCropService() => _instance;
  FaceCropService._internal();

  /// Extra room around the detected box, as a multiple of its largest edge.
  /// 1.6 keeps hair, chin and a band of background — the framing a 256x256
  /// face crop has — without pulling in so much surroundings that the face
  /// stops dominating the square.
  static const double defaultMargin = 1.6;

  /// Pure geometry, no plugin: the square crop that [faceWidth]x[faceHeight]
  /// at (faceLeft, faceTop) implies inside an imageWidth x imageHeight frame.
  ///
  /// Returns null only when the inputs are not usable. The box is clamped so
  /// the crop always stays inside the image: the square is grown first, then
  /// slid back into bounds, which keeps the face centred whenever the frame
  /// allows it and simply touches an edge when it does not.
  static SquareCrop? cropForFace({
    required int faceLeft,
    required int faceTop,
    required int faceWidth,
    required int faceHeight,
    required int imageWidth,
    required int imageHeight,
    double margin = defaultMargin,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;
    if (faceWidth <= 0 || faceHeight <= 0) return null;

    var side = (faceWidth > faceHeight ? faceWidth : faceHeight) * margin;
    final shortest = imageWidth < imageHeight ? imageWidth : imageHeight;
    if (side > shortest) side = shortest.toDouble();
    final s = side.round();
    if (s <= 0) return null;

    final cx = faceLeft + faceWidth / 2;
    final cy = faceTop + faceHeight / 2;

    var left = (cx - s / 2).round();
    var top = (cy - s / 2).round();
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (left > imageWidth - s) left = imageWidth - s;
    if (top > imageHeight - s) top = imageHeight - s;

    return SquareCrop(left, top, s);
  }

  /// Detects the largest face in [filePath] and returns the cropped image to
  /// analyse. Never throws: every failure path falls back to the whole frame.
  Future<FaceCropOutcome> frameForAnalysis({
    required String filePath,
    required img.Image decoded,
  }) async {
    // ML Kit is Android/iOS only. On desktop and in unit tests the plugin has
    // no implementation, so the whole-frame path is kept deliberately.
    if (!Platform.isAndroid) {
      return FaceCropOutcome.wholeFrame(
          decoded, 'face framing skipped (non-Android target)');
    }

    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          // Accurate over fast: this runs once per file on a still image, and
          // the faces worth finding are the small ones in a wide photo.
          performanceMode: FaceDetectorMode.accurate,
          // ML Kit ignores faces below 10% of image width by default — the
          // exact faces this crop exists to rescue. Lower the floor so a face
          // in a crowd or a distant subject is still found and framed.
          minFaceSize: 0.02,
          enableTracking: false,
        ),
      );
      final faces = await detector.processImage(
        InputImage.fromFilePath(filePath),
      );
      await detector.close();
      detector = null;

      if (faces.isEmpty) {
        return FaceCropOutcome.wholeFrame(
            decoded, 'no face detected; whole frame analysed',
            faceCount: 0);
      }

      // Largest box by area: one clear subject beats a crowd of small ones,
      // and depth is unknowable from a bounding box alone.
      Face? best;
      var bestArea = 0;
      for (final f in faces) {
        final area = (f.boundingBox.width * f.boundingBox.height).toInt();
        if (area > bestArea) {
          bestArea = area;
          best = f;
        }
      }
      if (best == null || bestArea <= 0) {
        return FaceCropOutcome.wholeFrame(
            decoded, 'detected face had no usable bounds',
            faceCount: faces.length);
      }

      final box = best.boundingBox;
      // Kept for the UI regardless of what the crop decision turns out to be.
      final faceRect = BoxRect(
        box.left.toInt(),
        box.top.toInt(),
        box.width.toInt(),
        box.height.toInt(),
      );
      final crop = cropForFace(
        faceLeft: box.left.toInt(),
        faceTop: box.top.toInt(),
        faceWidth: box.width.toInt(),
        faceHeight: box.height.toInt(),
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );

      if (crop == null) {
        return FaceCropOutcome.wholeFrame(
            decoded, 'crop geometry rejected the detection',
            faceCount: faces.length, faceRect: faceRect);
      }
      if (crop.isIdentity(decoded.width, decoded.height)) {
        // The face already fills the frame — the in-distribution case, and the
        // one where crop and whole frame are provably the same bytes.
        return FaceCropOutcome.wholeFrame(
            decoded, 'face already fills the frame; nothing to crop',
            faceCount: faces.length, faceRect: faceRect);
      }

      final cropped = img.copyCrop(
        decoded,
        x: crop.left,
        y: crop.top,
        width: crop.side,
        height: crop.side,
      );

      dev.log(
        '[DeepGuard][FACE-CROP] faces=${faces.length}  '
        'faceBox=[${box.left.toInt()},${box.top.toInt()} '
        '${box.width.toInt()}x${box.height.toInt()}]  '
        'frame=${decoded.width}x${decoded.height} -> crop=$crop  '
        'coverage=${(crop.side * crop.side / (decoded.width * decoded.height) * 100).toStringAsFixed(1)}%',
        name: 'DeepGuard',
      );

      return FaceCropOutcome(
        image: cropped,
        faceCount: faces.length,
        crop: crop,
        note: 'face region analysed',
        faceRect: faceRect,
        // The crop replaced `image`, so the frame size has to be carried
        // separately — the overlay maps these back onto the ORIGINAL file the
        // user is shown, never onto the cropped bytes.
        frameWidth: decoded.width,
        frameHeight: decoded.height,
      );
    } catch (e) {
      // MissingPluginException, unreadable path, model unavailable, OOM on a
      // huge photo: all of them mean "analyse the frame as before".
      final pending = detector;
      if (pending != null) {
        try {
          await pending.close();
        } catch (_) {
          // Releasing the detector is best-effort; the fallback stands either way.
        }
      }
      dev.log('[DeepGuard][FACE-CROP] fallback to whole frame: $e',
          name: 'DeepGuard');
      return FaceCropOutcome.wholeFrame(
          decoded, 'face detection unavailable ($e); whole frame analysed');
    }
  }
}
