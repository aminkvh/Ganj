import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ganj/features/voice/app/voice_downloader.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/app/voice_worker.dart';

/// A [VoiceWorker] for tests: no isolate, no model. Each beyt becomes 0.5 s of a 440 Hz tone at 24 kHz.
///
/// - [delay]: wait this long before each beyt (to make cancellation observable).
/// - [failOn]: the beyt with this `index` (not position) emits [VoiceReadError] instead of audio; the stream
///   carries on with the next beyt, like the real worker.
/// - [failLoad]: the first beyt emits [VoiceEngineLoadError] and the stream closes, like a bad voice folder.
///
/// Like the real worker, a new [read] cancels the running one, and a cancelled stream closes without an error.
class FakeVoiceWorker implements VoiceWorker {
  FakeVoiceWorker({this.delay = Duration.zero, this.failOn, this.failLoad = false});

  final Duration delay;
  final int? failOn;
  final bool failLoad;

  int _generation = 0;
  StreamController<BeytAudio>? _current;
  bool disposed = false;

  /// The `index` of every beyt asked for, across all reads, in order (for assertions).
  final List<int> requested = [];

  /// The flow steps of each [read], in order.
  final List<int?> stepsAsked = [];

  static Int16List tone({int sampleRate = 24000, double seconds = 0.5}) {
    final n = (sampleRate * seconds).round();
    return Int16List.fromList([
      for (var i = 0; i < n; i++) (math.sin(2 * math.pi * 440 * i / sampleRate) * 0.5 * 32767).round(),
    ]);
  }

  @override
  Stream<BeytAudio> read(List<BeytRequest> beyts, {String? metre, int? steps}) {
    cancel();
    stepsAsked.add(steps);
    final mine = _generation;
    final out = StreamController<BeytAudio>();
    _current = out;
    out.onCancel = () {
      if (mine == _generation) _generation++;
    };
    () async {
      if (failLoad) {
        out.addError(const VoiceEngineLoadError('fake load failure'));
      } else {
        for (final b in beyts) {
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          if (mine != _generation || disposed || out.isClosed) break;
          requested.add(b.index);
          if (b.index == failOn) {
            out.addError(VoiceReadError(b.index));
          } else {
            out.add(BeytAudio(b.index, tone(), 24000));
          }
        }
      }
      if (!out.isClosed) await out.close();
    }();
    return out.stream;
  }

  @override
  void cancel() {
    _generation++;
    final c = _current;
    _current = null;
    if (c != null && !c.isClosed) c.close(); // closes at once, like the real worker
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _generation++;
  }
}

/// A [VoiceDownloader] that never reaches a source: every fetch fails as offline. Containers that start readings use
/// it, so the background upgrade check never goes to the network.
class OfflineVoiceDownloader implements VoiceDownloader {
  @override
  Future<VoiceManifest> fetchManifest() async => throw const VoiceDownloadError(VoiceDownloadFailure.offline);

  @override
  Future<String> install(
    VoiceManifest m, {
    required String variant,
    void Function(int got, int total)? onProgress,
    CancelToken? cancel,
  }) async => throw const VoiceDownloadError(VoiceDownloadFailure.offline);

  @override
  Future<String> stage(
    VoiceManifest m, {
    required String variant,
    required Directory from,
    CancelToken? cancel,
  }) async => throw const VoiceDownloadError(VoiceDownloadFailure.offline);

  @override
  bool staged(VoiceManifest m, {required String variant, required Directory from}) => false;

  @override
  int changedBytes(VoiceManifest m, {required String variant, required Directory from}) => 0;

  @override
  Future<void> finishSwap(VoiceManifest m, {required String variant, required Directory from}) async =>
      throw const VoiceDownloadError(VoiceDownloadFailure.checksum);
}
