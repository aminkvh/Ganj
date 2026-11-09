import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// What the OS media controls show for the current track.
class MediaInfo {
  const MediaInfo({required this.id, required this.title, required this.artist, this.artUri, this.live = false});

  final String id;
  final String title;
  final String artist;
  final Uri? artUri;

  /// A playlist that is still growing (the voice streaming beyt by beyt): the OS controls show
  /// no duration and offer no seek.
  final bool live;
}

/// One entry of a playlist (one beyt of the machine reading) with its known length.
class PlaylistItem {
  const PlaylistItem({required this.uri, required this.duration});

  final Uri uri;
  final Duration duration;
}

/// Maps between the global timeline of a playlist and (item, offset-in-item) pairs.
class PlaylistTimeline {
  PlaylistTimeline(Iterable<Duration> durations) : _durations = [...durations];

  final List<Duration> _durations;

  int get length => _durations.length;

  Duration get total => _durations.fold(Duration.zero, (a, b) => a + b);

  Duration get lastDuration => _durations.isEmpty ? Duration.zero : _durations.last;

  void add(Duration d) => _durations.add(d);

  /// Global position of [offset] into item [index].
  Duration global(int index, Duration offset) {
    var sum = Duration.zero;
    for (var i = 0; i < index && i < _durations.length; i++) {
      sum += _durations[i];
    }
    return sum + offset;
  }

  /// The item and offset at global position [g], clamped to the playlist's ends.
  ({int index, Duration offset}) locate(Duration g) {
    if (_durations.isEmpty) return (index: 0, offset: Duration.zero);
    if (g <= Duration.zero) return (index: 0, offset: Duration.zero);
    var start = Duration.zero;
    for (var i = 0; i < _durations.length; i++) {
      final end = start + _durations[i];
      if (g < end) return (index: i, offset: g - start);
      start = end;
    }
    final last = _durations.length - 1;
    return (index: last, offset: _durations[last]);
  }
}

const kSeekCompletionWindow = Duration(milliseconds: 250);

/// Whether a `completed` processing state counts as the playlist's real end.
/// [sinceSeek] is the time since the last playlist seek (null when none). Platforms blip
/// `completed` right after a seek that jumps to another item, so that window is ignored;
/// position is not consulted, since some platforms report 0 at the end.
bool playlistCompletionCounts({
  required int index,
  required int length,
  Duration? sinceSeek,
  Duration window = kSeekCompletionWindow,
}) => index == length - 1 && (sinceSeek == null || sinceSeek >= window);

/// After a playlist seek, holds back position events until the player reports the target item
/// near the target offset (platforms emit stale item/offset pairs for a few ms), or until
/// [timeout] passes so a missed event can't freeze the position.
class PlaylistSeekGate {
  PlaylistSeekGate({
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 1),
    this.tolerance = const Duration(milliseconds: 300),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration timeout;
  final Duration tolerance;
  ({int index, Duration offset})? _target;
  DateTime? _since;

  void seek(({int index, Duration offset}) target) {
    _target = target;
    _since = _now();
    _released = false;
  }

  void clear() {
    _target = null;
    _since = null;
  }

  /// Time since the last seek, or null when none happened.
  Duration? get sinceSeek => _since == null ? null : _now().difference(_since!);

  bool _released = false;

  /// True when an event for [index] / in-item [offset] may pass. Until the player reports the
  /// target it is held back; for the rest of [timeout] it must also not fall behind the target
  /// (platforms repeat the stale pair a moment after the first good one).
  bool admit(int index, Duration offset) {
    final t = _target;
    if (t == null) return true;
    if (_now().difference(_since!) >= timeout) {
      _target = null;
      return true;
    }
    final behind = index < t.index || (index == t.index && offset < t.offset - tolerance);
    if (!_released) {
      final near = index == t.index && (offset - t.offset).abs() <= tolerance;
      if (!near) return false;
      _released = true;
      return true;
    }
    return !behind;
  }
}

/// Playback seam: the app talks to this, tests use a fake.
abstract class AudioBackend {
  /// True when [loadPlaylist] / [appendItem] work on this platform.
  bool get supportsPlaylist;

  /// Loads one item per entry as a single global timeline: [position], [duration] and [seek]
  /// span all items (the backend maps between global and per-item positions), and [completed]
  /// fires only after the last item ends. Loading a playlist replaces whatever was loaded.
  Future<void> loadPlaylist(List<PlaylistItem> items, {required MediaInfo info});

  /// Adds [item] after the last one. The total [duration] grows. With [resume], a playlist that
  /// had already completed starts playing the new item; without it, this never calls play().
  Future<void> appendItem(PlaylistItem item, {bool resume = false});

  /// Index of the playing item in playlist mode (null otherwise).
  Stream<int?> get currentItem;

  Future<Duration?> load(Uri uri, {required MediaInfo info});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> stop();
  Future<void> setSpeed(double s);
  Stream<Duration> get position;
  Stream<bool> get playing;
  Stream<bool> get completed;

  /// Some platforms (Windows) learn the duration only after loading.
  Stream<Duration?> get duration;

  /// Errors that happen after loading (dropped stream, decoder failure…).
  Stream<Object> get errors;
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  JustAudioBackend([AudioPlayer? player]) : player = player ?? AudioPlayer();

  final AudioPlayer player;
  MediaInfo? current;

  /// Set by the OS media-session handler to publish now-playing info.
  void Function(MediaInfo info, Duration? duration)? onMedia;

  /// Non-null while a playlist is loaded; its table backs the global position.
  PlaylistTimeline? _timeline;
  final _total = StreamController<Duration?>.broadcast();
  Duration? _lastTotal;
  final _gate = PlaylistSeekGate();
  bool _disposed = false;
  bool _wantPlaying = false;

  /// Bumped by every load / loadPlaylist; an append or load finishing after a newer one started
  /// must not publish its media info or total.
  int _loadGen = 0;

  // Verified on Windows (just_audio_windows) and written for the others: playlists, appends
  // while playing and appends after completion all work.
  @override
  bool get supportsPlaylist => true;

  void _publishTotal(PlaylistTimeline t) {
    _lastTotal = t.total;
    if (!_total.isClosed) _total.add(t.total);
  }

  @override
  Future<void> loadPlaylist(List<PlaylistItem> items, {required MediaInfo info}) async {
    if (_disposed) return;
    final gen = ++_loadGen;
    _wantPlaying = false; // a pending play retry belongs to the old media
    current = info;
    final timeline = PlaylistTimeline(items.map((i) => i.duration));
    _timeline = timeline;
    _gate.clear();
    await player.setAudioSources([for (final i in items) AudioSource.uri(i.uri)]);
    // just_audio_windows drops a play() issued before the player is really ready.
    try {
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.ready)
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Carry on; play() retries once if it was dropped.
    }
    if (_disposed || gen != _loadGen) return; // a newer load owns the media session now
    onMedia?.call(info, timeline.total);
    _publishTotal(timeline);
  }

  @override
  Future<void> appendItem(PlaylistItem item, {bool resume = false}) async {
    if (_disposed) return;
    final timeline = _timeline;
    if (timeline == null) throw StateError('appendItem without loadPlaylist');
    final gen = _loadGen;
    timeline.add(item.duration);
    await player.addAudioSource(AudioSource.uri(item.uri));
    if (_disposed || gen != _loadGen) return; // a newer load replaced this playlist
    final info = current;
    if (info != null) onMedia?.call(info, timeline.total);
    _publishTotal(timeline);
    // After the last item finished the player sits in `completed` and not playing.
    if (resume && player.processingState == ProcessingState.completed) await play();
  }

  @override
  Stream<int?> get currentItem => player.currentIndexStream.where((_) => _timeline != null).distinct();

  @override
  Future<Duration?> load(Uri uri, {required MediaInfo info}) async {
    final gen = ++_loadGen;
    _wantPlaying = false; // a pending play retry belongs to the old media
    current = info;
    _timeline = null;
    final d = await player.setAudioSource(AudioSource.uri(uri));
    if (gen == _loadGen) onMedia?.call(info, d);
    return d;
  }

  // just_audio's play() completes only when playback stops, so don't await it.
  @override
  Future<void> play() async {
    _wantPlaying = true;
    unawaited(player.play());
    if (_timeline != null) unawaited(_retryDroppedPlay());
  }

  /// just_audio_windows can still drop a play() right after loading: if playback isn't on
  /// after a moment and nobody paused, press play once more.
  Future<void> _retryDroppedPlay() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed || !_wantPlaying || player.playing) return;
    unawaited(player.play());
  }

  @override
  Future<void> pause() {
    _wantPlaying = false;
    return player.pause();
  }

  @override
  Future<void> seek(Duration d) {
    final t = _timeline;
    if (t == null) return player.seek(d);
    final at = t.locate(d);
    _gate.seek(at);
    return player.seek(at.offset, index: at.index);
  }

  @override
  Future<void> stop() {
    _wantPlaying = false;
    return player.stop();
  }

  @override
  Future<void> setSpeed(double s) => player.setSpeed(s);

  @override
  Stream<Duration> get position =>
      player.positionStream.where((p) => _timeline == null || _gate.admit(player.currentIndex ?? 0, p)).map((p) {
        final t = _timeline;
        return t == null ? p : t.global(player.currentIndex ?? 0, p);
      });

  @override
  Stream<bool> get playing => player.playingStream;

  @override
  Stream<bool> get completed {
    late final StreamController<bool> out;
    StreamSubscription<ProcessingState>? sub;
    Timer? recheck;
    bool counts() {
      final t = _timeline;
      if (t == null) return true;
      return playlistCompletionCounts(index: player.currentIndex ?? 0, length: t.length, sinceSeek: _gate.sinceSeek);
    }

    out = StreamController<bool>.broadcast(
      onListen: () {
        sub = player.processingStateStream.listen((s) {
          recheck?.cancel();
          if (s != ProcessingState.completed) {
            out.add(false);
          } else if (counts()) {
            out.add(true);
          } else if (_timeline != null) {
            // Maybe a post-seek blip, maybe a real end right after a seek: look again later.
            recheck = Timer(kSeekCompletionWindow, () {
              if (player.processingState == ProcessingState.completed && counts() && !out.isClosed) out.add(true);
            });
          }
        });
      },
      onCancel: () async {
        recheck?.cancel();
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<Duration?> get duration {
    late final StreamController<Duration?> out;
    StreamSubscription<Duration?>? fromPlayer, fromTotal;
    out = StreamController<Duration?>.broadcast(
      onListen: () {
        // In playlist mode the player reports per-item lengths; only the total is the duration.
        fromPlayer = player.durationStream.listen((d) {
          if (_timeline == null) out.add(d);
        });
        fromTotal = _total.stream.listen(out.add);
        // Late subscribers get the last total right away.
        final last = _lastTotal;
        if (last != null && _timeline != null) scheduleMicrotask(() => out.isClosed ? null : out.add(last));
      },
      onCancel: () async {
        await fromPlayer?.cancel();
        await fromTotal?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<Object> get errors => player.errorStream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _total.close();
    await player.dispose();
  }
}
