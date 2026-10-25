import 'dart:async';
import 'app_log.dart' as dev;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'inference_tensor.dart';

/// The scalar a model returned, plus how long the native call itself took.
class InferenceResult {
  /// P(fake) in [0, 1]. Thresholding and confidence mapping stay in
  /// [DeepGuardTFLiteService] so this file has no opinion about policy.
  final double fakeProbability;

  /// Microseconds spent inside `invoke()`, measured on the worker. This is the
  /// pure model cost with no queueing, tensor marshalling or isolate handoff,
  /// which makes it the number to compare against the notebook's latency
  /// figures. Wall-clock latency is measured separately by the caller.
  final int nativeMicros;

  const InferenceResult({
    required this.fakeProbability,
    required this.nativeMicros,
  });
}

/// InferenceIsolate
///
/// A single long-lived background isolate that owns both TFLite interpreters
/// and performs every inference off the platform thread.
///
/// ─── WHY ───────────────────────────────────────────────────────────────────
///
/// `Interpreter.run` / `invoke` is a synchronous FFI call into native TFLite.
/// On the root isolate it blocks the Android platform thread for the entire
/// inference, which is visible in logcat as:
///
///   I/Choreographer: Skipped 58 frames! The application may be doing too
///                    much work on its main thread.
///
/// The project rule is that inference must not run on the UI thread. This is
/// where that is enforced.
///
/// ─── WHY THE INTERPRETERS ARE BUILT HERE RATHER THAN PASSED IN ─────────────
///
/// Two options were on the table and only one is safe:
///
///  * `Interpreter.fromAddress` exists and its own doc comment says it is
///    "typically used for passing interpreter between isolates", but it hands
///    the worker a second Dart handle on ONE native object. Whichever side
///    calls `close()` first leaves the other holding freed memory — a
///    use-after-free in the middle of a model run.
///
///  * So the worker constructs its own interpreters instead, from raw bytes,
///    and owns them outright. `Interpreter.fromAsset` cannot be used here
///    because it goes through `rootBundle`, and plugin/asset channels exist
///    only on the root isolate; the bytes are therefore read on the root
///    isolate by [start] and copied across once, at startup.
///
/// ─── SERIALIZATION ─────────────────────────────────────────────────────────
///
/// The worker handles one job at a time: its message handler runs the native
/// call synchronously, so a second request simply waits on the port. That is
/// the intended queue — TFLite interpreters are not reentrant, and the app
/// only ever analyses one item at a time.
class InferenceIsolate {
  InferenceIsolate._();

  static final InferenceIsolate instance = InferenceIsolate._();

  SendPort? _toWorker;
  Isolate? _worker;
  ReceivePort? _errors;
  ReceivePort? _exit;

  /// How long to wait for the models to load before declaring the worker dead.
  static const Duration _bootTimeout = Duration(seconds: 45);

  /// How long to wait for a single inference. Generous: on a device where the
  /// XNNPACK delegate is refused (see the tensor#137 note in
  /// DeepGuardTFLiteService) the reference kernels are slow but bounded.
  static const Duration _jobTimeout = Duration(minutes: 2);

  bool get isRunning => _toWorker != null;

  /// Spawns the worker and loads both models inside it. Idempotent.
  ///
  /// Throws if either model cannot be loaded, so callers surface a real error
  /// instead of silently producing Authentic verdicts from a dead pipeline.
  Future<void> start({
    required String imageAsset,
    required String videoAsset,
  }) async {
    if (_toWorker != null) return;

    // rootBundle is only available on the root isolate; the worker receives
    // plain bytes. Both copies are transient — sent once, then dropped.
    final Uint8List imageBytes;
    final Uint8List videoBytes;
    try {
      imageBytes = (await rootBundle.load(imageAsset)).buffer.asUint8List();
      videoBytes = (await rootBundle.load(videoAsset)).buffer.asUint8List();
    } catch (e, st) {
      dev.log('[DeepGuard][ISOLATE] model asset read FAILED: $e\n$st',
          name: 'DeepGuard');
      rethrow;
    }

    final handshake = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();

    errors.listen((e) => dev.log('[DeepGuard][ISOLATE] error: $e',
        name: 'DeepGuard'));

    late final Isolate worker;
    try {
      worker = await Isolate.spawn<_Boot>(
        _entry,
        _Boot(
          ready: handshake.sendPort,
          imageBytes: imageBytes,
          videoBytes: videoBytes,
        ),
        errorsAreFatal: false,
        onError: errors.sendPort,
        onExit: exit.sendPort,
      );
    } catch (e) {
      handshake.close();
      errors.close();
      exit.close();
      rethrow;
    }

    Object? ack;
    try {
      ack = await handshake.first.timeout(
        _bootTimeout,
        onTimeout: () => 'timed out after ${_bootTimeout.inSeconds}s',
      );
    } finally {
      // The worker only ever sends the handshake once on this port.
      handshake.close();
    }

    if (ack is! SendPort) {
      worker.kill(priority: Isolate.immediate);
      errors.close();
      exit.close();
      final reason = ack?.toString() ?? 'no handshake';
      dev.log('[DeepGuard][ISOLATE] boot FAILED: $reason', name: 'DeepGuard');
      throw StateError('Inference isolate could not load the models: $reason');
    }

    exit.listen((_) {
      // Only expected after shutdown(); if it happens earlier, the next call
      // will find _toWorker null and start() will rebuild the worker.
      if (_worker == worker) {
        _toWorker = null;
        _worker = null;
      }
    });

    _toWorker = ack;
    _worker = worker;
    _errors = errors;
    _exit = exit;
    dev.log('[DeepGuard][ISOLATE] worker running '
        '(image ${imageBytes.length}B, video ${videoBytes.length}B models '
        'transferred)', name: 'DeepGuard');
  }

  /// Runs the image branch. [input] must be exactly
  /// [InferenceTensors.imageElementCount] float32 values.
  Future<InferenceResult> runImage(Float32List input) =>
      _run(_JobKind.image, input);

  /// Runs the video branch. [input] must be exactly
  /// [InferenceTensors.videoElementCount] float32 values.
  Future<InferenceResult> runVideo(Float32List input) =>
      _run(_JobKind.video, input);

  Future<InferenceResult> _run(_JobKind kind, Float32List input) async {
    final port = _toWorker;
    if (port == null) {
      throw StateError(
          'InferenceIsolate.run${kind.name} called before start(). The '
          'callers in DeepGuardTFLiteService are responsible for starting it.');
    }

    final expected = kind == _JobKind.image
        ? InferenceTensors.imageElementCount
        : InferenceTensors.videoElementCount;
    if (input.length != expected) {
      throw ArgumentError(
          '${kind.name} inference needs $expected float32 values, got '
          '${input.length}');
    }

    final replyPort = ReceivePort();
    final completer = Completer<InferenceResult>();
    replyPort.listen((message) {
      if (message is _Failure) {
        completer.completeError(StateError(message.message));
      } else if (message is InferenceResult) {
        completer.complete(message);
      }
    });

    port.send(_Job(kind: kind, input: input, reply: replyPort.sendPort));

    try {
      return await completer.future.timeout(_jobTimeout, onTimeout: () {
        throw TimeoutException(
            '${kind.name} inference did not finish within '
            '${_jobTimeout.inSeconds}s');
      });
    } finally {
      replyPort.close();
    }
  }

  /// Closes the interpreters inside the worker and releases this instance's
  /// ports. Safe to call when not running.
  Future<void> shutdown() async {
    final port = _toWorker;
    final worker = _worker;
    if (port == null) return;

    final replyPort = ReceivePort();
    final done = Completer<void>();
    replyPort.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    port.send(_Job(
        kind: _JobKind.shutdown, input: Float32List(0), reply: replyPort.sendPort));

    try {
      await done.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      dev.log('[DeepGuard][ISOLATE] shutdown ack lost; killing worker',
          name: 'DeepGuard');
      worker?.kill(priority: Isolate.immediate);
    } finally {
      replyPort.close();
    }

    _toWorker = null;
    _worker = null;
    _errors?.close();
    _exit?.close();
    _errors = null;
    _exit = null;
    dev.log('[DeepGuard][ISOLATE] worker stopped.', name: 'DeepGuard');
  }

  // ── Worker side ────────────────────────────────────────────────────────────

  static void _entry(_Boot boot) {
    final commands = ReceivePort();

    Interpreter? image;
    Interpreter? video;
    try {
      image = Interpreter.fromBuffer(boot.imageBytes,
          options: InterpreterOptions()..threads = 2)
        ..allocateTensors();
      video = Interpreter.fromBuffer(boot.videoBytes,
          options: InterpreterOptions()..threads = 2)
        ..allocateTensors();
    } catch (e, st) {
      image?.close();
      video?.close();
      dev.log('[DeepGuard][ISOLATE] model load FAILED: $e\n$st',
          name: 'DeepGuard');
      boot.ready.send('$e');
      commands.close();
      return;
    }

    boot.ready.send(commands.sendPort);

    commands.listen((message) {
      final job = message as _Job;
      if (job.kind == _JobKind.shutdown) {
        image?.close();
        video?.close();
        image = null;
        video = null;
        job.reply.send(null);
        commands.close();
        return;
      }

      final interpreter =
          job.kind == _JobKind.image ? image : video;
      if (interpreter == null) {
        job.reply.send(_Failure('worker already shut down'));
        return;
      }
      try {
        job.reply.send(_invoke(interpreter, job));
      } catch (e, st) {
        dev.log('[DeepGuard][ISOLATE] ${job.kind} inference FAILED: $e\n$st',
            name: 'DeepGuard');
        job.reply.send(_Failure('$e'));
      }
    });
  }

  /// The single native round trip: copy input, invoke, read output.
  ///
  /// Deliberately NOT `Interpreter.run(nestedList, outputList)`. That overload
  /// feeds the buffer through `ByteConversionUtils.convertObjectToBytes`, which
  /// recognises `Uint8List` and `ByteBuffer` but treats anything else as a
  /// `List` and recurses per element — allocating a fresh 4-byte Uint8List for
  /// every one of the 49,152 (image) or 491,520 (video) floats, and appending
  /// them into a growable `List<int>`. Passing the Float32List's own byte view
  /// hits the early-return branch instead: one memcpy, identical bytes.
  static InferenceResult _invoke(Interpreter interpreter, _Job job) {
    final input = interpreter.getInputTensor(0);
    if (input.type != TensorType.float32) {
      throw StateError(
          'expected a float32 input tensor, model declares ${input.type} '
          '(${input.name})');
    }
    final bytes =
        job.input.buffer.asUint8List(job.input.offsetInBytes, job.input.lengthInBytes);
    final tensorBytes =
        input.shape.fold<int>(1, (a, b) => a * b) * 4;
    if (bytes.length != tensorBytes) {
      throw StateError(
          'input buffer is ${bytes.length}B but the ${job.kind.name} model '
          'wants ${tensorBytes}B (shape ${input.shape})');
    }

    input.setTo(bytes);

    final watch = Stopwatch()..start();
    interpreter.invoke();
    watch.stop();

    final output = interpreter.getOutputTensor(0);
    if (output.type != TensorType.float32) {
      throw StateError(
          'expected a float32 output tensor, model declares ${output.type} '
          '(${output.name})');
    }
    final raw = output.data;
    if (raw.lengthInBytes < 4) {
      throw StateError(
          'output tensor is ${raw.lengthInBytes}B, too small for one float32');
    }
    // The models emit a single sigmoid scalar; anything beyond it is ignored,
    // exactly as the previous nested-list path ignored it.
    final value = ByteData.sublistView(raw).getFloat32(0, Endian.little);

    return InferenceResult(
      fakeProbability: value,
      nativeMicros: watch.elapsedMicroseconds,
    );
  }
}

// ── Message types ────────────────────────────────────────────────────────────
// Plain objects cross isolate ports by deep copy, so these carry no logic and
// stay private to this file. Float32List crosses as a memcpy rather than an
// element-by-element walk, which is why the job payload is typed data and not
// a nested list.

enum _JobKind { image, video, shutdown }

class _Job {
  final _JobKind kind;
  final Float32List input;
  final SendPort reply;

  const _Job({
    required this.kind,
    required this.input,
    required this.reply,
  });
}

class _Boot {
  final SendPort ready;
  final Uint8List imageBytes;
  final Uint8List videoBytes;

  const _Boot({
    required this.ready,
    required this.imageBytes,
    required this.videoBytes,
  });
}

class _Failure {
  final String message;

  const _Failure(this.message);
}
