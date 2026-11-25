import 'app_log.dart' as dev;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/prediction_result.dart';
import '../models/deepguard_detection_result.dart';
import '../models/analysis_framing.dart';
import '../models/gradcam_evidence.dart';
import '../screens/upload_screen.dart' show MediaSource;
import 'deepguard_tflite_service.dart';
import 'face_crop_service.dart';
import 'inference_tensor.dart';
import 'video_frame_extractor_service.dart';

/// Live progress snapshot emitted at real inference pipeline boundaries.
class AnalysisProgressUpdate {
  final int stageIndex;
  final String stageTitle;
  final String stageDetail;
  final int? completedUnits;
  final int? totalUnits;
  final BoxRect? detectedFaceRect;
  final int? frameWidth;
  final int? frameHeight;

  const AnalysisProgressUpdate({
    required this.stageIndex,
    required this.stageTitle,
    required this.stageDetail,
    this.completedUnits,
    this.totalUnits,
    this.detectedFaceRect,
    this.frameWidth,
    this.frameHeight,
  });

  /// True only when measurable progress units exist (e.g. extracted frames).
  bool get hasMeasurableProgress =>
      completedUnits != null && totalUnits != null && totalUnits! > 0;

  double? get progressFraction => hasMeasurableProgress
      ? (completedUnits! / totalUnits!).clamp(0.0, 1.0)
      : null;
}

typedef AnalysisProgressCallback = FutureOr<void> Function(
  AnalysisProgressUpdate update,
);

/// AIService
///
/// High-level facade used by ProcessingScreen to run deepfake detection.
/// Preserves the exact thesis-approved preprocessing and TFLite models:
///   - EfficientNetB0 + Hybrid CNN-RNN (LSTM) + Parallel Fusion +
///     Neuro-Symbolic Reasoning
///   - Raw [0.0, 255.0] float32 input tensors (no /255 division)
///   - Face cropping on IMAGE branch only; whole-frame sequence on VIDEO branch
///   - Sigmoid 0.5 classification threshold
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final _tflite = DeepGuardTFLiteService();
  final _extractor = VideoFrameExtractorService();

  void dispose() {}

  /// Canonical 6-stage checklist for Image analysis (Phase 7.1).
  static const List<(String, String)> imageStages = [
    ('Preparing image', 'Loading on-device model and reading image file…'),
    ('Checking image quality', 'Decoding image and verifying dimensions…'),
    ('Detecting human faces', 'Locating subject face region for analysis…'),
    (
      'Extracting visual features',
      'Preparing 128×128 RGB spatial input for EfficientNetB0…'
    ),
    (
      'Evaluating authenticity',
      'Running Hybrid CNN–RNN, Parallel Fusion, and Neuro-Symbolic Reasoning…'
    ),
    ('Preparing results', 'Finalizing classification and framing report…'),
  ];

  /// Canonical 9-stage checklist for Video analysis (Phase 7.2).
  static const List<(String, String)> videoStages = [
    ('Preparing video', 'Loading on-device model and verifying video file…'),
    ('Decoding video', 'Inspecting video stream duration and timestamps…'),
    ('Extracting frames', 'Sampling 10 uniformly spaced video frames…'),
    (
      'Filtering unsuitable frames',
      'Validating decoded frames and sequence integrity…'
    ),
    ('Detecting human faces', 'Checking subject presence in sampled frames…'),
    (
      'Extracting spatial features',
      'Preparing per-frame spatial inputs for EfficientNetB0…'
    ),
    (
      'Analyzing temporal features',
      'Running LSTM sequence, Parallel Fusion, and Neuro-Symbolic Reasoning…'
    ),
    ('Evaluating authenticity', 'Computing authenticity classification…'),
    ('Preparing results', 'Finalizing video analysis report…'),
  ];

  Future<void> _emit(
    AnalysisProgressCallback? cb,
    int index,
    List<(String, String)> table, {
    String? customDetail,
    int? completedUnits,
    int? totalUnits,
    BoxRect? detectedFaceRect,
    int? frameWidth,
    int? frameHeight,
  }) async {
    if (cb == null) return;
    final (title, defaultDetail) = table[index];
    await cb(
      AnalysisProgressUpdate(
        stageIndex: index,
        stageTitle: title,
        stageDetail: customDetail ?? defaultDetail,
        completedUnits: completedUnits,
        totalUnits: totalUnits,
        detectedFaceRect: detectedFaceRect,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      ),
    );
  }

  /// Analyses a single image file using `deepguard_image.tflite`.
  Future<PredictionResult> predictImage({
    required String id,
    required String filePath,
    MediaSource source = MediaSource.gallery,
    AnalysisProgressCallback? onProgress,
  }) async {
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';
    try {
      // Stage 0: Preparing image
      await _emit(onProgress, 0, imageStages);
      await _tflite.loadModels();

      final file = File(filePath);
      if (!await file.exists()) {
        return _errorResult(
          id,
          filePath,
          MediaType.image,
          'The selected image file could not be found on your device.',
        );
      }

      final fileSizeBytes = await file.length();
      if (fileSizeBytes == 0) {
        return _errorResult(
          id,
          filePath,
          MediaType.image,
          'The selected image file is empty or unreadable.',
        );
      }

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

      // Stage 1: Checking image quality
      await _emit(onProgress, 1, imageStages);
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return _errorResult(
          id,
          filePath,
          MediaType.image,
          'This image could not be decoded. It may be corrupted or in an unsupported format.',
        );
      }

      dev.log(
        '[AIService][IMAGE] decoded: ${decoded.width}×${decoded.height}  '
        'channels=${decoded.numChannels}  '
        'hasExif=${decoded.exif.hasTag(274)}  '
        'source=$sourceLabel',
        name: 'DeepGuard',
      );

      // Stage 2: Detecting human faces
      await _emit(
        onProgress,
        2,
        imageStages,
        frameWidth: decoded.width,
        frameHeight: decoded.height,
      );
      final framing = await FaceCropService().frameForAnalysis(
        filePath: filePath,
        decoded: decoded,
      );

      // Stages 3 & 4 fire inside analyzeImage at exact tensor & isolate boundaries
      final tfliteResult = await _tflite.analyzeImage(
        framing.image,
        source: source,
        onVisualFeaturesStarted: () => _emit(
          onProgress,
          3,
          imageStages,
          detectedFaceRect: framing.faceRect,
          frameWidth: decoded.width,
          frameHeight: decoded.height,
        ),
        onInferenceStarted: () => _emit(
          onProgress,
          4,
          imageStages,
          detectedFaceRect: framing.faceRect,
          frameWidth: decoded.width,
          frameHeight: decoded.height,
        ),
      );

      // Stage 5: Preparing results
      await _emit(
        onProgress,
        5,
        imageStages,
        detectedFaceRect: framing.faceRect,
        frameWidth: decoded.width,
        frameHeight: decoded.height,
      );

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

      GradCamEvidence? gradCam;
      if (tfliteResult.imageHeatmap != null &&
          tfliteResult.imageHeatmap!.length == 64 * 64) {
        final cropThumb = InferenceTensors.resizeForImage(framing.image);
        gradCam = GradCamEvidence(
          width: 64,
          height: 64,
          targetLabel: tfliteResult.isFake ? 'A.I.' : 'REAL',
          heatmap: tfliteResult.imageHeatmap!
              .map((v) => v.clamp(0.0, 1.0))
              .toList(growable: false),
          analyzedCropPngBase64: base64Encode(img.encodePng(cropThumb)),
        );
      }

      return _toPredictionResult(
        id,
        filePath,
        MediaType.image,
        tfliteResult,
        framing: framing.toFraming(),
        gradCam: gradCam,
      );
    } catch (e, st) {
      dev.log('[AIService] predictImage ERROR: $e\n$st', name: 'DeepGuard');
      return _errorResult(
        id,
        filePath,
        MediaType.image,
        'Image analysis could not be completed. Please verify the file is a valid image and try again.',
      );
    }
  }

  /// Analyses a video file using `deepguard_video.tflite`.
  Future<PredictionResult> predictVideo({
    required String id,
    required String filePath,
    MediaSource source = MediaSource.gallery,
    AnalysisProgressCallback? onProgress,
  }) async {
    final sourceLabel = source == MediaSource.camera ? 'CAMERA' : 'GALLERY';
    try {
      // Stage 0: Preparing video
      await _emit(onProgress, 0, videoStages);
      await _tflite.loadModels();

      final file = File(filePath);
      if (!await file.exists()) {
        return _errorResult(
          id,
          filePath,
          MediaType.video,
          'The selected video file could not be found on your device.',
        );
      }

      final fileSizeBytes = await file.length();
      if (fileSizeBytes == 0) {
        return _errorResult(
          id,
          filePath,
          MediaType.video,
          'The selected video file is empty or unreadable.',
        );
      }

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

      // Stages 1, 2, 3: Decoding video, Extracting frames (1..10), Filtering unsuitable frames
      final frames = await _extractor.extractFrames(
        filePath,
        onDecodingStarted: () => _emit(onProgress, 1, videoStages),
        onFrameExtracted: (extracted, total) => _emit(
          onProgress,
          2,
          videoStages,
          customDetail: 'Extracted frame $extracted of $total…',
          completedUnits: extracted,
          totalUnits: total,
        ),
        onFilteringStarted: () => _emit(onProgress, 3, videoStages),
      );

      dev.log(
        '[AIService][VIDEO] extracted: ${frames.length} frames  '
        'source=$sourceLabel  '
        'dims=${frames.isNotEmpty ? "${frames[0].width}×${frames[0].height}" : "N/A"}',
        name: 'DeepGuard',
      );

      // Stage 4: Detecting human faces (observational check ONLY — video frames
      // are deliberately NOT cropped so the [1, 10, 128, 128, 3] tensor keeps
      // its validated whole-frame distribution).
      final repFrame = frames.first;
      await _emit(
        onProgress,
        4,
        videoStages,
        frameWidth: repFrame.width,
        frameHeight: repFrame.height,
      );
      final detectedVideoFace = await _probeVideoFaceRect(repFrame);

      // Stages 5, 6, 7: Spatial features, Temporal features, Evaluating authenticity
      final tfliteResult = await _tflite.analyzeVideo(
        frames,
        source: source,
        onSpatialFeaturesStarted: () => _emit(
          onProgress,
          5,
          videoStages,
          detectedFaceRect: detectedVideoFace,
          frameWidth: repFrame.width,
          frameHeight: repFrame.height,
        ),
        onTemporalFeaturesStarted: () => _emit(
          onProgress,
          6,
          videoStages,
          detectedFaceRect: detectedVideoFace,
          frameWidth: repFrame.width,
          frameHeight: repFrame.height,
        ),
        onEvaluatingStarted: () => _emit(
          onProgress,
          7,
          videoStages,
          detectedFaceRect: detectedVideoFace,
          frameWidth: repFrame.width,
          frameHeight: repFrame.height,
        ),
      );

      // Stage 8: Preparing results
      await _emit(
        onProgress,
        8,
        videoStages,
        detectedFaceRect: detectedVideoFace,
        frameWidth: repFrame.width,
        frameHeight: repFrame.height,
      );

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

      // Build real Grad-CAM evidence for top 3 most influential frames out of 10
      GradCamEvidence? gradCam;
      final vMaps = tfliteResult.videoHeatmaps;
      final vScores = tfliteResult.videoFrameScores;
      if (vMaps != null &&
          vMaps.length == InferenceTensors.videoFrames &&
          vScores != null &&
          vScores.length == InferenceTensors.videoFrames) {
        // Ensure 10-frame padded sequence matches the tensor fed to the model
        final padded = List<img.Image>.from(frames);
        while (padded.length < InferenceTensors.videoFrames) {
          padded.add(padded.last);
        }
        final sequence = padded.sublist(0, InferenceTensors.videoFrames);

        final rankedIndices = List<int>.generate(
          InferenceTensors.videoFrames,
          (i) => i,
        )..sort((a, b) => vScores[b].compareTo(vScores[a]));

        final topIndices = rankedIndices.take(3).toList(growable: false);
        final topFrames = topIndices.map((idx) {
          final thumb = InferenceTensors.resizeForImage(sequence[idx]);
          return VideoFrameGradCam(
            frameIndex: idx,
            totalFrames: InferenceTensors.videoFrames,
            importanceScore: vScores[idx],
            heatmap: vMaps[idx]
                .map((v) => v.clamp(0.0, 1.0))
                .toList(growable: false),
            thumbnailPngBase64: base64Encode(img.encodePng(thumb)),
          );
        }).toList(growable: false);

        gradCam = GradCamEvidence(
          width: 64,
          height: 64,
          targetLabel: tfliteResult.isFake ? 'A.I.' : 'REAL',
          heatmap: topFrames.first.heatmap,
          topVideoFrames: topFrames,
        );
      }

      return _toPredictionResult(
        id,
        filePath,
        MediaType.video,
        tfliteResult,
        gradCam: gradCam,
      );
    } on VideoFrameExtractionException catch (e) {
      dev.log('[AIService] predictVideo frame extraction failed: $e',
          name: 'DeepGuard');
      return _errorResult(
        id,
        filePath,
        MediaType.video,
        'Insufficient readable video frames. Please select a clear, non-corrupted MP4, MOV, or AVI video clip.',
      );
    } catch (e, st) {
      dev.log('[AIService] predictVideo ERROR: $e\n$st', name: 'DeepGuard');
      return _errorResult(
        id,
        filePath,
        MediaType.video,
        'Video analysis could not be completed. Please verify the video format and try again.',
      );
    }
  }

  /// Observational face probe on one representative video frame so Stage 5
  /// ("Detecting human faces") runs real face detection on Android without
  /// modifying the uncropped video frame sequence.
  Future<BoxRect?> _probeVideoFaceRect(img.Image frame) async {
    if (!Platform.isAndroid) return null;
    File? tmpFile;
    FaceDetector? detector;
    try {
      final dir = await getTemporaryDirectory();
      tmpFile = File(
        '${dir.path}/dg_vface_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmpFile.writeAsBytes(img.encodeJpg(frame, quality: 90));
      detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.05,
        ),
      );
      final faces = await detector.processImage(
        InputImage.fromFilePath(tmpFile.path),
      );
      if (faces.isEmpty) return null;
      Face best = faces.first;
      double bestArea = best.boundingBox.width * best.boundingBox.height;
      for (final f in faces.skip(1)) {
        final area = f.boundingBox.width * f.boundingBox.height;
        if (area > bestArea) {
          best = f;
          bestArea = area;
        }
      }
      final b = best.boundingBox;
      return BoxRect(
        b.left.toInt(),
        b.top.toInt(),
        b.width.toInt(),
        b.height.toInt(),
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await detector?.close();
      } catch (_) {}
      try {
        if (tmpFile != null && await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  PredictionResult _toPredictionResult(
    String id,
    String filePath,
    MediaType type,
    DeepGuardDetectionResult r, {
    AnalysisFraming? framing,
    GradCamEvidence? gradCam,
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
      framing: framing,
      gradCam: gradCam,
    );
  }

  PredictionResult _errorResult(
    String id,
    String filePath,
    MediaType type,
    String message,
  ) {
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
