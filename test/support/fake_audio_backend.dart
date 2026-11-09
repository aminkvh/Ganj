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

  /// Holds load() until this completes, to test the loading state.
  Future<void>? beforeLoad;

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

  // Playlist mode: a global timeline over per-item durations, like the real backend.
  PlaylistTimeline? timeline;
  final playlists = <List<PlaylistItem>>[];
  final appended = <PlaylistItem>[];

  /// How many appends asked to resume.
  int resumed = 0;

  /// Holds appendItem() until this completes, to test an append in flight.
  Future<void>? beforeAppend;
  final itemSeeks = <({int index, Duration offset})>[];
  final _item = StreamController<int?>.broadcast();

  @override
  bool get supportsPlaylist => playlistSupported;

  /// Set false to mimic a platform without playlists.
  bool playlistSupported = true;

  @override
  Stream<int?> get currentItem => _item.stream;

  @override
  Future<void> loadPlaylist(List<PlaylistItem> items, {required MediaInfo info}) async {
    await beforeLoad;
    if (failLoad != null) throw failLoad!;
    playlists.add(items);
    infos.add(info);
    timeline = PlaylistTimeline(items.map((i) => i.duration));
    _duration.add(timeline!.total);
  }

  @override
  Future<void> appendItem(PlaylistItem item, {bool resume = false}) async {
    if (resume) resumed++;
    await beforeAppend;
    appended.add(item);
    timeline!.add(item.duration);
    _duration.add(timeline!.total);
  }

  /// The playlist plays [offset] into item [index]: emits the item and the global position.
  void emitItemPosition(int index, Duration offset) {
    _item.add(index);
    _pos.add(timeline!.global(index, offset));
  }

  /// Item [index] ends; the backend reports completion only for the last one.
  void emitItemCompleted(int index) {
    if (index == timeline!.length - 1) _completed.add(true);
  }

  @override
  Future<Duration?> load(Uri uri, {required MediaInfo info}) async {
    timeline = null;
    await beforeLoad;
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
    final t = timeline;
    if (t != null) {
      final at = t.locate(d);
      itemSeeks.add(at);
      _item.add(at.index);
    }
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
