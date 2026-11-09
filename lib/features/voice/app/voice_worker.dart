import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../engine/voice_engine.dart';

/// One beyt to read: its position in the poem and its hemistichs (one line for prose).
class BeytRequest {
  const BeytRequest(this.index, this.lines);

  final int index;
  final List<String> lines;
}

/// One beyt read aloud: 16-bit mono PCM.
class BeytAudio {
  const BeytAudio(this.index, this.pcm, this.sampleRate);

  final int index;
  final Int16List pcm;
  final int sampleRate;
}

/// `VoiceEngine.load` failed (files missing, incomplete or damaged): reading cannot work until they are fixed.
/// Nothing else raises this; an isolate crash is [VoiceWorkerDied].
class VoiceEngineLoadError implements Exception {
  const VoiceEngineLoadError([this.message = '']);

  final String message;

  @override
  String toString() => 'VoiceEngineLoadError: $message';
}

/// The worker isolate died (out of memory, a crash) or could not start. The voice files are not to blame, so keep them.
class VoiceWorkerDied implements Exception {
  const VoiceWorkerDied([this.message = '']);

  final String message;

  @override
  String toString() => 'VoiceWorkerDied: $message';
}

/// One beyt failed to read; the others are unaffected.
class VoiceReadError implements Exception {
  const VoiceReadError(this.index, [this.message = '']);

  final int index;
  final String message;

  @override
  String toString() => 'VoiceReadError($index): $message';
}

/// Prepares beyts off the UI thread.
abstract interface class VoiceWorker {
  /// Reads [beyts] in order and emits each one as it is ready. A new [read] cancels the running one; cancelling
  /// (by [read], [cancel], or cancelling the subscription) takes effect between beyts and closes the stream without
  /// an error. Errors on the stream are [VoiceEngineLoadError] (then the stream closes) and [VoiceReadError] (that
  /// beyt only; the stream carries on). [steps] sets the flow steps of every beyt (null: phone.json's).
  Stream<BeytAudio> read(List<BeytRequest> beyts, {String? metre, int? steps});

  void cancel();

  Future<void> dispose();
}

/// A [VoiceWorker] on one long-lived background isolate that holds the loaded [VoiceEngine]. The isolate starts on
/// the first [read] and loads the engine on its first request.
class IsolateVoiceWorker implements VoiceWorker {
  /// [threads] defaults to the processor count minus two, between 2 and 6. [sherpaLibDir] is for tests only: the
  /// folder with sherpa-onnx's libraries (the app finds them by itself).
  IsolateVoiceWorker(this.voiceDir, {int? threads, this.sherpaLibDir, this.idle = const Duration(minutes: 3)})
    : threads = threads ?? (Platform.numberOfProcessors - 2).clamp(2, 6);

  final String voiceDir;
  final int threads;
  final String? sherpaLibDir;

  /// How long after the last read ends (with none in flight) the isolate and its engine are released.
  final Duration idle;

  @visibleForTesting
  bool get debugHasIsolate => _isolate != null || _starting != null;

  @visibleForTesting
  int debugSpawns = 0;

  @visibleForTesting
  bool get debugReleasing => _releasing != null;

  Timer? _idleTimer;

  /// The idle release under way; a [read] waits for it, then starts a new isolate.
  Future<void>? _releasing;

  /// A read ended: release the isolate after [idle] unless another starts meanwhile.
  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_current != null || (_isolate == null && _starting == null)) return;
    _idleTimer = Timer(idle, () {
      _idleTimer = null;
      if (_current != null || _releasing != null) return; // a read in flight keeps the engine
      _releasing = _shutDown().whenComplete(() => _releasing = null);
    });
  }

  Isolate? _isolate;
  SendPort? _send;
  Future<void>? _starting;
  ReceivePort? _fromIsolate;
  ReceivePort? _exit;

  int _generation = 0;
  StreamController<BeytAudio>? _current;

  Future<void> _start() async {
    final rx = ReceivePort();
    final exit = ReceivePort();
    _fromIsolate = rx;
    _exit = exit;
    final ready = Completer<SendPort>();
    rx.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is List) {
        _onMessage(m);
      }
    });
    exit.listen((_) {
      // The isolate died under us: the current read cannot finish.
      final c = _current;
      _current = null;
      _isolate = null;
      _send = null;
      _starting = null;
      if (c != null && !c.isClosed) {
        c.addError(const VoiceWorkerDied('the voice worker stopped'));
        c.close();
      }
    });
    debugSpawns++;
    _isolate = await Isolate.spawn(
      _entry,
      _Init(rx.sendPort, voiceDir, threads, sherpaLibDir),
      onExit: exit.sendPort,
      errorsAreFatal: true,
    );
    _send = await ready.future;
  }

  void _onMessage(List m) {
    final gen = m[0] as int;
    final c = _current;
    if (gen != _generation || c == null || c.isClosed) return;
    switch (m[1] as String) {
      case 'audio':
        final pcm = (m[3] as TransferableTypedData).materialize().asInt16List();
        c.add(BeytAudio(m[2] as int, pcm, m[4] as int));
      case 'readError':
        c.addError(VoiceReadError(m[2] as int, m[3] as String));
      case 'loadError':
        c.addError(VoiceEngineLoadError(m[2] as String));
        _finish(c);
      case 'done':
        _finish(c);
    }
  }

  void _finish(StreamController<BeytAudio> c) {
    if (identical(_current, c)) _current = null;
    if (!c.isClosed) c.close();
    _armIdle();
  }

  @override
  Stream<BeytAudio> read(List<BeytRequest> beyts, {String? metre, int? steps}) {
    cancel();
    _idleTimer?.cancel();
    _idleTimer = null;
    final gen = _generation;
    final out = StreamController<BeytAudio>();
    _current = out;
    out.onCancel = () {
      if (identical(_current, out)) cancel();
    };
    () async {
      try {
        final releasing = _releasing;
        if (releasing != null) await releasing; // then start afresh
        if (gen != _generation || out.isClosed) return;
        await (_starting ??= _start());
        if (gen != _generation || out.isClosed) return;
        if (debugDieOnRead) {
          _send!.send(['die']);
          return;
        }
        _send!.send([
          'read',
          gen,
          [
            for (final b in beyts) [b.index, b.lines],
          ],
          metre,
          steps,
        ]);
      } catch (e) {
        _starting = null;
        if (identical(_current, out)) _current = null;
        if (!out.isClosed) {
          out.addError(VoiceWorkerDied('could not start the voice worker: $e'));
          await out.close();
        }
      }
    }();
    return out.stream;
  }

  /// Test only: the next [read] makes the isolate exit instead of reading, to pin how a crash is reported.
  @visibleForTesting
  bool debugDieOnRead = false;

  /// Stops the running read between beyts and closes its stream.
  @override
  void cancel() {
    _generation++;
    final c = _current;
    _current = null;
    _send?.send(['cancel', _generation]);
    if (c != null && !c.isClosed) c.close();
    _armIdle();
  }

  @override
  Future<void> dispose() async {
    cancel();
    _idleTimer?.cancel();
    _idleTimer = null;
    final releasing = _releasing;
    if (releasing != null) await releasing;
    await _shutDown();
  }

  /// Stops the isolate (the engine is disposed inside it). Nothing may be reading. The next [read] starts anew.
  Future<void> _shutDown() async {
    final starting = _starting;
    if (starting != null && _send == null) {
      // Mid-handshake: let it finish, so the new isolate is not leaked.
      try {
        await starting;
      } catch (_) {
        // It failed to start: nothing to stop.
      }
    }
    final iso = _isolate;
    final send = _send;
    // This exit is expected: stop the crash listener first, or it would fail a read that starts meanwhile.
    _exit?.close();
    _exit = null;
    if (iso != null && send != null) {
      final gone = Completer<void>();
      // Wait for the exit on a throwaway port.
      final done = ReceivePort();
      iso.addOnExitListener(done.sendPort);
      done.first.then((_) => gone.complete());
      send.send(['dispose']);
      await gone.future.timeout(const Duration(seconds: 5), onTimeout: () => iso.kill(priority: Isolate.immediate));
      done.close();
    } else {
      iso?.kill(priority: Isolate.immediate);
    }
    _fromIsolate?.close();
    _fromIsolate = null;
    _isolate = null;
    _send = null;
    _starting = null;
  }
}

class _Init {
  const _Init(this.main, this.voiceDir, this.threads, this.sherpaLibDir);

  final SendPort main;
  final String voiceDir;
  final int threads;
  final String? sherpaLibDir;
}

Int16List _toPcm(Float32List s) {
  final out = Int16List(s.length);
  for (var i = 0; i < s.length; i++) {
    out[i] = (s[i] * 32767).round().clamp(-32768, 32767);
  }
  return out;
}

Future<void> _entry(_Init init) async {
  final rx = ReceivePort();
  init.main.send(rx.sendPort);

  VoiceEngine? engine;
  var latest = 0; // the newest generation received, from a request or a cancel

  String? loadFailure;
  VoiceEngine? ensureEngine() {
    if (engine != null) return engine;
    try {
      String? ortPath;
      final lib = init.sherpaLibDir;
      if (lib != null) {
        // Tests only: load sherpa's onnxruntime by full path first, so Windows' older System32 copy does not win.
        ortPath = '$lib${Platform.pathSeparator}${Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'}';
        DynamicLibrary.open(ortPath);
        sherpa.initBindings(lib);
      } else {
        sherpa.initBindings();
      }
      final files = VoiceFiles(init.voiceDir);
      if (!files.complete) {
        final missing = files.all.where((p) => !File(p).existsSync()).join(', ');
        throw StateError('missing voice files: $missing');
      }
      engine = VoiceEngine.load(files, threads: init.threads, onnxruntimePath: ortPath);
      return engine;
    } catch (e) {
      loadFailure = '$e';
      return null;
    }
  }

  Future<void> serve(int gen, List beyts, String? metre, int? steps) async {
    final e = ensureEngine();
    if (e == null) {
      init.main.send([gen, 'loadError', loadFailure ?? 'unknown']);
      return;
    }
    for (final b in beyts) {
      // Let a cancel or a newer request that has arrived be handled before the next (blocking) beyt.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (latest != gen) return;
      var index = -1;
      try {
        index = (b as List)[0] as int;
        final line = e.read(List<String>.from(b[1] as List), metre: metre, steps: steps);
        init.main.send([
          gen,
          'audio',
          index,
          TransferableTypedData.fromList([_toPcm(line.samples)]),
          line.sampleRate,
        ]);
      } catch (err) {
        init.main.send([gen, 'readError', index, '$err']);
      }
    }
    if (latest == gen) init.main.send([gen, 'done']);
  }

  await for (final m in rx) {
    final msg = m as List;
    switch (msg[0] as String) {
      case 'read':
        latest = msg[1] as int;
        unawaited(serve(msg[1] as int, msg[2] as List, msg[3] as String?, msg[4] as int?));
      case 'cancel':
        if ((msg[1] as int) > latest) latest = msg[1] as int;
      case 'die':
        Isolate.exit(); // test only (see debugDieOnRead)
      case 'dispose':
        latest = -1;
        engine?.dispose();
        engine = null;
        rx.close();
    }
  }
}
