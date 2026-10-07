import 'dart:async';

import 'package:ganj/features/player/audio_backend.dart';

/// Scriptable audio backend: tests push positions and inspect calls.
class FakeAudioBackend implements AudioBackend {
  final loaded = <Uri>[];
  final seeks = <Duration>[];
  final infos = <MediaInfo>[];
  bool isPlaying = false;
  double speed = 1;
  Object? failLoad;

  /// Mimic just_audio_windows: duration arrives on the stream during load, load() returns null.
  bool durationOnlyViaStream = false;
  final _pos = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  void emitError(Object e) => _errors.add(e);

  void emitDuration(Duration? d) => _duration.add(d);

  void emitPosition(Duration d) => _pos.add(d);

  void emitCompleted() => _completed.add(true);

  @override
  Future<Duration?> load(Uri uri, {required MediaInfo info}) async {
    if (failLoad != null) throw failLoad!;
    loaded.add(uri);
    infos.add(info);
    if (durationOnlyViaStream) {
      _duration.add(const Duration(minutes: 1, seconds: 37));
      await Future<void>.delayed(Duration.zero);
      return null;
    }
    return const Duration(minutes: 2);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration d) async {
    seeks.add(d);
    _pos.add(d);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> setSpeed(double s) async => speed = s;

  @override
  Stream<Duration> get position => _pos.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Duration?> get duration => _duration.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> dispose() async {}
}
