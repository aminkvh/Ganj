import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/voice/app/steps_rule.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/app/voice_providers.dart';
import 'package:ganj/features/voice/engine/voice_settings.dart';
import 'package:ganj/router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 2 live check: the consent choice (fast by default), download of a v2 voice.json from a local server, early
/// start (beyt-by-beyt playlist), stalls, replay from the joined file, the Settings label, removal.
///
/// --dart-define=GANJ_VOICE_BASE=http://127.0.0.1:8767/
/// --dart-define=GANJ_E2E_VARIANT=fast|quality      (with a v2 voice.json; default fast: the dialog's default is
///                                                   kept. A voice.json without variants offers no choice: quality)
/// --dart-define=GANJ_E2E_SEED_T8=0.2               (optional: a remembered t8, s per audio s at 8 steps, set
///                                                   after the download, to choose the steps and force an early start)
/// --dart-define=GANJ_E2E_STEPS=4                   (optional: rewrites the installed phone.json's num_steps)
/// Screens go to build/e2e_shots/stream_*.png.
const _variant = String.fromEnvironment('GANJ_E2E_VARIANT', defaultValue: 'fast');
const _seed = String.fromEnvironment('GANJ_E2E_SEED_T8');
const _steps = String.fromEnvironment('GANJ_E2E_STEPS');

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
    debugPrint('[e2e-stream] ${what ?? 'wait'}: ${sw.elapsed.inMilliseconds} ms, done=${done()}');
    expect(done(), isTrue, reason: what);
  }

  testWidgets('live: fast/quality choice, early start, replay, remove', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('ganj_live_stream_');
    final voiceRoot = Directory('${tmp.path}/voice');
    final cacheBase = Directory('${tmp.path}/voice-cache');
    final backend = JustAudioBackend();
    debugPrint('[e2e-stream] variant=$_variant seed=$_seed steps=$_steps supportsPlaylist=${backend.supportsPlaylist}');

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

    // Consent with the two choices.
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(
      tester,
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
      max: const Duration(seconds: 20),
      what: 'consent',
    );
    await tester.pumpAndSettle();
    final choice = find.byType(RadioListTile<String>).evaluate().length;
    expect(choice, anyOf(0, 2), reason: 'one variant offers no choice, two a choice');
    final variant = choice == 0 ? kQualityVariant : _variant;
    debugPrint('[e2e-stream] consent offers ${choice == 0 ? 'no choice' : 'a choice'}: $variant');
    await shot(tester, 'stream_1_consent');
    if (choice == 2 && _variant == 'quality') {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('باکیفیت')).first);
      await tester.pumpAndSettle();
    }
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
      what: 'download',
    );
    final ready = c.read(voiceProvider);
    expect(ready, isA<VoiceReady>());
    expect((ready as VoiceReady).variant, variant);
    debugPrint('[e2e-stream] downloaded ${ready.bytes} bytes in ${swDl.elapsed.inSeconds} s');
    await tester.pumpAndSettle();

    if (_steps.isNotEmpty) {
      final f = File('${ready.dir}/phone.json');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      (j['sherpa'] as Map<String, dynamic>)['num_steps'] = int.parse(_steps);
      f.writeAsStringSync(jsonEncode(j));
      debugPrint('[e2e-stream] phone.json num_steps -> $_steps');
    }
    if (_seed.isNotEmpty) await prefs.setDouble(voiceT8Pref(ready.version), double.parse(_seed));
    // The steps this reading uses, chosen the way the controller does for a fresh poem.
    final usedSteps = chooseSteps(
      t8: prefs.getDouble(voiceT8Pref(ready.version)),
      playbackRate: c.read(playerProvider).speed,
      maxSteps: VoiceSettings.load('${ready.dir}/phone.json').numSteps,
    );
    debugPrint('[e2e-stream] reading with $usedSteps steps');

    // Prepare and stream.
    var stalls = 0;
    final stallSub = c.read(playerProvider.notifier).voiceStalls.listen((_) => stalls++);
    var waits = 0;
    var wasWaiting = false;
    final sw = Stopwatch()..start();
    int? firstSoundMs;
    var shotStreaming = false;
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(
      tester,
      () {
        final st = c.read(playerProvider);
        if (st.waiting && !wasWaiting) waits++;
        wasWaiting = st.waiting;
        if (firstSoundMs == null &&
            st.recitation?.id == kVoiceRecitationId &&
            st.playing &&
            !st.waiting &&
            st.status == PlayerStatus.ready &&
            st.position > Duration.zero) {
          firstSoundMs = sw.elapsedMilliseconds;
          debugPrint(
            '[e2e-stream] first sound at $firstSoundMs ms, streaming=${c.read(playerProvider.notifier).streaming}, '
            'prepare=${c.read(voicePrepareProvider(2130))}',
          );
        }
        return firstSoundMs != null;
      },
      max: const Duration(minutes: 15),
      what: 'first sound',
    );
    final streamed = c.read(playerProvider.notifier).streaming;
    await until(
      tester,
      () {
        final st = c.read(playerProvider);
        if (st.waiting && !wasWaiting) waits++;
        wasWaiting = st.waiting;
        if (!shotStreaming && (st.currentVOrder ?? 0) >= 2) shotStreaming = true;
        return c.read(voicePrepareProvider(2130)) is Prepared;
      },
      max: const Duration(minutes: 15),
      what: 'prepare done',
    );
    debugPrint('[e2e-stream] prepared in ${sw.elapsed.inSeconds} s');
    await shot(tester, 'stream_2_playing');
    await until(
      tester,
      () {
        final st = c.read(playerProvider);
        if (st.waiting && !wasWaiting) waits++;
        wasWaiting = st.waiting;
        return !st.playing && st.status == PlayerStatus.ready && st.currentVOrder == null;
      },
      max: const Duration(minutes: 5),
      what: 'reading finished',
    );
    debugPrint(
      '[e2e-stream] SUMMARY variant=$variant steps=$usedSteps (max ${_steps.isEmpty ? 'phone.json' : _steps}) '
      'streamed=$streamed firstSoundMs=$firstSoundMs totalS=${sw.elapsed.inSeconds} waits=$waits stalls=$stalls '
      'rememberedT8=${prefs.getDouble(voiceT8Pref(ready.version))}',
    );
    await stallSub.cancel();

    // Replay: the joined file, at once.
    await tester.runAsync(() => c.read(playerProvider.notifier).stop());
    await tester.pump();
    final sw2 = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(
      tester,
      () => c.read(playerProvider).playing,
      max: const Duration(seconds: 10),
      what: 'replay from cache',
    );
    debugPrint(
      '[e2e-stream] replay started in ${sw2.elapsedMilliseconds} ms, streaming=${c.read(playerProvider.notifier).streaming}',
    );
    expect(c.read(playerProvider.notifier).streaming, isFalse);
    await tester.runAsync(() => c.read(playerProvider.notifier).stop());

    // Settings names only the fast variant (quality has the plain label); remove.
    c.read(routerProvider).push('/settings');
    await wait(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('voice-remove')), 200);
    await tester.pumpAndSettle();
    expect(find.textContaining('سریع'), variant == kFastVariant ? findsWidgets : findsNothing);
    await shot(tester, 'stream_3_settings');
    await tester.tap(find.byKey(const ValueKey('voice-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
    await until(tester, () => c.read(voiceProvider) is VoiceAbsent, max: const Duration(seconds: 20), what: 'removed');
    expect(voiceRoot.existsSync() ? voiceRoot.listSync() : const [], isEmpty);

    await tester.runAsync(() => backend.dispose());
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });
}
