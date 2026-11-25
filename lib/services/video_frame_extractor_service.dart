import 'app_log.dart' as dev;
import 'dart:async';
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
class VideoFrameExtractorService {
  static const int requiredFrames = DeepGuardTFLiteService.videoFrames; // 10
  static const int _inferenceThumbSize = 512;

  static const List<int> _durationProbes = [
    500, 1000, 2000, 3000, 5000,
    8000, 12000, 20000, 30000, 60000,
    90000, 120000, 180000, 240000, 300000,
  ];

  /// Extracts [requiredFrames] decoded images from [videoPath].
  ///
  /// Optional callbacks report actual stage completion and measurable frame
  /// counts to the UI without modifying any frame data or model inputs.
  Future<List<img.Image>> extractFrames(
    String videoPath, {
    FutureOr<void> Function()? onDecodingStarted,
    FutureOr<void> Function(int extractedCount, int totalFrames)?
        onFrameExtracted,
    FutureOr<void> Function()? onFilteringStarted,
  }) async {
    dev.log('[VideoFrameExtractor] Starting extraction: $videoPath',
        name: 'DeepGuard');

    await onDecodingStarted?.call();

    // Step 1 – estimate video duration
    final durationMs = await _estimateDurationMs(videoPath);
    dev.log('[VideoFrameExtractor] Estimated duration: ${durationMs}ms',
        name: 'DeepGuard');

    // Step 2 – compute 10 evenly-spaced timestamps
    final timestamps = _uniformTimestamps(durationMs, requiredFrames);
    dev.log('[VideoFrameExtractor] Timestamps: $timestamps', name: 'DeepGuard');

    // Step 3 – extract raw JPEG bytes for each timestamp
    final rawFrames = await _fetchFrameBytes(
      videoPath,
      timestamps,
      onFrameExtracted: onFrameExtracted,
    );

    await onFilteringStarted?.call();

    // Step 4 – decode JPEG bytes → img.Image
    final decoded = _decodeFrames(rawFrames, timestamps);

    if (decoded.every((f) => f == null)) {
      throw VideoFrameExtractionException(
        'Could not decode any frames from: $videoPath',
      );
    }

    // Step 5 – pad to exactly requiredFrames (repeat last valid frame)
    final padded = _padFrames(decoded, requiredFrames);
    if (padded.isEmpty) {
      throw VideoFrameExtractionException(
        'Insufficient readable frames in video: $videoPath',
      );
    }

    dev.log(
      '[VideoFrameExtractor] Done | '
      'decoded=${decoded.whereType<img.Image>().length}  padded=${padded.length}',
      name: 'DeepGuard',
    );

    return padded;
  }

  Future<int> _estimateDurationMs(String videoPath) async {
    int lastSuccessfulMs = 0;

    for (final probeMs in _durationProbes) {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 64,
          timeMs: probeMs,
          quality: 10,
        );
        if (bytes != null && bytes.isNotEmpty) {
          lastSuccessfulMs = probeMs;
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }

    if (lastSuccessfulMs == 0) {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 64,
          timeMs: 0,
          quality: 10,
        );
        if (bytes != null && bytes.isNotEmpty) {
          lastSuccessfulMs = 100;
        }
      } catch (_) {}
    }

    return (lastSuccessfulMs * 1.1).round().clamp(100, 600000);
  }

  List<int> _uniformTimestamps(int durationMs, int count) {
    if (count == 1) return [0];
    final step = durationMs / (count - 1);
    return List.generate(count, (i) => (i * step).round());
  }

  Future<List<Uint8List?>> _fetchFrameBytes(
    String videoPath,
    List<int> timestamps, {
    FutureOr<void> Function(int extractedCount, int totalFrames)?
        onFrameExtracted,
  }) async {
    final results = <Uint8List?>[];
    final total = timestamps.length;

    for (int i = 0; i < total; i++) {
      Uint8List? bytes;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          maxWidth: _inferenceThumbSize,
          maxHeight: _inferenceThumbSize,
          timeMs: timestamps[i],
          quality: 100,
        );
      } catch (e) {
        dev.log('[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms FAILED: $e',
            name: 'DeepGuard');
      }

      if (bytes != null && bytes.isNotEmpty) {
        dev.log(
          '[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms OK '
          '(${bytes.length} bytes, thumbSize=${_inferenceThumbSize}px, q=100)',
          name: 'DeepGuard',
        );
      } else {
        dev.log('[VideoFrameExtractor] Frame $i at ${timestamps[i]}ms EMPTY',
            name: 'DeepGuard');
      }

      results.add(bytes);
      await onFrameExtracted?.call(i + 1, total);
    }

    return results;
  }

  List<img.Image?> _decodeFrames(
      List<Uint8List?> rawFrames, List<int> timestamps) {
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

  List<img.Image> _padFrames(List<img.Image?> decoded, int required) {
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
    }

    if (filled.isEmpty) {
      return [];
    }

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
