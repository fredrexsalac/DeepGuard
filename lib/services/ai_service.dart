import 'app_log.dart' as dev;
import 'dart:io';

import 'package:image/image.dart' as img;

import '../models/prediction_result.dart';
import '../models/deepguard_detection_result.dart';
import '../models/analysis_framing.dart';
import '../screens/upload_screen.dart' show MediaSource;
import 'deepguard_tflite_service.dart';
import 'face_crop_service.dart';
import 'video_frame_extractor_service.dart';

/// AIService
///
/// High-level facade used by ProcessingScreen to run deepfake detection.
/// Delegates to:
///   - [DeepGuardTFLiteService]  for on-device inference
///   - [VideoFrameExtractorService]  for 10-frame video extraction
///
/// Both camera-captured and gallery-selected media arrive here as a saved
/// file path and follow exactly the same preprocessing path:
///   File.readAsBytes → img.decodeImage (auto-applies EXIF rotation)
///     → FaceCropService.frameForAnalysis  (IMAGE branch only: the largest
///       detected face is cropped to a square; no face / no ML Kit on this
///       platform keeps the whole frame)
///     → DeepGuardTFLiteService.analyzeImage
///       → copyResize(128×128, Interpolation.average)  [≡ cv2.INTER_AREA]
///       → _buildImageTensor  (raw float32, range [0, 255], NO /255)
///       → TFLite run
///
/// VIDEO IS DELIBERATELY NOT CROPPED. Its DFD source clips were never checked
/// for face-vs-full framing, so the temporal branch keeps the whole-frame path
/// it was validated on instead of inheriting an unproven assumption.
///
/// The [source] parameter ([MediaSource.camera] or [MediaSource.gallery]) is
/// used ONLY for diagnostic logging. It never influences the classification.
///
/// Classification policy (thesis-approved pipeline):
///   The Hybrid CNN-RNN model output IS the final classification. The raw
///   sigmoid probability and its derived Prediction Confidence are passed
///   through unchanged — never forced, boosted, or overridden.
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final _tflite    = DeepGuardTFLiteService();
  final _extractor = VideoFrameExtractorService();

  void dispose() {}

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Analyses a single image file using deepguard_image.tflite.
  ///
  /// [source] is passed only for diagnostic logging and never affects output.
  Future<PredictionResult> predictImage({
    required String id,
    required String filePath,
    MediaSource source = MediaSource.gallery,
  }) async {
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';
    try {
      await _tflite.loadModels();

      final file = File(filePath);
      if (!await file.exists()) {
        return _errorResult(id, filePath, MediaType.image, 'File not found.');
      }

      final fileSizeBytes = await file.length();
      dev.log(
        '[AIService][IMAGE] ── INPUT ──────────────────────────────────\n'
        '  mediaType   : image\n'
        '  source      : $sourceLabel\n'
        '  filePath    : $filePath\n'
        '  fileSizeB   : $fileSizeBytes\n'
        '  expectedInputShape : [1, 128, 128, 3]  float32\n'
        '  normalization      : raw [0,255]  (EfficientNetB0 rescales internally)\n'
        '  exifRotation       : auto-applied by img.decodeImage()',
        name: 'DeepGuard',
      );

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return _errorResult(
            id, filePath, MediaType.image, 'Could not decode image file.');
      }

      // Log original decoded dimensions (after EXIF rotation has been applied).
      dev.log(
        '[AIService][IMAGE] decoded: ${decoded.width}×${decoded.height}  '
        'channels=${decoded.numChannels}  '
        // 274 (0x0112) is the EXIF Orientation tag.
        'hasExif=${decoded.exif.hasTag(274)}  '
        'source=$sourceLabel',
        name: 'DeepGuard',
      );

      // Frame the classifier on the detected face. Every training image was a
      // 256×256 square with the face filling it, so a wide photo has to be
      // cropped BEFORE the 128×128 resize or the face arrives a few pixels
      // across and its artifacts are already gone. The deployed model itself is
      // untouched, and this never blocks analysis: no face, or no ML Kit on
      // this platform, falls back to the whole frame exactly as before.
      final framing = await FaceCropService().frameForAnalysis(
        filePath: filePath,
        decoded: decoded,
      );

      final tfliteResult =
          await _tflite.analyzeImage(framing.image, source: source);

      dev.log(
        '[AIService][IMAGE] ── OUTPUT ─────────────────────────────────\n'
        '  source            : $sourceLabel\n'
        '  framing           : ${framing.applied ? 'FACE CROP ${framing.crop} of ${decoded.width}x${decoded.height}' : 'WHOLE FRAME (${framing.note})'}\n'
        '  facesDetected     : ${framing.faceCount}\n'
        '  analysedByModel   : ${framing.image.width}x${framing.image.height}\n'
        '  rawTFLiteOutput   : ${tfliteResult.fakeProbability.toStringAsFixed(6)}\n'
        '  threshold         : 0.5\n'
        '  predictedClass    : ${tfliteResult.internalClassName}\n'
        '  confidence        : ${tfliteResult.confidencePercent}\n'
        '  displayLabel      : ${tfliteResult.displayLabel}',
        name: 'DeepGuard',
      );

      return _toPredictionResult(id, filePath, MediaType.image, tfliteResult,
          framing: framing.toFraming());
    } catch (e, st) {
      dev.log('[AIService] predictImage ERROR: $e\n$st', name: 'DeepGuard');
      return _errorResult(id, filePath, MediaType.image,
          'Image analysis failed: $e');
    }
  }

  /// Analyses a video file using deepguard_video.tflite.
  ///
  /// Extracts exactly 10 uniformly-spaced frames via [VideoFrameExtractorService],
  /// assembles [1, 10, 128, 128, 3] tensor, and runs inference.
  ///
  /// [source] is passed only for diagnostic logging and never affects output.
  Future<PredictionResult> predictVideo({
    required String id,
    required String filePath,
    MediaSource source = MediaSource.gallery,
  }) async {
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';
    try {
      await _tflite.loadModels();

      final file = File(filePath);
      if (!await file.exists()) {
        return _errorResult(id, filePath, MediaType.video, 'File not found.');
      }

      final fileSizeBytes = await file.length();
      dev.log(
        '[AIService][VIDEO] ── INPUT ──────────────────────────────────\n'
        '  mediaType   : video\n'
        '  source      : $sourceLabel\n'
        '  filePath    : $filePath\n'
        '  fileSizeB   : $fileSizeBytes\n'
        '  framesRequired     : 10\n'
        '  expectedInputShape : [1, 10, 128, 128, 3]  float32\n'
        '  normalization      : raw [0,255]  (EfficientNetB0 rescales internally)\n'
        '  frameThumbSize     : 512px (Dart resizes to 128×128 via INTER_AREA)',
        name: 'DeepGuard',
      );

      final frames = await _extractor.extractFrames(filePath);

      dev.log(
        '[AIService][VIDEO] extracted: ${frames.length} frames  '
        'source=$sourceLabel  '
        'dims=${frames.isNotEmpty ? "${frames[0].width}×${frames[0].height}" : "N/A"}',
        name: 'DeepGuard',
      );

      final tfliteResult = await _tflite.analyzeVideo(frames, source: source);

      dev.log(
        '[AIService][VIDEO] ── OUTPUT ─────────────────────────────────\n'
        '  source            : $sourceLabel\n'
        '  framesUsed        : ${frames.length}\n'
        '  rawTFLiteOutput   : ${tfliteResult.fakeProbability.toStringAsFixed(6)}\n'
        '  threshold         : 0.5\n'
        '  predictedClass    : ${tfliteResult.internalClassName}\n'
        '  confidence        : ${tfliteResult.confidencePercent}\n'
        '  displayLabel      : ${tfliteResult.displayLabel}',
        name: 'DeepGuard',
      );

      return _toPredictionResult(id, filePath, MediaType.video, tfliteResult);
    } on VideoFrameExtractionException catch (e) {
      dev.log('[AIService] predictVideo frame extraction failed: $e',
          name: 'DeepGuard');
      return _errorResult(id, filePath, MediaType.video,
          'Could not extract frames from video. '
          'Please ensure the video is a valid, readable file.');
    } catch (e, st) {
      dev.log('[AIService] predictVideo ERROR: $e\n$st', name: 'DeepGuard');
      return _errorResult(id, filePath, MediaType.video,
          'Video analysis failed: $e');
    }
  }

  // ── Conversion helpers ─────────────────────────────────────────────────────

  PredictionResult _toPredictionResult(
    String id,
    String filePath,
    MediaType type,
    DeepGuardDetectionResult r, {
    AnalysisFraming? framing,
  }) {
    return PredictionResult(
      id: id,
      filePath: filePath,
      mediaType: type,
      status: PredictionStatus.completed,
      result: r.isFake
          ? DetectionResult.manipulated
          : DetectionResult.authentic,
      confidence: r.confidence,
      // Video passes nothing: the temporal branch analyses whole frames by
      // design, so there is no crop to report and inventing one would be a lie.
      framing: framing,
    );
  }

  PredictionResult _errorResult(
      String id, String filePath, MediaType type, String message) {
    dev.log('[AIService] error: $message', name: 'DeepGuard');
    return PredictionResult(
      id: id,
      filePath: filePath,
      mediaType: type,
      status: PredictionStatus.error,
      errorMessage: message,
    );
  }
}
