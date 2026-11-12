import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/providers.dart' show sharedPrefsProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/features/player/audio_backend.dart' show PlaylistItem;
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/player/recitation_list.dart';
import 'package:ganj/features/player/unavailable_audio.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/settings/settings_screen.dart';
import 'package:ganj/features/voice/app/voice_downloader.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/app/voice_providers.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';
import 'fakes.dart';

final _sep = Platform.pathSeparator;

const _manifest = VoiceManifest(
  version: 'v1',
  files: [VoiceFile(name: 'model.onnx', size: 500 * 1024 * 1024, sha256: 'ab')],
);

Poem _poem({bool prose = false, int id = 7}) => Poem(
  id: id,
  title: 'غزل',
  fullTitle: 'غزل',
  fullUrl: '/x',
  plainText: '',
  verses: [
    Verse(vOrder: 1, position: prose ? VersePosition.paragraph : VersePosition.right, text: 'الف', coupletIndex: 0),
    Verse(vOrder: 2, position: prose ? VersePosition.paragraph : VersePosition.left, text: 'ب', coupletIndex: 0),
  ],
);

const _twoVariants = VoiceManifest(
  version: 'v1',
  files: [VoiceFile(name: 'shared.onnx', size: 100 * 1024 * 1024, sha256: 'ab')],
  variants: {
    kFastVariant: [VoiceFile(name: 'fast.onnx', size: 50 * 1024 * 1024, sha256: 'cd')],
    kQualityVariant: [VoiceFile(name: 'q.onnx', size: 300 * 1024 * 1024, sha256: 'ef')],
  },
);

/// A voice controller with a fixed state; records what the UI asks of it.
class _FakeVoice extends VoiceController {
  _FakeVoice(this.initial);

  final VoiceStatus initial;
  final calls = <String>[];
  VoiceManifest served = _manifest;

  @override
  VoiceStatus build() => initial;

  @override
  Future<VoiceManifest?> manifest() async {
    calls.add('manifest');
    return served;
  }

  @override
  Future<void> download(VoiceManifest m, {required String variant}) async =>
      calls.add('download ${m.version} $variant');

  @override
  void cancel() => calls.add('cancel');
}

/// A prepare controller with a fixed state; records the calls.
class _FakePrepare extends PrepareController {
  _FakePrepare(super.poemId, this.initial, this.calls);

  final PrepareStatus initial;
  final List<String> calls;

  @override
  PrepareStatus build() => initial;

  @override
  Future<void> start(Poem p, {required bool playWhenDone, required String artist}) async =>
      calls.add('start $playWhenDone $artist');

  @override
  void cancel() => calls.add('cancel');

  @override
  void quiet() => calls.add('quiet');
}

/// Records what screens ask of the running prepare.
class _FakePrepares implements VoicePrepares {
  _FakePrepares({this.runningPartsDir});

  final calls = <String>[];

  @override
  final String? runningPartsDir;

  @override
  Set<String> get keepParts => {?runningPartsDir};

  @override
  void quietExcept(int poemId) => calls.add('quietExcept $poemId');
}

void main() {
  late Directory tmp;
  late Directory root;
  late Directory cacheBase;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('voice_row_');
    root = Directory('${tmp.path}${_sep}voice')..createSync();
    cacheBase = Directory('${tmp.path}${_sep}voice-cache')..createSync();
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Still held for a moment on Windows.
    }
  });

  late _FakeVoice voice;
  final prepareCalls = <String>[];

  Future<ProviderContainer> pumpList(
    WidgetTester tester,
    Poem poem, {
    VoiceStatus status = const VoiceAbsent(),
    PrepareStatus prepare = const PrepareIdle(),
    bool audio = true,
    FakeAudioBackend? backend,
    VoiceManifest served = _manifest,
    Map<String, Object> prefValues = const {},
  }) async {
    prepareCalls.clear();
    voice = _FakeVoice(status)..served = served;
    final prefs = await mockPrefs(prefValues);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ListView(children: [RecitationList(poem: poem)]),
        ),
        prefs: prefs,
        repo: FixtureRepository(),
        backend: backend,
        overrides: [
          voiceRootProvider.overrideWithValue(root),
          voiceCacheBaseProvider.overrideWithValue(cacheBase),
          voiceProvider.overrideWith(() => voice),
          voicePrepareProvider(7).overrideWith(() => _FakePrepare(7, prepare, prepareCalls)),
          if (!audio) audioUnavailableProvider.overrideWithValue(AudioUnavailableReason.windowsN),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.headphones)); // expand the panel
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(RecitationList)));
  }

  group('voice row', () {
    testWidgets('row hidden on prose poem', (tester) async {
      await pumpList(tester, _poem(prose: true));
      expect(find.text('خوانش ماشینی'), findsNothing);
    });

    testWidgets('row hidden when audio cannot play on this computer', (tester) async {
      await pumpList(tester, _poem(), audio: false);
      expect(find.text('خوانش ماشینی'), findsNothing);
    });

    testWidgets('absent row opens consent with real size and downloads on accept', (tester) async {
      await pumpList(tester, _poem());
      expect(find.text('خوانش ماشینی'), findsOneWidget);
      expect(find.text('دریافت یک‌بارهٔ صدا'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pumpAndSettle();
      expect(voice.calls, ['manifest']);
      expect(find.textContaining('۵۰۰٫۰ م‌ب'), findsOneWidget);
      await tester.tap(find.text('دریافت'));
      await tester.pumpAndSettle();
      expect(voice.calls, ['manifest', 'download v1 quality']);
    });

    testWidgets('consent offers fast (default) and quality with sizes', (tester) async {
      await pumpList(tester, _poem(), served: _twoVariants);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pumpAndSettle();
      expect(find.text('سریع · ۱۵۰٫۰ م‌ب'), findsOneWidget);
      expect(find.text('باکیفیت · ۴۰۰٫۰ م‌ب'), findsOneWidget);
      expect(find.text('سریع‌تر روی بیشتر گوشی‌ها'), findsOneWidget);
      expect(find.text('صدای روشن‌تر؛ گوشی‌های کندتر بیشتر آماده می‌کنند'), findsOneWidget);
      // Each choice shows its size, so the body sentence carries none.
      expect(
        find.text('این صدا شعر را روی همین دستگاه می‌خواند. یک بار دریافت می‌شود و از تنظیمات پاک‌شدنی است.'),
        findsOneWidget,
      );
      expect(find.textContaining('م‌ب)'), findsNothing);
      await tester.tap(find.text('دریافت'));
      await tester.pumpAndSettle();
      expect(voice.calls, ['manifest', 'download v1 fast']);
    });

    testWidgets('choosing quality downloads quality', (tester) async {
      await pumpList(tester, _poem(), served: _twoVariants);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('باکیفیت ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('دریافت'));
      await tester.pumpAndSettle();
      expect(voice.calls, ['manifest', 'download v1 quality']);
    });

    testWidgets('single-variant manifest shows no choice', (tester) async {
      await pumpList(tester, _poem());
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.textContaining('سریع ·'), findsNothing);
      expect(find.textContaining('(۵۰۰٫۰ م‌ب)'), findsOneWidget, reason: 'with no choice, the body keeps the size');
    });

    testWidgets('declining consent downloads nothing', (tester) async {
      await pumpList(tester, _poem());
      await tester.tap(find.byKey(const ValueKey('voice-trailing')));
      await tester.pumpAndSettle();
      expect(find.text('انصراف'), findsOneWidget);
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      expect(voice.calls, ['manifest']);
    });

    testWidgets('a corrupt voice says so', (tester) async {
      await pumpList(tester, _poem(), status: const VoiceAbsent(wasCorrupt: true));
      expect(find.text('صدا خراب بود؛ دوباره دریافت کنید'), findsOneWidget);
    });

    testWidgets('downloading shows local-digit percent and cancels', (tester) async {
      await pumpList(tester, _poem(), status: const VoiceDownloading(25, 100));
      expect(find.text('دریافت صدا… ٪۲۵'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-trailing')));
      expect(voice.calls, ['cancel']);
    });

    testWidgets('failed offline offers a retry through consent', (tester) async {
      await pumpList(tester, _poem(), status: const VoiceFailed(VoiceDownloadFailure.offline));
      expect(find.text('دریافت نشد؛ اینترنت را بررسی کنید'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-trailing')));
      await tester.pumpAndSettle();
      expect(find.text('دریافت'), findsOneWidget);
    });

    testWidgets('ready row starts a prepare that plays when done', (tester) async {
      await pumpList(tester, _poem(), status: const VoiceReady('d', 'v1', 1, 'quality'));
      expect(find.text('صدای گنج، روی همین دستگاه'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, ['start true خوانش ماشینی']);
    });

    testWidgets('prepared but not current: a tap starts again (cache hit)', (tester) async {
      await pumpList(
        tester,
        _poem(),
        status: const VoiceReady('d', 'v1', 1, 'quality'),
        prepare: Prepared(File('x.wav'), const []),
      );
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, ['start true خوانش ماشینی']);
    });

    testWidgets('preparing shows count and cancel', (tester) async {
      await pumpList(
        tester,
        _poem(),
        status: const VoiceReady('d', 'v1', 1, 'quality'),
        prepare: const Preparing(3, 12),
      );
      expect(find.text('آماده‌سازی… ۳ از ۱۲ بیت'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-trailing')));
      expect(prepareCalls, ['cancel']);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      expect(prepareCalls, ['cancel', 'cancel']); // play cancels too while preparing (spec state table)
    });

    testWidgets('preparing while this poem streams: the row plays and toggles, with no cancel', (tester) async {
      final backend = FakeAudioBackend();
      final c = await pumpList(
        tester,
        _poem(),
        status: const VoiceReady('d', 'v1', 1, 'quality'),
        prepare: const Preparing(3, 12),
        backend: backend,
      );
      final token = c
          .read(playerProvider.notifier)
          .startVoiceStream(
            _poem(),
            artist: 'خوانش ماشینی',
            first: PlaylistItem(uri: Uri.file('0.wav'), duration: const Duration(seconds: 1)),
            firstVOrder: 1,
          );
      await tester.runAsync(() => token.started);
      await tester.pump();
      expect(c.read(playerProvider).playing, isTrue);
      expect(find.text('آماده‌سازی… ۳ از ۱۲ بیت'), findsOneWidget); // quiet secondary info
      expect(find.byKey(const ValueKey('voice-trailing')), findsNothing);
      expect(find.byIcon(Icons.pause_circle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, isEmpty);
      expect(c.read(playerProvider).playing, isFalse);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, isEmpty);
      expect(c.read(playerProvider).playing, isTrue);
    });

    testWidgets('prepare failure offers refresh', (tester) async {
      await pumpList(
        tester,
        _poem(),
        status: const VoiceReady('d', 'v1', 1, 'quality'),
        prepare: const PrepareFailed(),
      );
      expect(find.text('خواندن ممکن نشد'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-trailing')));
      await tester.pump();
      expect(prepareCalls, ['start true خوانش ماشینی']);
    });

    group('the improved line', () {
      Future<SharedPreferences> pumpNotice(WidgetTester tester, PrepareStatus prepare) async {
        final c = await pumpList(
          tester,
          _poem(),
          status: const VoiceReady('d', 'v1', 1, 'quality'),
          prepare: prepare,
          prefValues: {kVoiceImprovedNoticePref: '1.2.0'},
        );
        return c.read(sharedPrefsProvider);
      }

      testWidgets('replaces the plain subtitle before the poem is read', (tester) async {
        final prefs = await pumpNotice(tester, const PrepareIdle());
        expect(find.text('خوانش ماشینی بهتر شد'), findsOneWidget);
        expect(find.text('صدای گنج، روی همین دستگاه'), findsNothing);
        expect(prefs.getString(kVoiceImprovedNoticePref), '1.2.0', reason: 'not read yet: still to say');
      });

      testWidgets('stays after the swapped reading is prepared, across rebuilds', (tester) async {
        final prefs = await pumpNotice(tester, Prepared(File('x.wav'), const []));
        expect(find.text('خوانش ماشینی بهتر شد'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.headphones)); // collapse and open again: a fresh build
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.headphones));
        await tester.pumpAndSettle();
        expect(find.text('خوانش ماشینی بهتر شد'), findsOneWidget);
        expect(prefs.getString(kVoiceImprovedNoticePref), '1.2.0', reason: 'only the next reading spends it');
      });

      testWidgets('never hides progress, and progress does not spend it', (tester) async {
        final prefs = await pumpNotice(tester, const Preparing(2, 7));
        expect(find.text('آماده‌سازی… ۲ از ۷ بیت'), findsOneWidget);
        expect(find.text('خوانش ماشینی بهتر شد'), findsNothing);
        expect(prefs.getString(kVoiceImprovedNoticePref), '1.2.0');
      });

      testWidgets('a failed prepare shows its error, not the notice', (tester) async {
        await pumpNotice(tester, const PrepareFailed());
        expect(find.text('خواندن ممکن نشد'), findsOneWidget);
        expect(find.text('خوانش ماشینی بهتر شد'), findsNothing);
      });

      testWidgets('shows the plain line once spent', (tester) async {
        await pumpList(tester, _poem(), status: const VoiceReady('d', 'v1', 1, 'quality'));
        expect(find.text('صدای گنج، روی همین دستگاه'), findsOneWidget);
        expect(find.text('خوانش ماشینی بهتر شد'), findsNothing);
      });
    });

    testWidgets('the current voice toggles instead of preparing', (tester) async {
      final c = await pumpList(tester, _poem(), status: const VoiceReady('d', 'v1', 1, 'quality'));
      final poem = _poem();
      await tester.runAsync(
        () => c.read(playerProvider.notifier).playVoice(poem, File('v.wav'), const [
          SyncPoint(1, 0),
        ], artist: 'خوانش ماشینی'),
      );
      await tester.pump();
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      expect(c.read(playerProvider).playing, isTrue);
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, isEmpty);
      expect(c.read(playerProvider).playing, isFalse);
    });

    testWidgets('the current voice in error prepares again instead of retrying the (maybe gone) wav', (tester) async {
      final backend = FakeAudioBackend()..failLoad = const FileSystemException('gone');
      final c = await pumpList(tester, _poem(), status: const VoiceReady('d', 'v1', 1, 'quality'), backend: backend);
      await tester.runAsync(
        () => c.read(playerProvider.notifier).playVoice(_poem(), File('evicted.wav'), const [
          SyncPoint(1, 0),
        ], artist: 'خوانش ماشینی'),
      );
      await tester.pump();
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      expect(c.read(playerProvider).status, PlayerStatus.error);
      backend.failLoad = null;
      await tester.tap(find.byKey(const ValueKey('voice-play')));
      await tester.pump();
      expect(prepareCalls, ['start true خوانش ماشینی']);
      expect(backend.loaded, isEmpty); // no player.retry() of the old file
    });
  });

  group('poem page', () {
    late FixtureRepository repo;

    Future<ProviderContainer> openPoem(WidgetTester tester, {List<Recitation> recitations = const []}) async {
      prepareCalls.clear();
      voice = _FakeVoice(const VoiceReady('d', 'v1', 1, 'quality'));
      repo = FixtureRepository()..poems[7] = _poemWith(recitations);
      final prefs = await mockPrefs();
      await tester.pumpWidget(
        testApp(
          PoemScreen(id: 7),
          prefs: prefs,
          repo: repo,
          overrides: [
            voiceRootProvider.overrideWithValue(root),
            voiceCacheBaseProvider.overrideWithValue(cacheBase),
            voiceProvider.overrideWith(() => voice),
            voicePrepareProvider(7).overrideWith(() => _FakePrepare(7, const PrepareIdle(), prepareCalls)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
    }

    testWidgets('panel shows on a verse poem with no human recitations', (tester) async {
      await openPoem(tester);
      expect(find.text('خوانش‌ها (۱)'), findsOneWidget);
    });

    testWidgets('the header count includes the voice row', (tester) async {
      await openPoem(tester, recitations: _humans());
      expect(find.text('خوانش‌ها (۳)'), findsOneWidget);
    });

    testWidgets('opening a poem quiets any other poem\'s running prepare', (tester) async {
      final prepares = _FakePrepares();
      prepareCalls.clear();
      voice = _FakeVoice(const VoiceReady('d', 'v1', 1, 'quality'));
      repo = FixtureRepository()..poems[7] = _poemWith(const []);
      final prefs = await mockPrefs();
      await tester.pumpWidget(
        testApp(
          PoemScreen(id: 7),
          prefs: prefs,
          repo: repo,
          overrides: [
            voiceRootProvider.overrideWithValue(root),
            voiceCacheBaseProvider.overrideWithValue(cacheBase),
            voiceProvider.overrideWith(() => voice),
            voicePrepareProvider(7).overrideWith(() => _FakePrepare(7, const PrepareIdle(), prepareCalls)),
            voicePreparesProvider.overrideWithValue(prepares),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(prepares.calls, ['quietExcept 7']);
    });

    testWidgets('leaving the poem page quiets its prepare', (tester) async {
      await openPoem(tester);
      expect(prepareCalls, isNot(contains('quiet')));
      await tester.pumpWidget(const SizedBox());
      expect(prepareCalls, contains('quiet'));
    });
  });

  group('settings', () {
    Future<ProviderContainer> pumpSettings(
      WidgetTester tester, {
      bool installed = true,
      int partialBytes = 0,
      String variant = kQualityVariant,
      VoicePrepares? prepares,
    }) async {
      final prefs = await mockPrefs();
      if (partialBytes > 0) {
        final d = Directory('${root.path}${_sep}v1')..createSync();
        File('${d.path}${_sep}model.onnx.part').writeAsBytesSync(List.filled(partialBytes, 1));
      }
      if (installed) {
        final d = Directory('${root.path}${_sep}v1')..createSync();
        File('${d.path}${_sep}installed.json')
            .writeAsStringSync(jsonEncode({..._manifest.toJson(), 'variant': variant}));
        File('${d.path}${_sep}model.onnx').writeAsBytesSync([1, 2, 3]);
        final cache = Directory('${cacheBase.path}${_sep}v1-quality')..createSync(recursive: true);
        File('${cache.path}${_sep}7-k.wav').writeAsBytesSync(List.filled(2048, 1));
      }
      await tester.pumpWidget(
        testApp(
          const SettingsScreen(),
          prefs: prefs,
          backend: FakeAudioBackend(),
          overrides: [
            voiceRootProvider.overrideWithValue(root),
            voiceCacheBaseProvider.overrideWithValue(cacheBase),
            voiceWorkerProvider.overrideWithValue(FakeVoiceWorker()),
            if (prepares != null) voicePreparesProvider.overrideWithValue(prepares),
          ],
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pumpAndSettle();
      }
      return ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    }

    Future<void> reveal(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('settings row names the installed variant', (tester) async {
      await pumpSettings(tester, variant: kFastVariant);
      await reveal(tester, find.byKey(const ValueKey('voice-remove')));
      expect(find.textContaining('پاک کردن صدای گنج — سریع ('), findsOneWidget);
    });

    testWidgets('settings row has the plain label for the quality voice', (tester) async {
      await pumpSettings(tester);
      await reveal(tester, find.byKey(const ValueKey('voice-remove')));
      expect(find.textContaining('پاک کردن صدای گنج ('), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('no remove row without a voice', (tester) async {
      await pumpSettings(tester, installed: false);
      expect(find.byKey(const ValueKey('voice-remove')), findsNothing);
    });

    testWidgets('a partial download shows the remove row with its real size, and remove deletes it', (tester) async {
      final c = await pumpSettings(tester, installed: false, partialBytes: 4096);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      final row = find.byKey(const ValueKey('voice-remove'));
      await reveal(tester, row);
      expect(find.textContaining('۴ ک‌ب'), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }
      expect(root.listSync(recursive: true), isEmpty);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(find.byKey(const ValueKey('voice-remove')), findsNothing);
    });

    testWidgets('clear cache spares the running prepare\'s parts folder', (tester) async {
      final parts = Directory('${cacheBase.path}${_sep}v1-quality${_sep}7-k.parts')..createSync(recursive: true);
      File('${parts.path}${_sep}0.pcm').writeAsBytesSync([1, 2]);
      await pumpSettings(tester, prepares: _FakePrepares(runningPartsDir: '7-k.parts'));
      final wav = File('${cacheBase.path}${_sep}v1-quality${_sep}7-k.wav');
      final clear = find.text('پاک‌کردن حافظهٔ موقت');
      await reveal(tester, clear);
      await tester.tap(clear);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pumpAndSettle();
      }
      expect(wav.existsSync(), isFalse);
      expect(File('${parts.path}${_sep}0.pcm').existsSync(), isTrue);
    });

    testWidgets('remove stops worker and voice playback', (tester) async {
      final c = await pumpSettings(tester);
      final worker = c.read(voiceWorkerProvider)! as FakeVoiceWorker;
      await tester.runAsync(
        () => c.read(playerProvider.notifier).playVoice(_poem(), File('v.wav'), const [
          SyncPoint(1, 0),
        ], artist: 'خوانش ماشینی'),
      );
      expect(c.read(playerProvider).recitation?.id, kVoiceRecitationId);
      final row = find.byKey(const ValueKey('voice-remove'));
      await reveal(tester, row);
      expect(find.textContaining('پاک کردن صدای گنج'), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }
      expect(c.read(playerProvider).status, PlayerStatus.idle);
      expect(c.read(playerProvider).recitation, isNull);
      expect(worker.disposed, isTrue);
      expect(Directory('${root.path}${_sep}v1').existsSync(), isFalse);
      expect(c.read(voiceProvider), isA<VoiceAbsent>());
      expect(find.byKey(const ValueKey('voice-remove')), findsNothing);
    });

    testWidgets('declining the confirm keeps the voice', (tester) async {
      final c = await pumpSettings(tester);
      final row = find.byKey(const ValueKey('voice-remove'));
      await reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      expect(c.read(voiceProvider), isA<VoiceReady>());
      expect(Directory('${root.path}${_sep}v1').existsSync(), isTrue);
    });

    testWidgets('clear cache also clears voice cache', (tester) async {
      await pumpSettings(tester);
      final file = File('${cacheBase.path}${_sep}v1-quality${_sep}7-k.wav');
      expect(file.existsSync(), isTrue);
      final clear = find.text('پاک‌کردن حافظهٔ موقت');
      await reveal(tester, clear);
      await tester.tap(clear);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pumpAndSettle();
      }
      expect(file.existsSync(), isFalse);
      expect(Directory('${root.path}${_sep}v1').existsSync(), isTrue); // the voice itself stays
    });

    testWidgets('cache size includes the voice cache', (tester) async {
      await pumpSettings(tester);
      // 2 KB of readings, nothing in api_cache.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await reveal(tester, find.text('حافظهٔ موقت صفحه‌های خوانده‌شده'));
      expect(find.text('۲ ک‌ب'), findsOneWidget);
    });
  });
}

Poem _poemWith(List<Recitation> r) =>
    Poem(id: 7, title: 'غزل', fullTitle: 'غزل', fullUrl: '/x', plainText: '', verses: _poem().verses, recitations: r);

List<Recitation> _humans() => [
  for (final i in [1, 2])
    Recitation(
      id: i,
      poemId: 7,
      artist: 'خواننده $i',
      title: 'خوانش',
      artistUrl: '',
      mp3Url: 'https://x/$i.mp3',
      mp3Size: 1,
      audioOrder: i,
      inSync: false,
    ),
];
