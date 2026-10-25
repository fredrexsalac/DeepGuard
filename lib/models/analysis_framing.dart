/// AnalysisFraming
///
/// Records WHAT the image classifier was actually shown: the decoded frame
/// size, the face ML Kit located, and the square that was cropped and resized
/// to the model's 128x128 input.
///
/// WHY THIS EXISTS
/// The deployed model is a whole-square classifier — it receives one 128x128
/// crop and emits one probability, and has no localization of any kind. Two
/// results that look identical in the UI ("AUTHENTIC 99.4%") can arrive from a
/// tight face crop or from an entire 2160x3840 frame in which the subject was a
/// few pixels wide, and those have very different reliability. Observed on a
/// real Infinix X6885 on 2026-10-24: three consecutive camera captures scored
/// 0.7326, 0.0231 and 0.0058, and the difference between them is visible in
/// this record — FACE CROP with 1 face, FACE CROP with 2 faces, and WHOLE FRAME
/// with 0 faces. Until this class existed that distinction was readable only
/// from `adb logcat`.
///
/// WHAT THIS IS NOT
/// Not evidence of manipulation and not a region of interest. The face box is a
/// FRAMING locator: it records where a face was found so the analysed square
/// could be centred on it. Nothing in the pipeline scores a sub-region, so no
/// consumer may render any part of this as "where the manipulation was
/// detected". That constraint is restated in the widget that paints it.
class BoxRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const BoxRect(this.left, this.top, this.width, this.height);

  int get right => left + width;
  int get bottom => top + height;

  bool get isValid => width > 0 && height > 0;

  @override
  String toString() => '[$left,$top ${width}x$height]';

  Map<String, dynamic> toJson() => {
        'l': left,
        't': top,
        'w': width,
        'h': height,
      };

  factory BoxRect.fromJson(Map<dynamic, dynamic> json) => BoxRect(
        (json['l'] as num?)?.toInt() ?? 0,
        (json['t'] as num?)?.toInt() ?? 0,
        (json['w'] as num?)?.toInt() ?? 0,
        (json['h'] as num?)?.toInt() ?? 0,
      );
}

/// The framing a single image analysis actually ran on.
class AnalysisFraming {
  /// Decoded frame size, AFTER EXIF rotation, i.e. the coordinate space every
  /// rect in this record is expressed in.
  final int frameWidth;
  final int frameHeight;

  /// How many faces the detector reported, including the zero case — the
  /// difference between "1 face" and "0 faces" is the whole diagnostic.
  final int faceCount;

  /// The largest detected face, or null when none was usable.
  final BoxRect? faceRect;

  /// The square that was fed to the model, or null when the whole frame was.
  final BoxRect? analysedRect;

  /// Why the crop was or was not applied. Shown verbatim when no crop happened,
  /// so it must stay a plain technical phrase and never a verdict.
  final String note;

  const AnalysisFraming({
    required this.frameWidth,
    required this.frameHeight,
    required this.faceCount,
    this.faceRect,
    this.analysedRect,
    this.note = '',
  });

  bool get cropApplied => analysedRect != null && analysedRect!.isValid;
  bool get faceFound => faceRect != null && faceRect!.isValid;

  /// The region the model saw — the crop when there was one, otherwise the
  /// entire frame. There is always an answer; that is the point of the record.
  BoxRect get analysedBox =>
      cropApplied ? analysedRect! : BoxRect(0, 0, frameWidth, frameHeight);

  /// Fraction of the frame that reached the model. Low coverage with no crop is
  /// the signature of a wide shot in which the subject is a few pixels across.
  double get coveragePercent {
    final area = frameWidth * frameHeight;
    if (area <= 0) return 0;
    final b = analysedBox;
    return (b.width * b.height) / area * 100.0;
  }

  /// One-line technical summary, matching the format already written to logcat
  /// so a screenshot and a log line can be compared directly.
  String get summary {
    final crop = cropApplied ? 'FACE CROP $analysedRect' : 'WHOLE FRAME';
    return '$crop of ${frameWidth}x$frameHeight  faces=$faceCount';
  }

  Map<String, dynamic> toJson() => {
        'fw': frameWidth,
        'fh': frameHeight,
        'fc': faceCount,
        'face': faceRect?.toJson(),
        'crop': analysedRect?.toJson(),
        'note': note,
      };

  /// Legacy history records were saved before this existed and carry no
  /// framing at all, so a missing key yields null rather than a guess. The
  /// caller must not draw a box it has no data for.
  factory AnalysisFraming.fromJson(Map<dynamic, dynamic> json) =>
      AnalysisFraming(
        frameWidth: (json['fw'] as num?)?.toInt() ?? 0,
        frameHeight: (json['fh'] as num?)?.toInt() ?? 0,
        faceCount: (json['fc'] as num?)?.toInt() ?? 0,
        faceRect: json['face'] is Map
            ? BoxRect.fromJson(json['face'] as Map)
            : null,
        analysedRect: json['crop'] is Map
            ? BoxRect.fromJson(json['crop'] as Map)
            : null,
        note: json['note'] as String? ?? '',
      );
}
