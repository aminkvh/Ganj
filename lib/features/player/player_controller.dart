import 'dart:async';
import 'dart:io';

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
    this.waiting = false,
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

  /// The voice stream is paused at a beyt boundary until the next beyt is made. [playing] keeps
  /// the listener's intent; the UI shows the loading ring as for [PlayerStatus.loading].
  final bool waiting;

  PlayerState copyWith({
    PlayerStatus? status,
    bool? playing,
    Duration? position,
    Duration? duration,
    SyncTimeline? timeline,
    int? Function()? currentVOrder,
    double? speed,
    bool? follow,
    bool? waiting,
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
    waiting: waiting ?? this.waiting,
  );
}

final audioBackendProvider = Provider<AudioBackend>((ref) => throw UnimplementedError('override in main'));

/// The id of the on-device voice's pseudo-recitation (never a real recitation id).
const kVoiceRecitationId = -1;

Recitation voiceRecitation(Poem p, String artist) => Recitation(
  id: kVoiceRecitationId,
  poemId: p.id,
  title: '',
  artist: artist,
  artistUrl: '',
  mp3Url: '',
  mp3Size: 0,
  audioOrder: 0,
  inSync: true,
);

/// How close to the end of the last ready beyt the voice stream pauses to wait for the next one.
const kVoiceStallMargin = Duration(milliseconds: 150);

/// Names one logical voice stream, returned by [PlayerController.startVoiceStream]. Pass it to
/// [PlayerController.addVoiceBeyt] and [PlayerController.endVoiceStream]; once a newer stream,
/// another play or a stop has replaced it, those calls ignore it. A retry keeps the same token.
class VoiceStreamToken {
  VoiceStreamToken._(this.started);

  /// Completes when the first load has finished (playing, failed or superseded); never throws.
  final Future<void> started;
}

/// The voice reading of one poem, played while later beyts are still being made.
class _VoiceStream {
  _VoiceStream(this.poem, this.artist, this.token);

  final Poem poem;
  final String artist;
  final VoiceStreamToken token;
  final items = <PlaylistItem>[];
  final vOrders = <int>[];

  /// How many of [items] the backend has; only those are ready to play or seek to.
  int sent = 0;

  /// The playlist finished loading; later items go in by append.
  bool loaded = false;
  bool pumping = false;

  /// No more beyts will come.
  bool ended = false;

  Duration get sentTotal => items.take(sent).fold(Duration.zero, (a, i) => a + i.duration);

  /// A fresh run over the same beyts (retry reloads them all).
  _VoiceStream copy() => _VoiceStream(poem, artist, token)
    ..items.addAll(items)
    ..vOrders.addAll(vOrders)
    ..ended = ended;

  /// Sync points from the ready beyts' lengths, plus the end marker once the stream has ended.
  SyncTimeline timeline() {
    final points = <SyncPoint>[];
    var at = Duration.zero;
    for (var i = 0; i < items.length; i++) {
      if (i < sent) points.add(SyncPoint(vOrders[i], at.inMilliseconds));
      at += items[i].duration;
    }
    if (ended) points.add(SyncPoint(-2, at.inMilliseconds));
    return SyncTimeline(points, validVOrders: {for (final v in poem.verses) v.vOrder});
  }
}

class PlayerController extends Notifier<PlayerState> {
  /// Bumped by every play(); an older call that resumes after an await gives up.
  int _generation = 0;

  /// The voice stream being played (null when the loaded media is anything else).
  _VoiceStream? _stream;
  late StreamController<void> _stalls;

  /// The backend reported the open stream's playlist completed and has not played since: there is
  /// nothing left to hear until the next beyt.
  bool _backendCompleted = false;
  bool _completed = false;

  /// What the listener wants while a recitation is still loading (the backend isn't playing yet).
  bool _wantPlay = true;

  /// The voice's wav and sync points, kept so retry can reload them.
  File? _voiceWav;
  List<SyncPoint> _voicePoints = const [];

  AudioBackend get _backend => ref.read(audioBackendProvider);

  @override
  PlayerState build() {
    final b = ref.watch(audioBackendProvider);
    final stalls = _stalls = StreamController<void>.broadcast();
    final subs = [
      b.position.listen(_onPosition),
      b.playing.listen((p) {
        // While waiting the backend is paused, but the listener still wants it playing.
        if (state.status != PlayerStatus.loading && !state.waiting) state = state.copyWith(playing: p);
      }),
      b.errors.listen((_) {
        if (state.status != PlayerStatus.idle) {
          state = state.copyWith(status: PlayerStatus.error, playing: false, waiting: false);
        }
      }),
      b.duration.listen((d) {
        if (d != null && d > Duration.zero) state = state.copyWith(duration: d);
      }),
      b.completed.listen((done) {
        if (done && _streamOpen) {
          _backendCompleted = true;
          // Ran past the last ready beyt before the position check caught it: wait there. A
          // listener who had paused keeps the pause.
          if (state.playing && !state.waiting) _enterWaiting();
          return;
        }
        if (!done) _backendCompleted = false;
        _completed = done;
        if (done) state = state.copyWith(playing: false, currentVOrder: () => null);
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      stalls.close();
    });
    return PlayerState();
  }

  void _onPosition(Duration p) {
    if (_completed) return; // the player reports its final position after finishing
    final r = state.recitation;
    final v = (r != null && r.inSync) ? state.timeline.vOrderAt(p) : null;
    if (p != state.position || v != state.currentVOrder) state = state.copyWith(position: p, currentVOrder: () => v);
    if (state.playing && !state.waiting && _atStreamEdge(p)) _enterWaiting();
  }

  /// True when a voice stream is loaded, ready and still expecting beyts: not ended, or ended with
  /// beyts still on their way to the backend (an append in flight).
  bool get _streamOpen {
    final s = _stream;
    return s != null && s.loaded && (!s.ended || s.sent < s.items.length) && state.status == PlayerStatus.ready;
  }

  /// Whether an open stream has nothing left to play at [p]: the backend completed, or [p] is
  /// within the stall margin (in wall time, so scaled by the speed) of the end of the ready beyts.
  bool _atStreamEdge(Duration p) =>
      _streamOpen && (_backendCompleted || p >= _stream!.sentTotal - kVoiceStallMargin * state.speed);

  /// Pauses at the beyt boundary until [addVoiceBeyt] brings the next one. [report] tells
  /// [voiceStalls]: only when playback reached the edge on its own, not after a seek or a play.
  void _enterWaiting({bool report = true}) {
    state = state.copyWith(waiting: true, playing: true);
    if (report && !_stalls.isClosed) _stalls.add(null);
    unawaited(_backend.pause());
  }

  /// Leaves the waiting state and plays on from where it paused.
  Future<void> _continue() async {
    _backendCompleted = false;
    state = state.copyWith(waiting: false, playing: true);
    await _backend.play();
  }

  /// The stream played out its last beyt: the reading is finished.
  void _finish() {
    _backendCompleted = false;
    _completed = true;
    state = state.copyWith(waiting: false, playing: false, currentVOrder: () => null);
  }

  /// Whether this platform can play a voice stream; when false, prepare the whole poem and use
  /// [playVoice] instead of [startVoiceStream].
  bool get canStream => _backend.supportsPlaylist;

  /// True while the loaded media is a voice stream (until [stop] or another play). It stays true
  /// after [endVoiceStream]: the OS controls keep showing it as live until the next play.
  bool get streaming => _stream != null;

  /// Whether [token]'s stream is the media being played (it stays so after [endVoiceStream], until [stop] or
  /// the next play).
  bool isCurrentStream(VoiceStreamToken token) => identical(_stream?.token, token);

  /// Fires each time a voice stream has to wait for a beyt that is not made yet.
  Stream<void> get voiceStalls => _stalls.stream;

  /// Starts the on-device voice from its [first] beyt (verse [firstVOrder]) while the rest are
  /// still being made; feed them with [addVoiceBeyt] and finish with [endVoiceStream], passing the
  /// returned token (usable at once, also while the first load runs; await
  /// [VoiceStreamToken.started] for the load itself). Requires [canStream].
  VoiceStreamToken startVoiceStream(
    Poem poem, {
    required String artist,
    required PlaylistItem first,
    required int firstVOrder,
  }) {
    final started = Completer<void>();
    final token = VoiceStreamToken._(started.future);
    final s = _VoiceStream(poem, artist, token)
      ..items.add(first)
      ..vOrders.add(firstVOrder);
    unawaited(_startStream(s, started)); // runs synchronously up to the load
    return token;
  }

  /// Loads [s] and plays, completes [started] once that first load is over (before any queued
  /// appends), then hands the beyts that arrived meanwhile to the backend.
  Future<void> _startStream(_VoiceStream s, [Completer<void>? started]) async {
    final ok = await _loadStream(s);
    if (started != null && !started.isCompleted) started.complete();
    if (ok) await _pump(s); // beyts that arrived during the load
  }

  /// The load-and-play part of [_startStream]; false when it failed or was superseded.
  Future<bool> _loadStream(_VoiceStream s) async {
    final gen = ++_generation;
    _voiceWav = null;
    _stream = s;
    _backendCompleted = false;
    _completed = false;
    _wantPlay = true;
    bool stale() => gen != _generation;
    state = PlayerState(
      poem: s.poem,
      recitation: voiceRecitation(s.poem, s.artist),
      status: PlayerStatus.loading,
      playing: true,
      speed: state.speed,
      follow: state.follow,
    );
    try {
      final items = [...s.items];
      final info = MediaInfo(id: 'voice-${s.poem.id}', title: s.poem.title, artist: s.artist, live: true);
      await _backend.loadPlaylist(items, info: info);
      if (stale()) return false;
      s
        ..sent = items.length
        ..loaded = true;
      state = state.copyWith(status: PlayerStatus.ready, timeline: s.timeline(), duration: s.sentTotal);
      await _backend.setSpeed(state.speed);
      if (stale()) return false;
      state = state.copyWith(playing: _wantPlay);
      if (_wantPlay) {
        await _backend.play();
      } else {
        await _backend.pause();
      }
      return true;
    } catch (_) {
      if (!stale()) state = state.copyWith(status: PlayerStatus.error, playing: false);
      return false;
    }
  }

  /// Adds the next made beyt to the voice stream: the timeline grows and, if playback was waiting
  /// for it, playback goes on. Ignored when [token] is not the current stream (after [stop],
  /// another play or a newer stream), after [endVoiceStream], or for a verse already added.
  Future<void> addVoiceBeyt(VoiceStreamToken token, PlaylistItem item, int vOrder) async {
    final s = _stream;
    if (s == null || !identical(s.token, token) || s.ended || s.vOrders.contains(vOrder)) return;
    s.items.add(item);
    s.vOrders.add(vOrder);
    await _pump(s);
  }

  /// Hands the stream's waiting beyts to the backend in order, one append at a time.
  Future<void> _pump(_VoiceStream s) async {
    if (s.pumping || !s.loaded) return;
    s.pumping = true;
    try {
      while (identical(_stream, s) && s.sent < s.items.length) {
        // No `resume`: the check after the await plays, so a pause during the append holds.
        await _backend.appendItem(s.items[s.sent]);
        if (!identical(_stream, s)) return;
        s.sent++;
        _backendCompleted = false; // there is audio to play again
        state = state.copyWith(timeline: s.timeline(), duration: s.sentTotal);
        if (state.waiting) await _continue();
      }
    } catch (_) {
      if (identical(_stream, s)) state = state.copyWith(status: PlayerStatus.error, playing: false, waiting: false);
    } finally {
      s.pumping = false;
    }
  }

  /// No more beyts for [token]'s stream: adds the end marker at the total. A stream waiting at
  /// the last beyt's edge plays it out; one whose backend already completed is finished.
  void endVoiceStream(VoiceStreamToken token) {
    final s = _stream;
    if (s == null || !identical(s.token, token) || s.ended) return;
    s.ended = true;
    if (!s.loaded) return; // the load builds the timeline with the marker
    state = state.copyWith(timeline: s.timeline());
    if (s.sent < s.items.length) return; // an append in flight resumes it
    if (_backendCompleted) {
      _finish(); // everything was already heard (waiting or paused)
    } else if (state.waiting) {
      unawaited(_continue());
    }
  }

  /// [follow]: scroll the poem page along; recitations started from the list leave the page alone.
  Future<void> play(Poem poem, Recitation r, {bool? follow}) {
    _voiceWav = null;
    return _start(poem, r, follow, () async {
      final store = ref.read(audioStoreProvider);
      final local = store != null && store.isDownloaded(r.id) ? store.mp3Uri(r.id) : null;
      final points = r.inSync ? await _sync(r, store) : const <SyncPoint>[];
      return (
        uri: local ?? Uri.parse(r.mp3Url),
        points: points,
        info: MediaInfo(id: '${r.id}', title: poem.title, artist: r.artist),
      );
    });
  }

  /// Plays the on-device voice's [wav] with its [sync] points; no network, store or API sync.
  Future<void> playVoice(Poem poem, File wav, List<SyncPoint> sync, {required String artist}) {
    _voiceWav = wav;
    _voicePoints = sync;
    return _start(
      poem,
      voiceRecitation(poem, artist),
      null,
      () async => (
        uri: Uri.file(wav.path),
        points: sync,
        info: MediaInfo(id: 'voice-${poem.id}', title: poem.title, artist: artist),
      ),
    );
  }

  /// The shared load-and-play flow; [source] resolves what to load (and may await).
  Future<void> _start(
    Poem poem,
    Recitation r,
    bool? follow,
    Future<({Uri uri, List<SyncPoint> points, MediaInfo info})> Function() source,
  ) async {
    final gen = ++_generation;
    _stream = null; // any voice stream ends; its later beyts are ignored
    _backendCompleted = false;
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
    try {
      final src = await source();
      if (stale()) return;
      final timeline = SyncTimeline(src.points, validVOrders: {for (final v in poem.verses) v.vOrder});
      final duration = await _backend.load(src.uri, info: src.info);
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
    if (p == null || r == null) return;
    final s = _stream;
    if (r.id == kVoiceRecitationId && s != null) return _startStream(s.copy()); // reload the ready beyts
    final wav = _voiceWav;
    if (r.id == kVoiceRecitationId && wav != null) {
      await playVoice(p, wav, _voicePoints, artist: r.artist);
    } else {
      await play(p, r);
    }
  }

  Future<void> toggle() => state.playing ? pause() : resume();

  /// The listener pauses (in-app or from the OS controls). A wait for the next beyt is cancelled:
  /// that beyt will not resume playback.
  Future<void> pause() async {
    if (state.status == PlayerStatus.loading) {
      _wantPlay = false;
      state = state.copyWith(playing: false);
      await _backend.pause();
    } else if (state.waiting) {
      state = state.copyWith(waiting: false, playing: false); // the backend is already paused
    } else {
      // In the state at once, so a completion already queued sees a pause, not a stall.
      state = state.copyWith(playing: false);
      await _backend.pause();
    }
  }

  /// The listener plays (in-app or from the OS controls). At the edge of a voice stream with
  /// nothing ready yet, it waits for the next beyt instead.
  Future<void> resume() async {
    if (state.status == PlayerStatus.loading) {
      _wantPlay = true;
      state = state.copyWith(playing: true);
    } else if (state.waiting) {
      return;
    } else if (_atStreamEdge(state.position)) {
      _enterWaiting(report: false);
    } else {
      await _backend.play();
    }
  }

  void setFollow(bool on) => state = state.copyWith(follow: on);

  /// Seeks to [d]; in a voice stream, a point past the beyts made so far is ignored.
  Future<void> seek(Duration d) async {
    final s = _stream;
    if (s != null && s.loaded && d >= s.sentTotal) return;
    await _seekAndGo(d, playAfter: false);
  }

  /// Seeks to the start of [vOrder]; false when this recitation does not read that line (or, in a
  /// voice stream, that beyt is not made yet).
  Future<bool> seekToVOrder(int vOrder) async {
    final start = state.timeline.startOf(vOrder);
    if (start == null || !(state.recitation?.inSync ?? false)) return false;
    state = state.copyWith(follow: true); // asked from a beyt: the page follows along
    await _seekAndGo(start, playAfter: true);
    return true;
  }

  /// Seeks; a stream that was waiting at the edge plays on from the new point, and a seek that
  /// lands at the edge while playing waits there (without reporting a stall).
  Future<void> _seekAndGo(Duration d, {required bool playAfter}) async {
    final wasWaiting = state.waiting;
    final wantsPlay = wasWaiting || playAfter || state.playing;
    _backendCompleted = false;
    if (wantsPlay && _atStreamEdge(d)) {
      _enterWaiting(report: false); // before the seek, so its position event is no stall
      await _backend.seek(d);
      return;
    }
    if (wasWaiting) state = state.copyWith(waiting: false);
    await _backend.seek(d);
    if (wasWaiting || (playAfter && !state.playing)) await _backend.play();
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
    final n = p.recitations.length;
    // The voice is not in the human list: step onto its first / last recitation.
    final i = r.id == kVoiceRecitationId ? (delta > 0 ? -1 : n) : p.recitations.indexWhere((x) => x.id == r.id);
    final j = (i + delta) % n;
    await play(p, p.recitations[j]);
  }

  /// Stops and clears the player. The state is reset at once, before the backend has stopped, so a play
  /// started meanwhile (or code reading the state right after) never sees the stopped media, and nothing
  /// written after the await could overwrite the newer play's state.
  Future<void> stop() async {
    _generation++; // a play()/playVoice() still loading is now stale and never starts
    _stream = null; // a voice stream's later beyts are ignored
    _backendCompleted = false;
    state = PlayerState(speed: state.speed);
    await _backend.stop();
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
