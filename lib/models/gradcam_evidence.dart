import 'dart:convert';
import 'dart:typed_data';

/// Grad-CAM spatial attribution for one selected video frame out of the 10
/// uniformly sampled frames analyzed by `deepguard_video_gradcam.tflite`.
class VideoFrameGradCam {
  /// 0-based index in the 10-frame sequence (`0..9`).
  final int frameIndex;

  /// Total frames in the model's temporal sequence (`10`).
  final int totalFrames;

  /// Mean unnormalized Grad-CAM activation energy for this frame.
  final double importanceScore;

  /// Normalized `[0.0, 1.0]` Grad-CAM heatmap values in row-major `[height * width]`.
  final List<double> heatmap;

  /// Base64-encoded PNG of the `128x128` analyzed frame for offline/history replay.
  final String? thumbnailPngBase64;

  const VideoFrameGradCam({
    required this.frameIndex,
    required this.totalFrames,
    required this.importanceScore,
    required this.heatmap,
    this.thumbnailPngBase64,
  });

  Uint8List? get thumbnailBytes => thumbnailPngBase64 == null
      ? null
      : base64Decode(thumbnailPngBase64!);

  Map<String, dynamic> toJson() => {
        'frameIndex': frameIndex,
        'totalFrames': totalFrames,
        'importanceScore': importanceScore,
        'heatmapQ': GradCamEvidence.encodeHeatmapBase64(heatmap),
        if (thumbnailPngBase64 != null) 'thumbnailPngBase64': thumbnailPngBase64,
      };

  factory VideoFrameGradCam.fromJson(
    Map<String, dynamic> json, {
    required int width,
    required int height,
  }) {
    final List<double> map;
    if (json['heatmapQ'] is String) {
      map = GradCamEvidence.decodeHeatmapBase64(
        json['heatmapQ'] as String,
        expectedLength: width * height,
      );
    } else if (json['heatmap'] is List) {
      map = (json['heatmap'] as List)
          .map((e) => (e as num).toDouble().clamp(0.0, 1.0))
          .toList(growable: false);
    } else {
      map = const <double>[];
    }

    return VideoFrameGradCam(
      frameIndex: (json['frameIndex'] as num?)?.toInt() ?? 0,
      totalFrames: (json['totalFrames'] as num?)?.toInt() ?? 10,
      importanceScore: (json['importanceScore'] as num?)?.toDouble() ?? 0.0,
      heatmap: map,
      thumbnailPngBase64: json['thumbnailPngBase64'] as String?,
    );
  }
}

/// Real model-prescribed Grad-CAM attribution computed on-device via
/// `tf.GradientTape` on `efficientnetb0/top_activation` through the LSTM,
/// Parallel Fusion, and Neuro-Symbolic Reasoning head.
class GradCamEvidence {
  final int width;
  final int height;

  /// Target class explained by this Grad-CAM (`'A.I.'` or `'REAL'`).
  final String targetLabel;

  /// Convolutional layer inspected (`'efficientnetb0/top_activation'`).
  final String layerName;

  /// Primary image Grad-CAM (`height * width` floats in `[0.0, 1.0]`), or the
  /// top-ranked video frame's heatmap when `topVideoFrames` is populated.
  final List<double> heatmap;

  /// Base64-encoded PNG of the exact `128x128` crop/frame fed to the image model
  /// (null for video or legacy records).
  final String? analyzedCropPngBase64;

  /// Top 3 most influential frames selected from the 10-frame video sequence.
  final List<VideoFrameGradCam> topVideoFrames;

  const GradCamEvidence({
    this.width = 64,
    this.height = 64,
    required this.targetLabel,
    this.layerName = 'efficientnetb0/top_activation',
    required this.heatmap,
    this.analyzedCropPngBase64,
    this.topVideoFrames = const <VideoFrameGradCam>[],
  });

  Uint8List? get analyzedCropBytes => analyzedCropPngBase64 == null
      ? null
      : base64Decode(analyzedCropPngBase64!);

  static String encodeHeatmapBase64(List<double> values) {
    final bytes = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      bytes[i] = (values[i].clamp(0.0, 1.0) * 255.0).round().clamp(0, 255);
    }
    return base64Encode(bytes);
  }

  static List<double> decodeHeatmapBase64(
    String encoded, {
    required int expectedLength,
  }) {
    final bytes = base64Decode(encoded);
    final count = bytes.length < expectedLength ? bytes.length : expectedLength;
    return List<double>.generate(
      count,
      (i) => bytes[i] / 255.0,
      growable: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'targetLabel': targetLabel,
        'layerName': layerName,
        'heatmapQ': encodeHeatmapBase64(heatmap),
        if (analyzedCropPngBase64 != null)
          'analyzedCropPngBase64': analyzedCropPngBase64,
        if (topVideoFrames.isNotEmpty)
          'topVideoFrames':
              topVideoFrames.map((f) => f.toJson()).toList(growable: false),
      };

  factory GradCamEvidence.fromJson(Map<String, dynamic> json) {
    final w = (json['width'] as num?)?.toInt() ?? 64;
    final h = (json['height'] as num?)?.toInt() ?? 64;
    final List<double> map;
    if (json['heatmapQ'] is String) {
      map = decodeHeatmapBase64(
        json['heatmapQ'] as String,
        expectedLength: w * h,
      );
    } else if (json['heatmap'] is List) {
      map = (json['heatmap'] as List)
          .map((e) => (e as num).toDouble().clamp(0.0, 1.0))
          .toList(growable: false);
    } else {
      map = const <double>[];
    }

    final framesRaw = json['topVideoFrames'];
    final frames = <VideoFrameGradCam>[];
    if (framesRaw is List) {
      for (final item in framesRaw) {
        if (item is Map<String, dynamic>) {
          frames.add(VideoFrameGradCam.fromJson(item, width: w, height: h));
        } else if (item is Map) {
          frames.add(
            VideoFrameGradCam.fromJson(
              Map<String, dynamic>.from(item),
              width: w,
              height: h,
            ),
          );
        }
      }
    }

    return GradCamEvidence(
      width: w,
      height: h,
      targetLabel: json['targetLabel']?.toString() ?? 'A.I.',
      layerName: json['layerName']?.toString() ?? 'efficientnetb0/top_activation',
      heatmap: map,
      analyzedCropPngBase64: json['analyzedCropPngBase64'] as String?,
      topVideoFrames: frames,
    );
  }
}
