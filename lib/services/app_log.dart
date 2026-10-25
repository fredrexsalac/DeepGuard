/// Device-visible application logging.
///
/// ─── WHY THIS EXISTS ───────────────────────────────────────────────────────
///
/// Every diagnostic in this project was written with `dart:developer`'s
/// `log()`. That function publishes to the Dart VM service, which is what
/// `flutter run` and DevTools read. It does NOT write to Android's log buffer,
/// so a message sent that way is invisible to `adb logcat`.
///
/// That was observed, not assumed. In a debug session on the Infinix X6885 the
/// native TFLite runtime logged its own startup
///
///   I tflite  : Created TensorFlow Lite XNNPACK delegate for CPU.
///   W tflite  : Attempting to use a delegate that only supports static-sized
///               tensors with a graph that has dynamic-sized tensors
///               (tensor#137 is a dynamic-sized tensor).
///
/// proving inference had definitely run, while the same buffer contained zero
/// `I flutter :` lines — i.e. none of the app's own 15-field inference
/// diagnostics, nor the face-crop decisions, nor the isolate boot message.
///
/// For a thesis whose evidence is captured from the device, a diagnostic that
/// only appears when a developer happens to be attached over the VM service is
/// a diagnostic that does not exist. `print`/`debugPrint` output, by contrast,
/// is forwarded by the engine to logcat under the `flutter` tag.
///
/// ─── DESIGN ────────────────────────────────────────────────────────────────
///
/// This file declares a `log` with the same call signature the codebase
/// already used, so the nine service files changed one line each — their
/// `import 'dart:developer' as dev;` — and none of their ~58 call sites.
///
/// Both sinks are kept deliberately: logcat for capture-on-device evidence,
/// the VM service for structured inspection in DevTools.
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Writes [message] to logcat and to the Dart VM service.
///
/// [name] prefixes the VM-service record and the logcat line so a filtered
/// capture (`adb logcat -s flutter`) still shows which subsystem spoke.
///
/// [error] and [stackTrace] mirror `dart:developer`'s parameters. They are
/// appended to the logcat copy because logcat has no structured error field.
void log(
  Object? message, {
  String name = 'DeepGuard',
  DateTime? time,
  Object? error,
  StackTrace? stackTrace,
}) {
  final text = '$message';
  developer.log(
    text,
    name: name,
    time: time ?? DateTime.now(),
    error: error,
    stackTrace: stackTrace,
  );

  // debugPrint rather than print: `print` trips the avoid_print lint that
  // analysis_options.yaml inherits from flutter_lints, and debugPrint is
  // already the framework's sanctioned logging entry point. Its throttling
  // queues chunks in order, so a multi-line diagnostic block still reads
  // top-to-bottom in logcat.
  final suffix = StringBuffer();
  if (error != null) suffix.write(' | error: $error');
  if (stackTrace != null) suffix.write('\n$stackTrace');
  debugPrint('[$name] $text$suffix');
}
