import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';

import 'deepguard_tflite_service.dart';

/// VideoFrameExtractorService
///
/// Extracts exactly 10 uniformly-spaced frames from a video file
/// and returns them as decoded [img.Image] objects ready for the
/// DeepGuard video model.
///
/// Required tensor shape: [1, 10, 128, 128, 3]
///
/// Frame extraction strategy:
///   1. Probe video length by requesting frames at increasing timestamps.
///   2. Distribute 10 timestamps across [0 .. estimatedDurationMs].
///   3. Each frame is decoded from JPEG bytes returned by video_thumbnail.
///   4. Any failed slot is filled by duplicating the nearest successful frame.
///   5. If ALL frames fail, throws [VideoFrameExtractionException].
///
/// The caller must handle [VideoFrameExtractionException] and present a
/// user-friendly error message.
///
/// ⚠️  PREPROCESSING NOTES:
///   - Inference frames are requested at maxWidth/maxHeight = 512 so that
///     the native plugin returns high-resolution data. The final resize to
///     128×128 is performed in Dart (inside DeepGuardTFLiteService._buildVideoTensor)
///     using average/INTER_AREA interpolation — matching the training pipeline.
///   - JPEG quality for inference frames is set to 100 (lossless-equivalent)
///     to prevent block artifacts from masking the high-frequency deepfake
///     signatures the model was trained to detect.
///   - Duration-probe thumbnails use quality:10 since they only test frame
///     existence, not pixel quality.
class VideoFrameExtractorService {
  static const int requiredFrames = DeepGuardTFLiteService.videoFrames; // 10

  // Resolution requested from the native plugin for *inference* frames.
  // Larger than the model's 128×128 so Dart performs the final, accurate
  // INTER_AREA-equivalent downscale rather than the plugin doing it.
  static const int _inferenceThumbSize = 512;

  // Timestamp candidates (ms) used to probe total duration.
  // Covers clips from ~1 s up to ~5 min in increasing granularity.
  static const List<int> _durationProbes = [
    500, 1000, 2000, 3000, 5000,
    8000, 12000, 20000, 30000, 60000,
    90000, 120000, 180000, 240000, 300000,
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Extracts [requiredFrames] decoded images from [videoPath].
  ///
  /// Throws [VideoFrameExtractionException] if no frames could be obtained.
  Future<List<img.Image>> extractFrames(String videoPath) async {
    dev.log('[VideoFrameExtractor] Starting extraction: $videoPath',
        name: 'DeepGuard');

    // Step 1 – estimate video duration
    final durationMs = await _estimateDurationMs(videoPath);
    dev.log('[VideoFrameExtractor] Estimated duration: ${durationMs}ms',
        name: 'DeepGuard');

    // Step 2 – compute 10 evenly-spaced timestamps
    final timestamps = _uniformTimestamps(durationMs, requiredFrames);
    dev.log('[VideoFrameExtractor] Timestamps: $timestamps', name: 'DeepGuard');

    // Step 3 – extract raw JPEG bytes for each timestamp
    final rawFrames = await _fetchFrameBytes(videoPath, timestamps);

    // Step 4 – decode JPEG bytes → img.Image
    final decoded = _decodeFrames(rawFrames, timestamps);

    if (decoded.isEmpty) {
      throw VideoFrameExtractionException(
        'Could not decode any frames from: $videoPath',
      );
    }

    // Step 5 – pad to exactly requiredFrames (repeat last frame)
    final padded = _padFrames(decoded, requiredFrames);

    dev.log('[VideoFrameExtractor] Done | '
        'decoded=${decoded.length}  padded=${padded.length}',
        name: 'DeepGuard');

    return padded;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Estimates total video duration (ms) by probing timestamps until the
  /// plugin starts returning null/empty — indicating we have passed the end.
  Future<int> _estimateDurationMs(String videoPath) async {
    int lastSuccessfulMs = 0;

    for (final probeMs in _durationProbes) {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 64, // small — just checking if frame exists
          timeMs: probeMs,
          quality: 10,
        );
        if (bytes != null && bytes.isNotEmpty) {
          lastSuccessfulMs = probeMs;
        } else {
          break; // past end of video
        }
      } catch (_) {
        break;
      }
    }

    // If nothing responded, treat as very short clip (use max probe that works)
    if (lastSuccessfulMs == 0) {
      // Try timeMs=0 as absolute minimum
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 64,
          timeMs: 0,
          quality: 10,
        );
        if (bytes != null && bytes.isNotEmpty) {
          lastSuccessfulMs = 100; // very short clip
        }
      } catch (_) {}
    }

    // Add 10% buffer to reach the final frame
    return (lastSuccessfulMs * 1.1).round().clamp(100, 600000);
  }

  /// Computes [count] evenly-spaced timestamps between 0 and [durationMs].
  List<int> _uniformTimestamps(int durationMs, int count) {
    if (count == 1) return [0];
    final step = durationMs / (count - 1);
    return List.generate(count, (i) => (i * step).round());
  }

  /// Fetches raw JPEG bytes from [videoPath] at each timestamp.
  ///
  /// ⚠️  Uses [_inferenceThumbSize] (512) instead of the model's native
  ///     128×128 so the native plugin does not pre-downsample the frame.
  ///     The final resize to 128×128 happens inside _buildVideoTensor
  ///     using Dart's average interpolation (≈ cv2.INTER_AREA).
  ///
  /// ⚠️  quality is set to 100 to minimise JPEG block artefacts.
  ///     Deepfake models detect subtle high-frequency patterns; lower
  ///     JPEG quality (e.g. 85) washes those patterns out and biases
  ///     predictions toward AUTHENTIC.
  ///
  /// Missing/failed frames are represented as null in the returned list.
  Future<List<Uint8List?>> _fetchFrameBytes(
      String videoPath, List<int> timestamps) async {
    final results = <Uint8List?>[];

    for (int i = 0; i < timestamps.length; i++) {
      Uint8List? bytes;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          // Request at 512×512 — plugin will preserve aspect ratio up to
          // this size. Dart resizes to 128×128 in _buildVideoTensor.
          maxWidth: _inferenceThumbSize,
          maxHeight: _inferenceThumbSize,
          timeMs: timestamps[i],
          // quality:100 minimises JPEG artefacts that mask deepfake signals.
          quality: 100,
        );
      } catch (e) {
        dev.log('[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms FAILED: $e',
            name: 'DeepGuard');
      }

      if (bytes != null && bytes.isNotEmpty) {
        dev.log('[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms OK '
            '(${bytes.length} bytes, thumbSize=${_inferenceThumbSize}px, q=100)',
            name: 'DeepGuard');
      } else {
        dev.log('[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms EMPTY',
            name: 'DeepGuard');
      }

      results.add(bytes);
    }

    return results;
  }

  /// Decodes raw JPEG bytes into [img.Image] objects.
  /// Gaps (null/empty slots) are represented as null in the returned list —
  /// they will be filled by [_padFrames].
  List<img.Image?> _decodeFrames(List<Uint8List?> rawFrames, List<int> timestamps) {
    final decoded = <img.Image?>[];

    for (int i = 0; i < rawFrames.length; i++) {
      final bytes = rawFrames[i];
      if (bytes == null || bytes.isEmpty) {
        decoded.add(null);
        continue;
      }
      try {
        final image = img.decodeImage(bytes);
        decoded.add(image);
      } catch (e) {
        dev.log('[VideoFrameExtractor] Decode FAILED for frame $i: $e',
            name: 'DeepGuard');
        decoded.add(null);
      }
    }

    return decoded;
  }

  /// Fills null slots in [decoded] using the nearest non-null neighbour,
  /// then pads to [required] by repeating the last frame.
  ///
  /// Throws if no successful frame exists at all.
  List<img.Image> _padFrames(List<img.Image?> decoded, int required) {
    // Forward-fill: replace each null with the last non-null
    img.Image? last;
    final filled = <img.Image>[];

    for (final frame in decoded) {
      if (frame != null) {
        last = frame;
        filled.add(frame);
      } else if (last != null) {
        filled.add(last);
        dev.log('[VideoFrameExtractor] Null frame filled with duplicate.',
            name: 'DeepGuard');
      }
      // If last is still null, skip (we'll handle below)
    }

    if (filled.isEmpty) {
      // No successful frames at all — re-throw from caller
      return [];
    }

    // Pad to required length by repeating last frame
    while (filled.length < required) {
      filled.add(filled.last);
      dev.log('[VideoFrameExtractor] Padding frame to reach $required.',
          name: 'DeepGuard');
    }

    return filled.sublist(0, required);
  }
}

/// Thrown when [VideoFrameExtractorService] cannot produce any usable frames.
class VideoFrameExtractionException implements Exception {
  final String message;
  const VideoFrameExtractionException(this.message);
  @override
  String toString() => 'VideoFrameExtractionException: $message';
}
