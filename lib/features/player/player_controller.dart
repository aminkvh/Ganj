import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto/poem.dart';
import '../../data/api/dto/recitation.dart';
import '../../data/providers.dart';
import 'audio_backend.dart';
import 'audio_store.dart';
import 'sync_engine.dart';

enum PlayerStatus { idle, loading, ready, error }

class PlayerState {
  PlayerState({
    this.poem,
    this.recitation,
    this.status = PlayerStatus.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    SyncTimeline? timeline,
    this.currentVOrder,
    this.speed = 1,
    this.follow = false,
  }) : timeline = timeline ?? SyncTimeline(const []);

  final Poem? poem;
  final Recitation? recitation;
  final PlayerStatus status;
  final bool playing;
  final Duration position;
  final Duration duration;
  final SyncTimeline timeline;
  final int? currentVOrder;
  final double speed;

  /// Whether the poem page scrolls along with the recitation: on when it was started from a beyt.
  final bool follow;

  PlayerState copyWith({
    PlayerStatus? status,
    bool? playing,
    Duration? position,
    Duration? duration,
    SyncTimeline? timeline,
    int? Function()? currentVOrder,
    double? speed,
    bool? follow,
  }) => PlayerState(
    poem: poem,
    recitation: recitation,
    status: status ?? this.status,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    timeline: timeline ?? this.timeline,
    currentVOrder: currentVOrder == null ? this.currentVOrder : currentVOrder(),
    speed: speed ?? this.speed,
    follow: follow ?? this.follow,
  );
}

final audioBackendProvider = Provider<AudioBackend>((ref) => throw UnimplementedError('override in main'));

class PlayerController extends Notifier<PlayerState> {
  /// Bumped by every play(); an older call that resumes after an await gives up.
  int _generation = 0;
  bool _completed = false;

  /// What the listener wants while a recitation is still loading (the backend isn't playing yet).
  bool _wantPlay = true;

  AudioBackend get _backend => ref.read(audioBackendProvider);

  @override
  PlayerState build() {
    final b = ref.watch(audioBackendProvider);
    final subs = [
      b.position.listen(_onPosition),
      b.playing.listen((p) {
        if (state.status != PlayerStatus.loading) state = state.copyWith(playing: p);
      }),
      b.errors.listen((_) {
        if (state.status != PlayerStatus.idle) state = state.copyWith(status: PlayerStatus.error, playing: false);
      }),
      b.duration.listen((d) {
        if (d != null && d > Duration.zero) state = state.copyWith(duration: d);
      }),
      b.completed.listen((done) {
        _completed = done;
        if (done) state = state.copyWith(playing: false, currentVOrder: () => null);
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return PlayerState();
  }

  void _onPosition(Duration p) {
    if (_completed) return; // the player reports its final position after finishing
    final r = state.recitation;
    final v = (r != null && r.inSync) ? state.timeline.vOrderAt(p) : null;
    if (p == state.position && v == state.currentVOrder) return;
    state = state.copyWith(position: p, currentVOrder: () => v);
  }

  /// [follow]: scroll the poem page along; recitations started from the list leave the page alone.
  Future<void> play(Poem poem, Recitation r, {bool? follow}) async {
    final gen = ++_generation;
    _completed = false;
    _wantPlay = true;
    bool stale() => gen != _generation;
    // `playing` is the intent, so the button already shows «pause» while the audio loads.
    state = PlayerState(
      poem: poem,
      recitation: r,
      status: PlayerStatus.loading,
      playing: true,
      speed: state.speed,
      follow: follow ?? state.follow,
    );
    final store = ref.read(audioStoreProvider);
    try {
      final local = store != null && store.isDownloaded(r.id) ? store.mp3Uri(r.id) : null;
      final points = r.inSync ? await _sync(r, store) : const <SyncPoint>[];
      if (stale()) return;
      final timeline = SyncTimeline(points, validVOrders: {for (final v in poem.verses) v.vOrder});
      final duration = await _backend.load(
        local ?? Uri.parse(r.mp3Url),
        info: MediaInfo(id: '${r.id}', title: poem.title, artist: r.artist),
      );
      if (stale()) return; // superseded by a newer play()
      // Windows reports the duration on the stream during load and returns null here.
      state = state.copyWith(status: PlayerStatus.ready, timeline: timeline, duration: duration ?? state.duration);
      await _backend.setSpeed(state.speed);
      state = state.copyWith(playing: _wantPlay);
      if (_wantPlay) {
        await _backend.play();
      } else {
        await _backend.pause();
      }
    } catch (_) {
      if (!stale()) state = state.copyWith(status: PlayerStatus.error, playing: false);
    }
  }

  /// Saved sync first (offline), then the API; a sync failure never blocks playback.
  Future<List<SyncPoint>> _sync(Recitation r, AudioStore? store) async {
    final saved = await store?.savedSync(r.id);
    if (saved != null && saved.isNotEmpty) return saved; // empty = sync failed during download
    try {
      return await ref.read(poetryRepositoryProvider).recitationSync(r.id);
    } catch (_) {
      return const [];
    }
  }

  Future<void> retry() async {
    final p = state.poem, r = state.recitation;
    if (p != null && r != null) await play(p, r);
  }

  Future<void> toggle() {
    if (state.status == PlayerStatus.loading) {
      _wantPlay = !_wantPlay;
      state = state.copyWith(playing: _wantPlay);
      return _wantPlay ? Future.value() : _backend.pause();
    }
    return state.playing ? _backend.pause() : _backend.play();
  }

  void setFollow(bool on) => state = state.copyWith(follow: on);

  Future<void> seek(Duration d) => _backend.seek(d);

  /// Seeks to the start of [vOrder]; false when this recitation does not read that line.
  Future<bool> seekToVOrder(int vOrder) async {
    final start = state.timeline.startOf(vOrder);
    if (start == null || !(state.recitation?.inSync ?? false)) return false;
    state = state.copyWith(follow: true); // asked from a beyt: the page follows along
    await _backend.seek(start);
    if (!state.playing) await _backend.play();
    return true;
  }

  Future<void> setSpeed(double s) async {
    state = state.copyWith(speed: s);
    await _backend.setSpeed(s);
  }

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  Future<void> _step(int delta) async {
    final p = state.poem, r = state.recitation;
    if (p == null || r == null || p.recitations.isEmpty) return;
    final i = p.recitations.indexWhere((x) => x.id == r.id);
    final j = (i + delta) % p.recitations.length;
    await play(p, p.recitations[j]);
  }

  Future<void> stop() async {
    await _backend.stop();
    state = PlayerState(speed: state.speed);
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
