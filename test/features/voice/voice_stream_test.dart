import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/voice/app/voice_cache.dart';
import 'package:ganj/features/voice/app/voice_providers.dart';
import 'package:ganj/features/voice/app/voice_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';
import 'fakes.dart';

const _artist = 'خوانش ماشینی';
const _t8Key = 'voice.t8.v1';

/// The t8 a measured [speed] (audio seconds per wall second) at [steps] stands for.
double _t8(double speed, int steps) => 1 / speed / (0.1 + 0.9 * steps / 8);
final _sep = Platform.pathSeparator;

/// [n] beyts of equal length (vOrders 1 … 2n).
Poem _poem(int id, {int n = 7}) => Poem(
  id: id,
  title: 'p$id',
  fullTitle: 'p$id',
  fullUrl: '/p$id',
  plainText: '',
  metre: 'm',
  recitations: poem2130().recitations,
  verses: [
    for (var i = 0; i < n; i++) ...[
      Verse(vOrder: 2 * i + 1, position: VersePosition.right, text: 'r${i}x$id', coupletIndex: i),
      Verse(vOrder: 2 * i + 2, position: VersePosition.left, text: 'l${i}x$id', coupletIndex: i),
    ],
  ],
);

/// A phase 1 install (`<root>/v1`, so the variant is quality).
void _install(Directory root) {
  final d = Directory('${root.path}${_sep}v1')..createSync(recursive: true);
  File('${d.path}${_sep}model.onnx').writeAsBytesSync(List.filled(100, 1));
  File('${d.path}${_sep}installed.json').writeAsStringSync(
    jsonEncode({
      'version': 'v1',
      'files': [
        {'name': 'model.onnx', 'size': 100, 'sha256': 'ab'},
      ],
    }),
  );
}

class _Clock {
  DateTime now = DateTime(2026, 11, 8);

  void advance(double seconds) => now = now.add(Duration(microseconds: (seconds * 1e6).round()));
}

/// A worker the test drives beyt by beyt; each [emit] first lets wall time pass on [clock].
class _ManualWorker implements VoiceWorker {
  _ManualWorker(this.clock);

  final _Clock clock;
  StreamController<BeytAudio>? _out;
  List<BeytRequest> _asked = const [];
  int _next = 0;
  int reads = 0;

  /// The flow steps of each read, in order.
  final List<int?> steps = [];

  /// The beyt indexes of the latest read.
  List<int> get asked => [for (final b in _asked) b.index];

  bool get open => _out != null && !_out!.isClosed;

  @override
  Stream<BeytAudio> read(List<BeytRequest> beyts, {String? metre, int? steps}) {
    cancel();
    reads++;
    this.steps.add(steps);
    _asked = beyts;
    _next = 0;
    final out = _out = StreamController<BeytAudio>();
    return out.stream;
  }

  /// [wallS] seconds pass, then the next asked beyt arrives with [audioS] seconds of audio. The stream closes
  /// after the last one. Completes once the prepare has had the beyt (so each arrival sees its own time).
  Future<void> emit({required double wallS, double audioS = 1}) async {
    clock.advance(wallS);
    final out = _out!;
    out.add(BeytAudio(_asked[_next++].index, FakeVoiceWorker.tone(seconds: audioS), 24000));
    if (_next == _asked.length) unawaited(out.close());
    await Future<void>.delayed(Duration.zero);
  }

  /// [wallS] seconds pass, then the next asked beyt fails to read (the prepare puts silence in its place).
  Future<void> readError({required double wallS}) async {
    clock.advance(wallS);
    final out = _out!;
    out.addError(VoiceReadError(_asked[_next++].index));
    if (_next == _asked.length) unawaited(out.close());
    await Future<void>.delayed(Duration.zero);
  }

  /// The worker breaks: [e] and the stream closes.
  Future<void> breakWith(Object e) async {
    final out = _out!;
    out.addError(e);
    unawaited(out.close());
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitAll(int count, {required double wallS}) async {
    for (var i = 0; i < count; i++) {
      await emit(wallS: wallS);
    }
  }

  @override
  void cancel() {
    final c = _out;
    _out = null;
    if (c != null && !c.isClosed) c.close();
  }

  @override
  Future<void> dispose() async {}
}

/// A real cache whose writes can be held or made to fail.
class _GatedCache extends VoiceCache {
  _GatedCache(super.root);

  /// Holds each part write until it completes.
  Completer<void>? putGate;

  /// Holds each beyt item until it completes; [itemAsked] tells when one waits.
  Completer<void>? itemGate;
  bool itemAsked = false;

  bool failJoin = false;

  /// The parts check after the read finds beyt 0 missing.
  bool partsShort = false;

  @override
  Future<void> putBeyt(int poemId, String key, BeytAudio a) async {
    final g = putGate;
    if (g != null) await g.future;
    return super.putBeyt(poemId, key, a);
  }

  @override
  Future<File> beytItem(int poemId, String key, int index, {required bool last, int sampleRate = 24000}) async {
    final g = itemGate;
    if (g != null) {
      itemAsked = true;
      await g.future;
    }
    return super.beytItem(poemId, key, index, last: last, sampleRate: sampleRate);
  }

  @override
  Future<File> join(int poemId, String key, List<int> vOrders, {int sampleRate = 24000, bool keepItems = false}) {
    if (failJoin) return Future.error(const FileSystemException('disk full'));
    return super.join(poemId, key, vOrders, sampleRate: sampleRate, keepItems: keepItems);
  }

  @override
  Set<int> partsHave(int poemId, String key) {
    final have = super.partsHave(poemId, key);
    return partsShort ? (have..remove(0)) : have;
  }
}

Future<void> _until(bool Function() cond, {String what = 'condition'}) async {
  for (var i = 0; i < 1000; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('timed out waiting for $what');
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late Directory tmp;
  late Directory root;
  late Directory cacheBase;
  late FakeAudioBackend backend;
  late SharedPreferences prefs;
  late _Clock clock;
  late _ManualWorker worker;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('voice_stream_');
    root = Directory('${tmp.path}${_sep}voice')..createSync();
    cacheBase = Directory('${tmp.path}${_sep}voice-cache');
    backend = FakeAudioBackend();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = _Clock();
    worker = _ManualWorker(clock);
    _install(root);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file for a moment.
    }
  });

  ProviderContainer container({VoiceCache? cache}) {
    final c = ProviderContainer(
      overrides: [
        if (cache != null) voiceCacheProvider.overrideWithValue(cache),
        sharedPrefsProvider.overrideWithValue(prefs),
        audioBackendProvider.overrideWithValue(backend),
        poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
        voiceRootProvider.overrideWithValue(root),
        voiceCacheBaseProvider.overrideWithValue(cacheBase),
        voiceWorkerProvider.overrideWithValue(worker),
        voiceClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  const gapped = Duration(milliseconds: 1250); // 1 s of audio + kBeytGap

  group('VoiceCache.beytItem', () {
    test('writes the beyt as a WAV with the trailing gap, none for the last, and is idempotent', () async {
      final cache = VoiceCache(Directory('${tmp.path}${_sep}c'));
      final pcm = FakeVoiceWorker.tone(seconds: 0.5);
      await cache.putBeyt(1, 'k', BeytAudio(0, pcm, 24000));
      await cache.putBeyt(1, 'k', BeytAudio(1, pcm, 24000));
      final gap = (24000 * kBeytGap.inMilliseconds / 1000).round();

      final a = await cache.beytItem(1, 'k', 0, last: false);
      expect(a.lengthSync(), 44 + (pcm.length + gap) * 2);
      final bytes = a.readAsBytesSync();
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(ByteData.sublistView(bytes).getUint32(40, Endian.little), (pcm.length + gap) * 2);
      expect(bytes.sublist(bytes.length - gap * 2).every((b) => b == 0), isTrue);

      final b = await cache.beytItem(1, 'k', 1, last: true);
      expect(b.lengthSync(), 44 + pcm.length * 2);

      final again = await cache.beytItem(1, 'k', 0, last: false);
      expect(again.path, a.path);
      expect(again.lengthSync(), a.lengthSync());
      // The WAVs are not parts.
      expect(cache.partsHave(1, 'k'), {0, 1});
    });

    test('a re-read beyt replaces its old item', () async {
      final cache = VoiceCache(Directory('${tmp.path}${_sep}c'));
      await cache.putBeyt(1, 'k', BeytAudio(0, FakeVoiceWorker.tone(seconds: 0.5), 24000));
      final old = await cache.beytItem(1, 'k', 0, last: true);
      expect(old.lengthSync(), 44 + 12000 * 2);
      await cache.putBeyt(1, 'k', BeytAudio(0, FakeVoiceWorker.tone(seconds: 0.25), 24000));
      final fresh = await cache.beytItem(1, 'k', 0, last: true);
      expect(fresh.lengthSync(), 44 + 6000 * 2);
    });

    test('two writers of the same item both succeed', () async {
      final cache = VoiceCache(Directory('${tmp.path}${_sep}c'));
      await cache.putBeyt(1, 'k', BeytAudio(0, FakeVoiceWorker.tone(seconds: 0.5), 24000));
      final both = await Future.wait([cache.beytItem(1, 'k', 0, last: false), cache.beytItem(1, 'k', 0, last: false)]);
      expect(both[0].path, both[1].path);
      expect(both[0].lengthSync(), 44 + (12000 + 6000) * 2);
    });
  });

  group('streaming', () {
    test('fast device streams from first beyt', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3); // beyt 0, with the engine's load
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      expect(backend.playlists.single, hasLength(1));
      expect(backend.playlists.single.single.duration, gapped);
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      expect(c.read(playerProvider).poem?.id, 1);

      await worker.emitAll(6, wallS: 0.5);
      await f;
      expect(backend.appended, hasLength(6));
      expect(backend.appended.take(5).every((i) => i.duration == gapped), isTrue);
      expect(backend.appended.last.duration, const Duration(seconds: 1)); // no trailing gap
      expect(c.read(playerProvider).timeline.end, isNotNull); // ended
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(backend.loaded, isEmpty); // never swapped to the joined file mid-play
      expect(c.read(playerProvider.notifier).streaming, isTrue);
    });

    test('without a remembered speed it waits for beyt 1, then streams and remembers', () async {
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _settle();
      expect(backend.playlists, isEmpty); // speed not known yet
      await worker.emit(wallS: 0.5); // beyt 1 alone: 2× real time
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      expect(backend.playlists.single, hasLength(1));
      await worker.emitAll(5, wallS: 0.5);
      await f;
      expect(backend.appended, hasLength(6));
      expect(worker.steps, [4], reason: 'a first reading on this device');
      expect(prefs.getDouble(_t8Key), closeTo(_t8(2.0, 4), 1e-6)); // 2× at 4 steps, normalized to 8
      expect(prefs.getKeys().where((k) => k.startsWith('voice.speed')), isEmpty);
    });

    test('slow device prepares fully (phase 1 path)', () async {
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      for (var i = 0; i < 7; i++) {
        await worker.emit(wallS: 10); // 0.1× real time
        await _settle(); // a slow reader: each beyt is on disk long before the next
      }
      await f;
      expect(backend.playlists, isEmpty);
      expect(backend.loaded.single.path, endsWith('.wav'));
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(prefs.getDouble(_t8Key), closeTo(_t8(0.1, 4), 1e-6));
    });

    test('a platform without playlists prepares fully (phase 1 path)', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      backend.playlistSupported = false;
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emitAll(7, wallS: 0.5);
      await f;
      expect(backend.playlists, isEmpty);
      expect(backend.loaded.single.path, endsWith('.wav'));
    });

    test('stream completes, joins, next play is a cache hit', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.emitAll(6, wallS: 0.5);
      await f;
      expect(backend.loaded, isEmpty);
      final s = c.read(voicePrepareProvider(1));
      expect(s, isA<Prepared>());
      s as Prepared;
      expect(s.wav.existsSync(), isTrue);
      expect(s.sync.map((p) => p.vOrder), [1, 3, 5, 7, 9, 11, 13, -2]);
      // The stream's highlight mapping is the joined file's: each beyt starts where its sync point says.
      final timeline = c.read(playerProvider).timeline;
      for (final p in s.sync.where((p) => p.vOrder > 0)) {
        expect(timeline.vOrderAt(Duration(milliseconds: p.ms + 1)), p.vOrder);
        if (p.ms > 0) expect(timeline.vOrderAt(Duration(milliseconds: p.ms - 2)), isNot(p.vOrder));
      }
      expect((timeline.end!.inMilliseconds - s.sync.last.ms).abs(), lessThanOrEqualTo(1));

      await ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      expect(worker.reads, 1);
      expect(backend.loaded.single, Uri.file(s.wav.path));
      expect(c.read(playerProvider.notifier).streaming, isFalse);
    });

    test('cancel mid-stream stops the player and keeps the beyts for resume', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.emit(wallS: 0.5);
      await _until(() => backend.appended.isNotEmpty, what: 'beyt 1 in the stream');
      ctrl.cancel();
      await f;
      await _until(() => !c.read(playerProvider.notifier).streaming, what: 'the stop');
      expect(c.read(playerProvider).poem, isNull);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
      final cache = c.read(voiceCacheProvider)!;
      expect(cache.partsHave(1, cache.keyOf(_poem(1), 'v1')), {0, 1});
    });

    test('another poem\'s prepare cancels a streaming run, which stops its stream', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      // Not VoiceController.remove (which stops any voice playback itself): only the prepare side.
      final g = c.read(voicePrepareProvider(2).notifier).start(_poem(2), playWhenDone: false, artist: _artist);
      await f;
      await _until(() => !c.read(playerProvider.notifier).streaming, what: 'the stop');
      expect(c.read(playerProvider).poem, isNull);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
      await _until(() => worker.reads == 2 && worker.open, what: 'poem 2\'s read'); // after its steps file
      await worker.emitAll(7, wallS: 0.5);
      await g;
      expect(c.read(voicePrepareProvider(2)), isA<Prepared>());
      expect(backend.playlists, hasLength(1)); // poem 2 did not play
    });

    test('a new poem started while another streams plays', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'poem 1\'s stream');
      final g = c.read(voicePrepareProvider(2).notifier).start(_poem(2), playWhenDone: true, artist: _artist);
      await f;
      await _until(() => worker.reads == 2 && worker.open, what: 'poem 2\'s read'); // after its steps file
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.length == 2, what: 'poem 2\'s stream');
      await worker.emitAll(6, wallS: 0.5);
      await g;
      expect(c.read(playerProvider).poem?.id, 2);
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      expect(c.read(playerProvider).status, PlayerStatus.ready);
      expect(backend.appended, hasLength(6));
    });

    test('a new poem whose cached beyts start it at once is not clobbered by the old stream\'s stop', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final cache = c.read(voiceCacheProvider)!;
      final key2 = cache.keyOf(_poem(2), 'v1');
      for (var i = 0; i < 3; i++) {
        await cache.putBeyt(2, key2, BeytAudio(i, FakeVoiceWorker.tone(seconds: 1), 24000));
      }
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'poem 1\'s stream');
      final g = c.read(voicePrepareProvider(2).notifier).start(_poem(2), playWhenDone: true, artist: _artist);
      await f;
      await _until(() => backend.playlists.length == 2, what: 'poem 2\'s stream');
      await _settle();
      expect(backend.playlists.last, hasLength(1));
      expect(c.read(playerProvider).poem?.id, 2);
      expect(c.read(playerProvider).status, PlayerStatus.ready);
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      await worker.emitAll(4, wallS: 0.5);
      await g;
      expect(backend.appended, hasLength(6)); // beyts 1–2 from the cache, then 3–6
      expect(c.read(playerProvider).poem?.id, 2);
    });

    test('a worker failure mid-stream stops the stream and fails as in phase 1', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      await worker.breakWith(const VoiceWorkerDied('crash'));
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      await _until(() => !c.read(playerProvider.notifier).streaming, what: 'the stop');
      expect(c.read(playerProvider).waiting, isFalse);
      expect(c.read(voiceProvider), isA<VoiceReady>());
    });

    test('an engine load error mid-stream stops the stream', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      await worker.breakWith(const VoiceEngineLoadError('bad'));
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(c.read(playerProvider).waiting, isFalse);
    });

    test('clearing the cache spares the parts of the poem being streamed', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.emitAll(6, wallS: 0.5);
      await f; // the run is over (joined), but the player still plays the beyt items
      expect(c.read(voicePreparesProvider).runningPartsDir, isNull);
      final cache = c.read(voiceCacheProvider)!;
      final name = VoiceCache.partsName(1, cache.keyOf(_poem(1), 'v1'));
      expect(c.read(voicePreparesProvider).keepParts, {name});
      await cache.clear(keep: c.read(voicePreparesProvider).keepParts);
      expect(File('${cache.root.path}$_sep$name${_sep}0.wav').existsSync(), isTrue);
      await c.read(playerProvider.notifier).stop();
      expect(c.read(voicePreparesProvider).keepParts, isEmpty);
    });

    test('all beyts arriving before beyt 0 is written still stream', () async {
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emitAll(7, wallS: 0.5); // faster than the disk
      await f;
      expect(backend.playlists, hasLength(1));
      expect(backend.appended, hasLength(6));
      expect(backend.loaded, isEmpty);
    });

    test('silence put for an unreadable beyt does not count in the speed', () async {
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.readError(wallS: 0.001); // a fast failure: 0.5 s of silence
      await worker.emitAll(5, wallS: 1); // 1× real time
      await f;
      expect(prefs.getDouble(_t8Key), closeTo(_t8(1.0, 4), 0.02));
    });

    test('the player\'s speed feeds the start rule', () async {
      final c = container();
      await c.read(playerProvider.notifier).setSpeed(1.5);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      // 1.04× real time: at ×1 it would start after 2 beyts, at ×1.5 only after 4.
      for (var i = 1; i < 3; i++) {
        await worker.emit(wallS: 1 / 1.04);
        await _settle();
        expect(backend.playlists, isEmpty, reason: 'after ${i + 1} beyts');
      }
      await worker.emit(wallS: 1 / 1.04);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream after 4 beyts');
      await worker.emitAll(3, wallS: 1 / 1.04);
      await f;
    });

    test('quiet keeps a playing stream', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream');
      ctrl.quiet(); // the reader left the poem page
      c.read(voicePreparesProvider).quietExcept(2);
      await worker.emitAll(6, wallS: 0.5);
      await f;
      expect(backend.appended, hasLength(6));
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      expect(c.read(playerProvider).poem?.id, 1);
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
    });

    test('quiet before the start means it never starts', () async {
      await prefs.setDouble(_t8Key, 4.0); // 4 steps at 0.45× real time: the rule waits a while
      final c = container();
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _settle();
      expect(backend.playlists, isEmpty);
      ctrl.quiet();
      await worker.emitAll(6, wallS: 0.25); // now fast enough, but quiet
      await f;
      await _settle();
      expect(backend.playlists, isEmpty);
      expect(backend.loaded, isEmpty);
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
    });

    test('playWhenDone false never streams', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emitAll(7, wallS: 0.5);
      await f;
      expect(backend.playlists, isEmpty);
      expect(backend.loaded, isEmpty);
    });

    test('a stall raises the remembered t8', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.steps, [8]);
      await worker.emit(wallS: 3);
      await _until(() => backend.isPlaying, what: 'playback');
      backend.emitItemPosition(0, const Duration(milliseconds: 1200)); // the edge of the only ready beyt
      await _until(() => c.read(playerProvider).waiting, what: 'the stall');
      await _until(() => (prefs.getDouble(_t8Key) ?? 0) > 0.51, what: 'the raised t8');
      expect(prefs.getDouble(_t8Key), closeTo(0.5 / 0.9, 1e-6));
      await worker.emitAll(6, wallS: 0.25); // measured: 4× real time at 8 steps, t8 0.25
      await f;
      expect(prefs.getDouble(_t8Key), closeTo(0.25 / 0.9, 1e-6)); // the measurement, raised for the stall
    });

    test('a first reading uses 4 steps and records them before the first part', () async {
      final c = container();
      final cache = c.read(voiceCacheProvider)!;
      final key = cache.keyOf(_poem(1), 'v1');
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.steps, [4]);
      expect(cache.partsHave(1, key), isEmpty);
      expect(cache.partsSteps(1, key), 4, reason: 'written before the first part');
      await worker.emit(wallS: 3);
      ctrl.cancel();
      await f;
      expect(cache.partsHave(1, key), {0});
      expect(cache.partsSteps(1, key), 4);
    });

    test('steps follow the remembered t8 and the player\'s speed', () async {
      for (final (t8, rate, want) in [(0.73, 1.0, 8), (0.9, 1.0, 6), (1.82, 1.0, 4), (0.73, 1.5, 6), (0.9, 1.5, 4)]) {
        await prefs.setDouble(_t8Key, t8);
        final c = container();
        await c.read(playerProvider.notifier).setSpeed(rate);
        final ctrl = c.read(voicePrepareProvider(1).notifier);
        final f = ctrl.start(_poem(1), playWhenDone: false, artist: _artist);
        await _until(() => worker.open, what: 'the read');
        expect(worker.steps.last, want, reason: 't8 $t8 at ×$rate');
        ctrl.cancel();
        await f;
        await c.read(voiceCacheProvider)!.clear();
      }
    });

    test('phone.json\'s num_steps is the most a device uses', () async {
      final dir = Directory('${root.path}${_sep}v1');
      File('${dir.path}${_sep}phone.json').writeAsStringSync(
        jsonEncode({
          'sherpa': {'num_steps': 6},
        }),
      );
      await prefs.setDouble(_t8Key, 0.3); // fast enough for 8
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.steps, [6]);
      await worker.emitAll(7, wallS: 0.5);
      await f;
    });

    test('a resumed poem keeps the steps its parts were read with', () async {
      await prefs.setDouble(_t8Key, 0.3); // a fresh poem would use 8
      final c = container();
      final cache = c.read(voiceCacheProvider)!;
      final key = cache.keyOf(_poem(1), 'v1');
      for (var i = 0; i < 3; i++) {
        await cache.putBeyt(1, key, BeytAudio(i, FakeVoiceWorker.tone(seconds: 1), 24000));
      }
      await cache.setPartsSteps(1, key, 6);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.asked, [3, 4, 5, 6]);
      expect(worker.steps, [6]);
      expect(cache.partsSteps(1, key), 6);
      await worker.emitAll(4, wallS: 0.5);
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
    });

    for (final (name, content) in [
      ('no steps file', null),
      ('a garbage steps file', 'abc'),
      ('a steps file outside 8, 6, 4', '5'),
      ('a steps file above phone.json\'s', '12'),
    ]) {
      test('a resumed poem with $name reads with phone.json\'s steps', () async {
        await prefs.setDouble(_t8Key, 1.0); // a fresh poem would use 6
        final c = container();
        final cache = c.read(voiceCacheProvider)!;
        final key = cache.keyOf(_poem(1), 'v1');
        for (var i = 0; i < 3; i++) {
          await cache.putBeyt(1, key, BeytAudio(i, FakeVoiceWorker.tone(seconds: 1), 24000));
        }
        if (content != null) {
          File('${cache.root.path}$_sep${VoiceCache.partsName(1, key)}${_sep}steps').writeAsStringSync(content);
        }
        final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
        await _until(() => worker.open, what: 'the read');
        expect(worker.steps, [8]);
        expect(cache.partsSteps(1, key), 8, reason: 'rewritten before the next part');
        await worker.emitAll(4, wallS: 0.5);
        await f;
        expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      });
    }

    test('a parts folder with a steps file but no parts chooses afresh', () async {
      await prefs.setDouble(_t8Key, 0.3);
      final c = container();
      final cache = c.read(voiceCacheProvider)!;
      final key = cache.keyOf(_poem(1), 'v1');
      await cache.setPartsSteps(1, key, 4);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.steps, [8]);
      expect(cache.partsSteps(1, key), 8);
      await worker.emitAll(7, wallS: 0.5);
      await f;
    });

    test('the start rule uses the remembered speed at the poem\'s own steps', () async {
      // t8 1.0: 6 steps, at 1.29× real time, enough to start after beyt 0 of 7 equal beyts. At 8 steps (1.0×) it
      // would not be.
      await prefs.setDouble(_t8Key, 1.0);
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      expect(worker.steps, [6]);
      await worker.emit(wallS: 3);
      await _until(() => backend.playlists.isNotEmpty, what: 'the stream after beyt 0');
      await worker.emitAll(6, wallS: 0.5);
      await f;
    });
  });

  group('final fixes', () {
    _GatedCache gated() => _GatedCache(Directory('${cacheBase.path}${_sep}v1-quality'));

    test('a cancel while the write that would start the stream is in flight never starts it', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final cache = gated();
      final c = container(cache: cache);
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      final gate = cache.putGate = Completer<void>();
      await worker.emit(wallS: 3); // beyt 0: with the remembered speed, enough to start once on disk
      expect(c.read(voicePrepareProvider(1)), isA<Preparing>());
      ctrl.cancel();
      gate.complete();
      await f;
      await _settle();
      expect(backend.playlists, isEmpty);
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(c.read(playerProvider).status, PlayerStatus.idle);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
      expect(cache.partsHave(1, cache.keyOf(_poem(1), 'v1')), {0}, reason: 'the beyt still lands for a resume');
    });

    test('a cancel while the first item is being written never starts the stream', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final cache = gated();
      final c = container(cache: cache);
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final f = ctrl.start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      final gate = cache.itemGate = Completer<void>();
      await worker.emit(wallS: 3);
      await _until(() => cache.itemAsked, what: 'the first item');
      ctrl.cancel();
      gate.complete();
      await f;
      await _settle();
      expect(backend.playlists, isEmpty);
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(c.read(playerProvider).status, PlayerStatus.idle);
    });

    test('a failed join after every beyt was fed keeps the stream playing', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final cache = gated()..failJoin = true;
      final c = container(cache: cache);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.emitAll(6, wallS: 0.5);
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      await _settle();
      expect(backend.appended, hasLength(6));
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      expect(c.read(playerProvider).poem?.id, 1);
      expect(c.read(playerProvider).timeline.end, isNotNull);
    });

    test('a failed parts check after every beyt was fed keeps the stream playing', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final cache = gated();
      final c = container(cache: cache);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      cache.partsShort = true;
      await worker.emit(wallS: 3);
      await worker.emitAll(6, wallS: 0.5);
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      await _settle();
      expect(backend.appended, hasLength(6));
      expect(c.read(playerProvider.notifier).streaming, isTrue);
      expect(c.read(playerProvider).poem?.id, 1);
    });

    test('a human recitation started before the stream would start prevents streaming', () async {
      await prefs.setDouble(_t8Key, 4.0); // 4 steps at 0.45× real time: the rule waits a while
      final c = container();
      final poem = _poem(1);
      final f = c.read(voicePrepareProvider(1).notifier).start(poem, playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await _settle();
      expect(backend.playlists, isEmpty);
      final human = poem.recitations.first;
      await c.read(playerProvider.notifier).play(poem, human);
      await worker.emitAll(6, wallS: 0.25); // now fast enough to start, but the reader chose a human voice
      await f;
      await _settle();
      expect(backend.playlists, isEmpty);
      expect(backend.loaded, hasLength(1), reason: 'only the human recitation');
      expect(c.read(playerProvider).recitation?.id, human.id);
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
    });

    test('removing the voice mid-stream stops the player', () async {
      await prefs.setDouble(_t8Key, 0.5); // 8 steps at 2× real time
      final c = container();
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await _until(() => worker.open, what: 'the read');
      await worker.emit(wallS: 3);
      await worker.emit(wallS: 0.5);
      await _until(() => backend.appended.isNotEmpty, what: 'beyt 1 in the stream');
      await c.read(voiceProvider.notifier).remove();
      await f;
      expect(c.read(playerProvider.notifier).streaming, isFalse);
      expect(c.read(playerProvider).poem, isNull);
      expect(c.read(playerProvider).status, PlayerStatus.idle);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      await _settle();
      expect(backend.playlists, hasLength(1), reason: 'nothing starts again after the remove');
      expect(backend.loaded, isEmpty);
    });
  });
}
