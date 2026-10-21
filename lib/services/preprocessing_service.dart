import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

/// DeepGuard Preprocessing Service
///
/// Handles media validation and temp-file management before inference.
///
/// ─── ACTUAL PREPROCESSING PIPELINE ────────────────────────────────────────
///
/// The full preprocessing pipeline (resize + tensor build) lives in
/// [DeepGuardTFLiteService], matching the training notebook exactly:
///
///   IMAGE (notebook Cell 18):
///     img.decodeImage(bytes)         — auto-applies EXIF orientation
///     img.copyResize(128×128, avg)   — ≡ tf.image.resize / cv2.INTER_AREA
///     _buildImageTensor              — float32, range [0,255], shape [1,128,128,3]
///     TFLite run                     — EfficientNetB0 rescales internally
///
///   VIDEO (notebook Cell 20):
///     VideoThumbnail.thumbnailData() — 10 uniformly-spaced timestamps, q=100
///     img.decodeImage(jpegBytes)     — decode each JPEG frame
///     img.copyResize(128×128, avg)   — ≡ cv2.INTER_AREA inside _buildVideoTensor
///     _buildVideoTensor              — float32, range [0,255], shape [1,10,128,128,3]
///     TFLite run
///
/// Camera-captured and gallery-selected files follow the EXACT SAME pipeline.
/// imageQuality is NOT applied during camera capture (removed from ImagePicker
/// call in upload_screen.dart) to prevent JPEG re-compression artefacts.
///
/// ⚠️  NORMALIZATION:
///   The TFLite models embed EfficientNetB0 which contains its own internal
///   Rescaling(1/255) layer. Pixel values are passed as raw [0.0, 255.0]
///   float32 — dividing by 255.0 before inference would collapse all
///   predictions to ~0 (Authentic).
class PreprocessingService {
  static final PreprocessingService _instance = PreprocessingService._internal();
  factory PreprocessingService() => _instance;
  PreprocessingService._internal();

  // Matching the trained model input specification
  static const int targetWidth  = 128;
  static const int targetHeight = 128;
  // Must match DeepGuardTFLiteService.videoFrames (10).
  static const int videoNumFrames = 10;

  // Allowed extensions (mirrors training dataset + Django settings)
  static const List<String> allowedImageExtensions = [
    'jpg', 'jpeg', 'png', 'bmp', 'webp',
  ];
  static const List<String> allowedVideoExtensions = [
    'mp4', 'avi', 'mov', 'mkv', 'webm',
  ];

  /// Returns true if [filePath] has a supported image or video extension.
  bool isValidMedia(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return allowedImageExtensions.contains(ext) ||
        allowedVideoExtensions.contains(ext);
  }

  /// Returns 'image', 'video', or 'unknown' based on [filePath] extension.
  String getMediaType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    if (allowedImageExtensions.contains(ext)) return 'image';
    if (allowedVideoExtensions.contains(ext)) return 'video';
    return 'unknown';
  }

  /// Returns true if [bytes] is within the 100 MB hard limit.
  bool isValidFileSize(int bytes) => bytes <= 100 * 1024 * 1024;

  /// Returns (or creates) a temporary working directory for DeepGuard files.
  Future<Directory> getTempDirectory() async {
    final base = await getTemporaryDirectory();
    final dir  = Directory('${base.path}/deepguard_processing');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Generates a unique processing ID string for each analysis request.
  String generateProcessingId() {
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'DG-$ts-$rnd';
  }
}
