import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/voice/app/voice_cache.dart';
import 'package:ganj/features/voice/app/voice_downloader.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/app/voice_providers.dart';
import 'package:ganj/features/voice/app/voice_worker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';
import 'fakes.dart';

const _artist = 'خوانش ماشینی';
final _sep = Platform.pathSeparator;

const _manifest = VoiceManifest(
  version: 'v1',
  files: [VoiceFile(name: 'model.onnx', size: 100, sha256: 'ab')],
);

/// Two beyts (vOrders 1–4).
Poem _poem(int id, {List<Verse>? verses}) => Poem(
  id: id,
  title: 'p$id',
  fullTitle: 'p$id',
  fullUrl: '/p$id',
  plainText: '',
  metre: 'm',
  recitations: poem2130().recitations,
  verses:
      verses ??
      [
        Verse(vOrder: 1, position: VersePosition.right, text: 'a1 $id', coupletIndex: 0),
        Verse(vOrder: 2, position: VersePosition.left, text: 'a2 $id', coupletIndex: 0),
        Verse(vOrder: 3, position: VersePosition.right, text: 'b1 $id', coupletIndex: 1),
        Verse(vOrder: 4, position: VersePosition.left, text: 'b2 $id', coupletIndex: 1),
      ],
);

/// Writes an installed voice `<root>/v1` with `installed.json`.
/// With [variant], installs like phase 2 into `<root>/<version>-<variant>`; without, a phase 1 `<root>/<version>`.
void _install(Directory root, [VoiceManifest m = _manifest, String? variant]) {
  final d = Directory('${root.path}$_sep${m.version}${variant == null ? '' : '-$variant'}')
    ..createSync(recursive: true);
  File('${d.path}${_sep}model.onnx').writeAsBytesSync(List.filled(100, 1));
  final files = variant == null ? m.files : m.filesFor(variant);
  final j = <String, dynamic>{
    'version': m.version,
    'files': [for (final f in files) f.toJson()],
    'variant': ?variant,
  };
  File('${d.path}${_sep}installed.json').writeAsStringSync(jsonEncode(j));
}

class _FakeDownloader implements VoiceDownloader {
  _FakeDownloader(this.root, {this.fail, this.manifest = _manifest});

  final Directory root;
  final VoiceDownloadFailure? fail;
  final VoiceManifest manifest;
  String? lastVariant;

  @override
  Future<VoiceManifest> fetchManifest() async => manifest;

  @override
  Future<String> install(
    VoiceManifest m, {
    required String variant,
    void Function(int got, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    lastVariant = variant;
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(40, m.sizeOf(variant));
    await Future<void>.delayed(Duration.zero);
    if (fail != null) throw VoiceDownloadError(fail!);
    onProgress?.call(m.sizeOf(variant), m.sizeOf(variant));
    _install(root, m, variant);
    return 'github';
  }
}

/// Leaves a partial file in `<root>/v1`, then fails or (with [untilCancelled]) waits for the cancel and, like a
/// write still in flight, touches the partial file once more before it stops.
class _PartialDownloader implements VoiceDownloader {
  _PartialDownloader(this.root, {this.untilCancelled = false});

  final Directory root;
  final bool untilCancelled;
  final started = Completer<void>();

  File get part => File('${root.path}${_sep}v1${_sep}model.onnx.part');

  @override
  Future<VoiceManifest> fetchManifest() async => _manifest;

  @override
  Future<String> install(
    VoiceManifest m, {
    required String variant,
    void Function(int got, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    part.parent.createSync(recursive: true);
    part.writeAsBytesSync(List.filled(40, 1));
    onProgress?.call(40, m.totalBytes);
    started.complete();
    if (!untilCancelled) {
      throw const VoiceDownloadError(VoiceDownloadFailure.offline);
    }
    while (!(cancel?.isCancelled ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    part.parent.createSync(recursive: true); // like install's dir.create before the next file
    part.writeAsBytesSync(List.filled(10, 2), mode: FileMode.append);
    throw const VoiceDownloadError(VoiceDownloadFailure.cancelled);
  }
}

void main() {
  late Directory tmp;
  late Directory root;
  late Directory cacheBase;
  late FakeAudioBackend backend;
  late SharedPreferences prefs;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('voice_providers_');
    root = Directory('${tmp.path}${_sep}voice')..createSync();
    cacheBase = Directory('${tmp.path}${_sep}voice-cache');
    // Phase 1's prepare-then-play: a platform without playlists (streaming is covered in voice_stream_test).
    backend = FakeAudioBackend()..playlistSupported = false;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file for a moment.
    }
  });

  ProviderContainer container({VoiceWorker? worker, VoiceDownloader? downloader}) {
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        audioBackendProvider.overrideWithValue(backend),
        poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
        voiceRootProvider.overrideWithValue(root),
        voiceCacheBaseProvider.overrideWithValue(cacheBase),
        if (worker != null) voiceWorkerProvider.overrideWithValue(worker),
        if (downloader != null) voiceDownloaderProvider.overrideWithValue(downloader),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Completes once poem [id]'s prepare has stored [done] beyts.
  Future<void> untilPrepared(ProviderContainer c, int id, int done) {
    final got = Completer<void>();
    final sub = c.listen(voicePrepareProvider(id), (_, s) {
      if (s is Preparing && s.done >= done && !got.isCompleted) got.complete();
    });
    return got.future.whenComplete(sub.close);
  }

  bool playedVoice() => backend.loaded.any((u) => u.path.endsWith('.wav'));

  group('VoiceController', () {
    test('starts Ready when a voice is installed, Absent otherwise', () {
      expect(container().read(voiceProvider), isA<VoiceAbsent>());
      _install(root);
      final s = container().read(voiceProvider);
      expect(s, isA<VoiceReady>());
      s as VoiceReady;
      expect(s.version, 'v1');
      expect(s.bytes, 100);
      expect(s.dir, '${root.path}${_sep}v1');
    });

    test('download success goes Absent → Downloading → Ready', () async {
      final c = container(downloader: _FakeDownloader(root));
      final states = <VoiceStatus>[];
      c.listen(voiceProvider, (_, s) => states.add(s), fireImmediately: true);
      final m = await c.read(voiceProvider.notifier).manifest();
      expect(m!.version, 'v1');
      await c.read(voiceProvider.notifier).download(m, variant: 'quality');
      expect(states.first, isA<VoiceAbsent>());
      expect(states.whereType<VoiceDownloading>().map((s) => s.got), containsAllInOrder([40, 100]));
      expect(states.last, isA<VoiceReady>());
      expect((states.last as VoiceReady).version, 'v1');
      final firstReady = states.indexWhere((s) => s is VoiceReady);
      expect(states.indexWhere((s) => s is VoiceDownloading), lessThan(firstReady));
      expect(prefs.getString('voice.source'), 'github');
    });

    test('controller download passes the variant; VoiceReady.variant set', () async {
      const m2 = VoiceManifest(
        version: 'v2',
        files: [VoiceFile(name: 'shared.bin', size: 10, sha256: 'ab')],
        variants: {
          'fast': [VoiceFile(name: 'f.bin', size: 5, sha256: 'ab')],
          'quality': [VoiceFile(name: 'q.bin', size: 20, sha256: 'ab')],
        },
      );
      final dl = _FakeDownloader(root, manifest: m2);
      final c = container(downloader: dl);
      final states = <VoiceStatus>[];
      c.listen(voiceProvider, (_, s) => states.add(s));
      await c.read(voiceProvider.notifier).download(m2, variant: 'fast');
      expect(dl.lastVariant, 'fast');
      expect(states.whereType<VoiceDownloading>().last.total, 15);
      final s = c.read(voiceProvider) as VoiceReady;
      expect(s.variant, 'fast');
      expect(s.version, 'v2');
      expect(s.bytes, 15);
      expect(s.dir, '${root.path}${_sep}v2-fast');
    });

    test('phase-1 folder reads as quality; cache folder is per version-variant', () {
      _install(root);
      final c = container();
      expect((c.read(voiceProvider) as VoiceReady).variant, 'quality');
      expect(c.read(voiceCacheProvider)!.root.path, '${cacheBase.path}${_sep}v1-quality');
    });

    test('installing the other variant replaces the folder and the readings of the first', () async {
      const m2 = VoiceManifest(
        version: 'v2',
        files: [VoiceFile(name: 'shared.bin', size: 10, sha256: 'ab')],
        variants: {
          'fast': [VoiceFile(name: 'f.bin', size: 5, sha256: 'ab')],
          'quality': [VoiceFile(name: 'q.bin', size: 20, sha256: 'ab')],
        },
      );
      _install(root, m2, 'quality');
      Directory('${cacheBase.path}${_sep}v2-quality').createSync(recursive: true);
      File('${cacheBase.path}${_sep}v2-quality${_sep}1-a.wav').writeAsBytesSync([1]);
      final c = container(downloader: _FakeDownloader(root, manifest: m2));
      expect((c.read(voiceProvider) as VoiceReady).variant, 'quality');
      await c.read(voiceProvider.notifier).download(m2, variant: 'fast');
      expect((c.read(voiceProvider) as VoiceReady).variant, 'fast');
      expect(root.listSync().map((e) => e.path.split(_sep).last), ['v2-fast']);
      expect(cacheBase.listSync(), isEmpty);
      expect(c.read(voiceCacheProvider)!.root.path, '${cacheBase.path}${_sep}v2-fast');
    });

    const sw = VoiceManifest(
      version: 'v2',
      files: [VoiceFile(name: 'shared.bin', size: 10, sha256: 'ab')],
      variants: {
        'fast': [VoiceFile(name: 'f.bin', size: 5, sha256: 'ab')],
        'quality': [VoiceFile(name: 'q.bin', size: 20, sha256: 'ab')],
      },
    );

    test('a failed switch keeps the old voice Ready and flags the failure', () async {
      _install(root, sw, 'quality');
      Directory('${cacheBase.path}${_sep}v2-quality').createSync(recursive: true);
      File('${cacheBase.path}${_sep}v2-quality${_sep}1-a.wav').writeAsBytesSync([1]);
      final c = container(
        downloader: _FakeDownloader(root, manifest: sw, fail: VoiceDownloadFailure.offline),
      );
      await c.read(voiceProvider.notifier).download(sw, variant: 'fast');
      final s = c.read(voiceProvider);
      expect(s, isA<VoiceReady>());
      s as VoiceReady;
      expect(s.variant, 'quality');
      expect(s.lastSwitchFailed, isTrue);
      expect(File('${root.path}${_sep}v2-quality${_sep}installed.json').existsSync(), isTrue);
      expect(File('${cacheBase.path}${_sep}v2-quality${_sep}1-a.wav').existsSync(), isTrue);
      expect(c.read(voiceCacheProvider)!.root.path, '${cacheBase.path}${_sep}v2-quality');
    });

    test('a cancelled switch keeps the old voice Ready without a failure flag', () async {
      _install(root, sw, 'quality');
      Directory('${cacheBase.path}${_sep}v2-quality').createSync(recursive: true);
      File('${cacheBase.path}${_sep}v2-quality${_sep}1-a.wav').writeAsBytesSync([1]);
      final dl = _PartialDownloader(root, untilCancelled: true);
      final c = container(downloader: dl);
      final f = c.read(voiceProvider.notifier).download(sw, variant: 'fast');
      await dl.started.future;
      c.read(voiceProvider.notifier).cancel();
      await f;
      final s = c.read(voiceProvider);
      expect(s, isA<VoiceReady>());
      s as VoiceReady;
      expect(s.variant, 'quality');
      expect(s.lastSwitchFailed, isFalse);
      expect(File('${root.path}${_sep}v2-quality${_sep}installed.json').existsSync(), isTrue);
      expect(File('${cacheBase.path}${_sep}v2-quality${_sep}1-a.wav').existsSync(), isTrue);
    });

    test('with no old voice a failure is still Failed', () async {
      final c = container(
        downloader: _FakeDownloader(root, manifest: sw, fail: VoiceDownloadFailure.offline),
      );
      await c.read(voiceProvider.notifier).download(sw, variant: 'fast');
      expect(c.read(voiceProvider), isA<VoiceFailed>());
    });

    test('building with a Ready voice deletes cache folders of other versions and variants', () async {
      _install(root, sw, 'quality');
      for (final n in ['v2-quality', 'v2-fast', 'v1']) {
        Directory('${cacheBase.path}$_sep$n').createSync(recursive: true);
        File('${cacheBase.path}$_sep$n${_sep}x.wav').writeAsBytesSync([1]);
      }
      final c = container();
      expect(c.read(voiceProvider), isA<VoiceReady>());
      for (var i = 0; i < 50 && cacheBase.listSync().length > 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(cacheBase.listSync().map((e) => e.path.split(_sep).last), ['v2-quality']);
    });

    test('download noSpace shows Failed(noSpace)', () async {
      final c = container(downloader: _FakeDownloader(root, fail: VoiceDownloadFailure.noSpace));
      await c.read(voiceProvider.notifier).download(_manifest, variant: 'quality');
      final s = c.read(voiceProvider);
      expect(s, isA<VoiceFailed>());
      expect((s as VoiceFailed).kind, VoiceDownloadFailure.noSpace);
      expect(prefs.getString('voice.source'), isNull);
    });

    test('remove stops worker and voice playback', () async {
      _install(root);
      final worker = FakeVoiceWorker();
      final c = container(worker: worker);
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      expect(backend.isPlaying, isTrue);
      final cache = c.read(voiceCacheProvider)!;
      expect(await cache.sizeBytes(), greaterThan(0));

      await c.read(voiceProvider.notifier).remove();

      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect((c.read(voiceProvider) as VoiceAbsent).wasCorrupt, isFalse);
      expect(c.read(playerProvider).status, PlayerStatus.idle);
      expect(c.read(playerProvider).recitation, isNull);
      expect(backend.isPlaying, isFalse);
      expect(worker.disposed, isTrue);
      expect(Directory('${root.path}${_sep}v1').existsSync(), isFalse);
      expect(installedDir(root), isNull);
      expect(await cache.sizeBytes(), 0);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
    });

    test('remove during a running prepare cancels it and never plays', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 30));
      final c = container(worker: worker);
      final firstBeyt = untilPrepared(c, 1, 1);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await firstBeyt;
      await c.read(voiceProvider.notifier).remove();
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 120)); // past the fake's remaining beyt
      expect(playedVoice(), isFalse);
      expect(backend.loaded, isEmpty);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
      expect(worker.disposed, isTrue);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(Directory('${root.path}${_sep}v1').existsSync(), isFalse);
      final leftover = cacheBase.existsSync()
          ? cacheBase.listSync(recursive: true).whereType<File>().toList()
          : const <File>[];
      expect(leftover, isEmpty);
    });

    test('a new version download deletes the old voice and its readings', () async {
      const old = VoiceManifest(
        version: 'v0',
        files: [VoiceFile(name: 'model.onnx', size: 100, sha256: 'ab')],
      );
      _install(root, old);
      Directory('${cacheBase.path}${_sep}v0-quality').createSync(recursive: true);
      File('${cacheBase.path}${_sep}v0-quality${_sep}7-abc.wav').writeAsBytesSync([1, 2, 3]);
      final c = container(downloader: _FakeDownloader(root));
      expect((c.read(voiceProvider) as VoiceReady).version, 'v0');
      await Future<void>.delayed(const Duration(milliseconds: 50)); // startup pruning of stray caches is done
      Directory('${cacheBase.path}${_sep}v1-quality').createSync(recursive: true);
      File('${cacheBase.path}${_sep}v1-quality${_sep}keep.wav').writeAsBytesSync([1]);
      await c.read(voiceProvider.notifier).download(_manifest, variant: 'quality');
      expect((c.read(voiceProvider) as VoiceReady).version, 'v1');
      expect(Directory('${root.path}${_sep}v0').existsSync(), isFalse);
      expect(cacheBase.listSync().map((e) => e.path.split(_sep).last), ['v1-quality']);
      expect(File('${cacheBase.path}${_sep}v1-quality${_sep}keep.wav').existsSync(), isTrue);
    });

    test('remove from VoiceFailed deletes the partial files', () async {
      final dl = _PartialDownloader(root);
      final c = container(downloader: dl);
      await c.read(voiceProvider.notifier).download(_manifest, variant: 'quality');
      expect(c.read(voiceProvider), isA<VoiceFailed>());
      expect(dl.part.existsSync(), isTrue);
      expect(voiceRootBytes(root), 40);

      await c.read(voiceProvider.notifier).remove();

      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(root.existsSync() ? root.listSync(recursive: true) : const [], isEmpty);
      expect(voiceRootBytes(root), 0);
    });

    test('remove from VoiceAbsent deletes partial files left by a cancelled download', () async {
      Directory('${root.path}${_sep}v1').createSync();
      File('${root.path}${_sep}v1${_sep}model.onnx.part').writeAsBytesSync(List.filled(30, 1));
      final c = container();
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      await c.read(voiceProvider.notifier).remove();
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(root.existsSync() ? root.listSync(recursive: true) : const [], isEmpty);
    });

    test('remove while downloading cancels the download and waits for it to stop', () async {
      final dl = _PartialDownloader(root, untilCancelled: true);
      final c = container(downloader: dl);
      final f = c.read(voiceProvider.notifier).download(_manifest, variant: 'quality');
      await dl.started.future;
      expect(c.read(voiceProvider), isA<VoiceDownloading>());

      await c.read(voiceProvider.notifier).remove();

      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(root.existsSync() ? root.listSync(recursive: true) : const [], isEmpty);
      await f;
      // Nothing the download still had in flight lands after the delete.
      expect(root.existsSync() ? root.listSync(recursive: true) : const [], isEmpty);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
    });

    test('remove and markCorrupt work with the real worker provider', () async {
      _install(root);
      final c = container();
      expect(c.read(voiceWorkerProvider), isA<IsolateVoiceWorker>());
      await c.read(voiceProvider.notifier).remove();
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(c.read(voiceWorkerProvider), isNull);
      expect(c.read(voiceCacheProvider), isNull);

      _install(root);
      final c2 = container();
      expect(c2.read(voiceWorkerProvider), isNotNull);
      await c2.read(voiceProvider.notifier).markCorrupt();
      expect((c2.read(voiceProvider) as VoiceAbsent).wasCorrupt, isTrue);
      expect(c2.read(voiceWorkerProvider), isNull);
      expect(installedDir(root), isNull);
    });
  });

  group('PrepareController', () {
    test('prepare reads, joins and plays', () async {
      _install(root);
      final worker = FakeVoiceWorker();
      final c = container(worker: worker);
      final states = <PrepareStatus>[];
      c.listen(voicePrepareProvider(1), (_, s) => states.add(s));
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      final s = c.read(voicePrepareProvider(1));
      expect(s, isA<Prepared>());
      s as Prepared;
      expect(s.wav.existsSync(), isTrue);
      expect(s.sync.map((p) => p.vOrder), [1, 3, -2]);
      expect(states.whereType<Preparing>(), isNotEmpty);
      expect(worker.requested, [0, 1]);
      expect(backend.loaded.single.path, endsWith('.wav'));
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      expect(c.read(playerProvider).recitation?.artist, _artist);
    });

    test('the worker receives the chosen steps', () async {
      _install(root);
      final worker = FakeVoiceWorker();
      final c = container(worker: worker);
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      expect(worker.stepsAsked, [4], reason: 'no measurement yet');
      await prefs.setDouble('voice.t8.v1', 0.9);
      await c.read(voicePrepareProvider(2).notifier).start(_poem(2), playWhenDone: false, artist: _artist);
      expect(worker.stepsAsked, [4, 6]);
    });

    test('prepare without playWhenDone does not play', () async {
      _install(root);
      final c = container(worker: FakeVoiceWorker());
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(backend.loaded, isEmpty);
    });

    test('a new prepare cancels the old one and it never plays', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 30));
      final c = container(worker: worker);
      final firstBeyt = untilPrepared(c, 1, 1);
      final a = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      await firstBeyt;
      final b = c.read(voicePrepareProvider(2).notifier).start(_poem(2), playWhenDone: true, artist: _artist);
      await Future.wait([a, b]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(voicePrepareProvider(1)), isNot(isA<Prepared>()));
      expect(c.read(voicePrepareProvider(2)), isA<Prepared>());
      expect(backend.loaded, hasLength(1));
      expect(c.read(playerProvider).poem?.id, 2);
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
    });

    test('quiet keeps preparing but never plays', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 20));
      final c = container(worker: worker);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      c.read(voicePrepareProvider(1).notifier).quiet();
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(worker.requested, [0, 1]);
      expect(playedVoice(), isFalse);
      expect(backend.loaded, isEmpty);
    });

    test('quiet on another poem does not affect the running one', () async {
      _install(root);
      final c = container(worker: FakeVoiceWorker(delay: const Duration(milliseconds: 20)));
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      c.read(voicePrepareProvider(2).notifier).quiet();
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(playedVoice(), isTrue);
      expect(c.read(playerProvider).poem?.id, 1);
    });

    test('opening another poem quiets the running prepare: it finishes but never plays', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 20));
      final c = container(worker: worker);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      c.read(voicePreparesProvider).quietExcept(2); // what PoemScreen(2).initState does
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(worker.requested, [0, 1]);
      expect(playedVoice(), isFalse);
    });

    test('opening the same poem again leaves its prepare free to play', () async {
      _install(root);
      final c = container(worker: FakeVoiceWorker(delay: const Duration(milliseconds: 20)));
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      c.read(voicePreparesProvider).quietExcept(1);
      await f;
      expect(playedVoice(), isTrue);
      expect(c.read(playerProvider).poem?.id, 1);
    });

    test('quietExcept with nothing running is harmless', () {
      final c = container(worker: FakeVoiceWorker());
      c.read(voicePreparesProvider).quietExcept(5);
      expect(c.read(voicePreparesProvider).runningPartsDir, isNull);
    });

    test('runningPartsDir names the running prepare\'s parts folder', () async {
      _install(root);
      final c = container(worker: FakeVoiceWorker(delay: const Duration(milliseconds: 30)));
      final firstBeyt = untilPrepared(c, 1, 1);
      final f = c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      await firstBeyt;
      final cache = c.read(voiceCacheProvider)!;
      final name = c.read(voicePreparesProvider).runningPartsDir;
      expect(name, '1-${cache.keyOf(_poem(1), 'v1')}.parts');
      final parts = Directory('${cache.root.path}$_sep$name');
      for (var i = 0; i < 100 && !parts.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2)); // the first part's write lands
      }
      expect(parts.existsSync(), isTrue);
      // Clearing the cache meanwhile spares it, so the prepare can still join.
      await cache.clear(keep: {name!});
      await f;
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(c.read(voicePreparesProvider).runningPartsDir, isNull);
    });

    test('a cancelled prepare resumes with only the missing beyts', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 30));
      final c = container(worker: worker);
      final ctrl = c.read(voicePrepareProvider(1).notifier);
      final firstBeyt = untilPrepared(c, 1, 1);
      final a = ctrl.start(_poem(1), playWhenDone: false, artist: _artist);
      await firstBeyt;
      ctrl.cancel();
      await a;
      expect(c.read(voicePrepareProvider(1)), isA<PrepareIdle>());
      expect(worker.requested, [0]);
      await ctrl.start(_poem(1), playWhenDone: false, artist: _artist);
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(worker.requested, [0, 1]);
    });

    test('prepare does not autoplay after the reader started a human recitation', () async {
      _install(root);
      final worker = FakeVoiceWorker(delay: const Duration(milliseconds: 20));
      final c = container(worker: worker);
      final poem = _poem(1);
      final human = poem.recitations.first;
      final f = c.read(voicePrepareProvider(1).notifier).start(poem, playWhenDone: true, artist: _artist);
      await c.read(playerProvider.notifier).play(poem, human);
      await f;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(voicePrepareProvider(1)), isA<Prepared>());
      expect(c.read(playerProvider).recitation?.id, human.id);
      expect(playedVoice(), isFalse);
    });

    test('cache hit is Prepared immediately', () async {
      _install(root);
      final worker = FakeVoiceWorker();
      final c = container(worker: worker);
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      final c2 = container(worker: worker);
      final f = c2.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      // Synchronously, before any await.
      expect(c2.read(voicePrepareProvider(1)), isA<Prepared>());
      await f;
      expect(worker.requested, [0, 1]);
    });

    test('read error puts silence for that beyt and carries on', () async {
      _install(root);
      final worker = FakeVoiceWorker(failOn: 0);
      final c = container(worker: worker);
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: false, artist: _artist);
      final s = c.read(voicePrepareProvider(1));
      expect(s, isA<Prepared>());
      s as Prepared;
      // Beyt 0 is 500 ms of silence, then the 250 ms gap: beyt 1 starts at 750 ms.
      expect(s.sync[1].vOrder, 3);
      expect(s.sync[1].ms, (kBeytGap * 2 + kBeytGap).inMilliseconds);
    });

    test('engine load error marks voice corrupt', () async {
      _install(root);
      final c = container(worker: FakeVoiceWorker(failLoad: true));
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      final v = c.read(voiceProvider);
      expect(v, isA<VoiceAbsent>());
      expect((v as VoiceAbsent).wasCorrupt, isTrue);
      expect(Directory('${root.path}${_sep}v1').existsSync(), isFalse);
      expect(backend.loaded, isEmpty);
    });

    test('worker died fails the prepare but keeps the voice', () async {
      _install(root);
      final c = container(worker: _DyingWorker());
      await c.read(voicePrepareProvider(1).notifier).start(_poem(1), playWhenDone: true, artist: _artist);
      expect(c.read(voicePrepareProvider(1)), isA<PrepareFailed>());
      expect(c.read(voiceProvider), isA<VoiceReady>());
      expect(installedDir(root), isNotNull);
    });
  });
}

class _DyingWorker implements VoiceWorker {
  @override
  Stream<BeytAudio> read(List<BeytRequest> beyts, {String? metre, int? steps}) =>
      Stream.error(const VoiceWorkerDied('crash'));

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}
}
