import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/core/net/api_client.dart' show kUserAgent;
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/voice/app/voice_downloader.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/app/voice_providers.dart';
import 'package:ganj/router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live check of the background upgrade: a voice installed from an old server, then the manifest of a newer one
/// (only the G2P files changed) staged by [VoiceController.checkUpgrade], swapped in by the next reading, which
/// plays to the end and leaves the one-time notice; the reading after spends it.
///
/// --dart-define=GANJ_E2E_OLD_BASE=http://127.0.0.1:8771/   (serves the old voice, e.g. 1.1.0)
/// --dart-define=GANJ_VOICE_BASE=http://127.0.0.1:8772/     (serves the new voice, e.g. 1.2.0)
/// GANJ_VOICE_BASE names one server, so the test points the downloader at each in turn; the new one is reached
/// through a small counting proxy, to measure what the upgrade downloads. Screens go to build/e2e_shots/upgrade_*.png.
const _oldBase = String.fromEnvironment('GANJ_E2E_OLD_BASE', defaultValue: 'http://127.0.0.1:8771/');
const _newBase = String.fromEnvironment('GANJ_VOICE_BASE', defaultValue: 'http://127.0.0.1:8772/');

/// The staged upgrade's manifest (private in voice_providers.dart).
const _stagedPref = 'voice.stagedManifest';

/// Forwards every request to [upstream] and counts the response body bytes it passes on.
class _CountingProxy {
  _CountingProxy(this.upstream);

  final Uri upstream;
  final _client = HttpClient();
  late final HttpServer _server;
  int bytes = 0;
  final paths = <String>[];

  String get base => 'http://127.0.0.1:${_server.port}/';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> _serve(HttpRequest req) async {
    try {
      paths.add(req.uri.path);
      final up = await _client.getUrl(upstream.resolve(req.uri.path.substring(1)));
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
      final r = await up.close();
      req.response.statusCode = r.statusCode;
      for (final h in [
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.contentTypeHeader,
      ]) {
        final v = r.headers.value(h);
        if (v != null) req.response.headers.set(h, v);
      }
      await for (final chunk in r) {
        bytes += chunk.length;
        req.response.add(chunk);
      }
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Directory('build/e2e_shots')..createSync(recursive: true);
  final boundary = GlobalKey();

  Future<void> wait(WidgetTester tester, Duration d) async {
    await tester.runAsync(() => Future<void>.delayed(d));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => ro.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Future<void> until(WidgetTester tester, bool Function() done, {required Duration max, String? what}) async {
    final sw = Stopwatch()..start();
    while (!done() && sw.elapsed < max) {
      await wait(tester, const Duration(milliseconds: 250));
    }
    debugPrint('[e2e-upgrade] ${what ?? 'wait'}: ${sw.elapsed.inMilliseconds} ms, done=${done()}');
    expect(done(), isTrue, reason: what);
  }

  testWidgets('live: install the old voice, stage the new one, swap at the next reading', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('ganj_live_upgrade_');
    final voiceRoot = Directory('${tmp.path}/voice');
    final cacheBase = Directory('${tmp.path}/voice-cache');
    final backend = JustAudioBackend();
    final proxy = _CountingProxy(Uri.parse(_newBase));
    await tester.runAsync(proxy.start);
    var base = _oldBase;
    debugPrint('[e2e-upgrade] old=$_oldBase new=$_newBase via ${proxy.base}');

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            appDbProvider.overrideWithValue(db),
            audioBackendProvider.overrideWithValue(backend),
            voiceRootProvider.overrideWithValue(voiceRoot),
            voiceCacheBaseProvider.overrideWithValue(cacheBase),
            voiceDownloaderProvider.overrideWith(
              (ref) => VoiceDownloader(
                dio: Dio(BaseOptions(headers: {'User-Agent': kUserAgent})),
                root: ref.watch(voiceRootProvider),
                sources: {'dev': base},
              ),
            ),
          ],
          child: const GanjApp(),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(GanjApp)));
    c.read(routerProvider).push('/poem/2130');
    const verse2 = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';
    await until(tester, () => find.text(verse2).evaluate().isNotEmpty, max: const Duration(seconds: 30), what: 'poem');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('خوانش‌ها'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('voice-play')));
    await tester.pumpAndSettle();

    // 1. Install the old voice (no variants: no choice, quality).
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(
      tester,
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
      max: const Duration(seconds: 20),
      what: 'consent',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('دریافت')));
    await tester.pump();
    final swDl = Stopwatch()..start();
    await until(
      tester,
      () {
        final s = c.read(voiceProvider);
        return s is VoiceReady || s is VoiceFailed;
      },
      max: const Duration(minutes: 8),
      what: 'old download',
    );
    final old = c.read(voiceProvider);
    expect(old, isA<VoiceReady>());
    old as VoiceReady;
    expect(old.variant, kQualityVariant);
    final oldDir = Directory(old.dir);
    debugPrint(
      '[e2e-upgrade] installed ${old.version} (${old.bytes} bytes) in ${swDl.elapsed.inSeconds} s at ${old.dir}',
    );
    await tester.pumpAndSettle();

    // 2. The newer server: check for the upgrade, as a reading's start would (once a day), and let it stage.
    final newManifest = VoiceManifest.fromJson(
      jsonDecode(
        (await tester.runAsync(
          () => HttpClient()
              .getUrl(Uri.parse('${_newBase}voice.json'))
              .then((r) => r.close())
              .then((r) => r.transform(utf8.decoder).join()),
        ))!,
      ) as Map<String, dynamic>,
    );
    expect(newManifest.version, isNot(old.version));
    final oldFiles = {
      for (final f in VoiceManifest.fromJson(
        jsonDecode(File('${old.dir}/installed.json').readAsStringSync()) as Map<String, dynamic>,
      ).filesFor(kQualityVariant))
        f.name: f.sha256,
    };
    final changed = [
      for (final f in newManifest.filesFor(kQualityVariant))
        if (oldFiles[f.name] != f.sha256) f,
    ];
    final changedBytes = changed.fold<int>(0, (s, f) => s + f.size);
    debugPrint(
      '[e2e-upgrade] changed files: ${[for (final f in changed) '${f.name} ${f.size}']} = $changedBytes bytes',
    );

    base = proxy.base;
    c.invalidate(voiceDownloaderProvider);
    final ctrl = c.read(voiceProvider.notifier);
    final swStage = Stopwatch()..start();
    ctrl.checkUpgrade();
    await tester.runAsync(() => ctrl.upgradeSettled);
    await tester.pump();
    final stageS = swStage.elapsedMilliseconds / 1000;
    debugPrint('[e2e-upgrade] staged in $stageS s: ${proxy.bytes} bytes over ${proxy.paths}');
    expect(prefs.getString(kVoiceUpgradeCheckedPref), isNotNull);
    expect(prefs.getString(_stagedPref), isNotNull, reason: 'staged');
    expect(ctrl.upgradeStaged, isTrue);
    // Only the changed files (and voice.json) came down.
    expect(proxy.bytes, greaterThanOrEqualTo(changedBytes));
    expect(proxy.bytes, lessThan(changedBytes + 64 * 1024));
    expect(changed.map((f) => f.name).toSet(), {'g2p_decoder.onnx', 'g2p_encoder.onnx'});
    // Still the old voice until a reading starts.
    expect((c.read(voiceProvider) as VoiceReady).version, old.version);

    // 3. The next reading swaps the new voice in, and plays to the end.
    final sw = Stopwatch()..start();
    int? firstSoundMs;
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(
      tester,
      () {
        final st = c.read(playerProvider);
        if (firstSoundMs == null &&
            st.recitation?.id == kVoiceRecitationId &&
            st.playing &&
            !st.waiting &&
            st.status == PlayerStatus.ready &&
            st.position > Duration.zero) {
          firstSoundMs = sw.elapsedMilliseconds;
        }
        return firstSoundMs != null;
      },
      max: const Duration(minutes: 15),
      what: 'first sound',
    );
    final now = c.read(voiceProvider);
    expect(now, isA<VoiceReady>());
    now as VoiceReady;
    expect(now.version, newManifest.version);
    expect(now.dir.split(Platform.pathSeparator).last, '${newManifest.version}-$kQualityVariant');
    expect(prefs.getString(_stagedPref), isNull);
    expect(prefs.getString(kVoiceImprovedNoticePref), newManifest.version);
    expect(oldDir.existsSync(), isFalse, reason: 'the old voice folder is gone');
    expect(voiceRoot.listSync().whereType<Directory>().map((d) => d.path.split(Platform.pathSeparator).last).toList(), [
      '${newManifest.version}-$kQualityVariant',
    ]);
    await until(
      tester,
      () => c.read(voicePrepareProvider(2130)) is Prepared,
      max: const Duration(minutes: 15),
      what: 'prepare done',
    );
    final preparedS = sw.elapsed.inSeconds;
    final wav = (c.read(voicePrepareProvider(2130)) as Prepared).wav;
    final wavBytes = wav.lengthSync();
    expect(wavBytes, greaterThan(44 + 24000), reason: 'the reading has audio');
    expect(wav.path, contains('${newManifest.version}-$kQualityVariant'));
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.text('خوانش ماشینی بهتر شد'), findsOneWidget, reason: 'the notice, in the row');
    await shot(tester, 'upgrade_1_notice');
    await until(
      tester,
      () {
        final st = c.read(playerProvider);
        return !st.playing && st.status == PlayerStatus.ready && st.currentVOrder == null;
      },
      max: const Duration(minutes: 5),
      what: 'reading finished',
    );
    final totalS = sw.elapsed.inSeconds;
    expect(prefs.getString(kVoiceImprovedNoticePref), newManifest.version, reason: 'kept until the next reading');

    // 4. The next reading spends the notice.
    await tester.runAsync(() => c.read(playerProvider.notifier).stop());
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(tester, () => c.read(playerProvider).playing, max: const Duration(seconds: 10), what: 'replay');
    expect(prefs.getString(kVoiceImprovedNoticePref), isNull);
    await tester.runAsync(() => c.read(playerProvider.notifier).stop());
    await wait(tester, const Duration(milliseconds: 500));
    expect(find.text('خوانش ماشینی بهتر شد'), findsNothing);
    await shot(tester, 'upgrade_2_spent');

    debugPrint(
      '[e2e-upgrade] SUMMARY ${old.version}->${now.version} upgradeBytes=${proxy.bytes} changedBytes=$changedBytes '
      'stageS=$stageS firstSoundMs=$firstSoundMs preparedS=$preparedS totalS=$totalS wavBytes=$wavBytes',
    );

    await tester.runAsync(() => backend.dispose());
    await tester.runAsync(proxy.close);
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });
}
