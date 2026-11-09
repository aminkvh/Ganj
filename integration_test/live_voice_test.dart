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
import 'package:ganj/features/voice/app/voice_providers.dart';
import 'package:ganj/router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live check of the machine reading on the real platform: consent, download from a local server
/// (--dart-define=GANJ_VOICE_BASE=http://127.0.0.1:8765/), prepare a ghazal on the device, play with beyt sync,
/// replay from the cache, remove in Settings. Screens go to build/e2e_shots/voice_*.png.
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
      await wait(tester, const Duration(milliseconds: 500));
    }
    debugPrint('[e2e-voice] ${what ?? 'wait'}: ${sw.elapsed.inMilliseconds} ms, done=${done()}');
    expect(done(), isTrue, reason: what);
  }

  testWidgets('live: machine reading downloads, prepares, plays in sync, replays, is removed', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    final tmp = Directory.systemTemp.createTempSync('ganj_live_voice_');
    final voiceRoot = Directory('${tmp.path}/voice');
    final cacheBase = Directory('${tmp.path}/voice-cache');
    final backend = JustAudioBackend();

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
    await shot(tester, 'voice_1_absent');

    // Consent, then download.
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(tester, () => find.byType(AlertDialog).evaluate().isNotEmpty, max: const Duration(seconds: 20), what: 'consent');
    await tester.pumpAndSettle();
    await shot(tester, 'voice_2_consent');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('دریافت')));
    await tester.pump();
    var shotDownloading = false;
    await until(tester, () {
      final s = c.read(voiceProvider);
      if (s is VoiceDownloading && !shotDownloading) shotDownloading = true;
      return s is VoiceReady || s is VoiceFailed;
    }, max: const Duration(minutes: 5), what: 'download');
    expect(c.read(voiceProvider), isA<VoiceReady>());
    await tester.pumpAndSettle();

    // Prepare and play.
    final sw = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await wait(tester, const Duration(seconds: 2));
    await until(tester, () => c.read(voicePrepareProvider(2130)) is Preparing, max: const Duration(seconds: 60), what: 'preparing starts');
    await until(tester, () {
      final p = c.read(voicePrepareProvider(2130));
      return p is Preparing && p.done >= 1;
    }, max: const Duration(minutes: 3), what: 'first beyt');
    await tester.pump();
    await shot(tester, 'voice_3_preparing');
    await until(tester, () => c.read(voicePrepareProvider(2130)) is! Preparing, max: const Duration(minutes: 15), what: 'prepare');
    final prepared = c.read(voicePrepareProvider(2130));
    expect(prepared, isA<Prepared>());
    debugPrint('[e2e-voice] prepared in ${sw.elapsed.inSeconds} s');
    await until(tester, () => (c.read(playerProvider).currentVOrder ?? 0) >= 2, max: const Duration(seconds: 40), what: 'beyt 2 highlighted');
    final st = c.read(playerProvider);
    debugPrint('[e2e-voice] status=${st.status} pos=${st.position} vOrder=${st.currentVOrder} dur=${st.duration}');
    expect(st.recitation?.id, kVoiceRecitationId);
    expect(st.status, PlayerStatus.ready);
    await shot(tester, 'voice_4_playing');

    // Replay: cache hit, plays at once.
    await tester.runAsync(() => c.read(playerProvider.notifier).stop());
    await tester.pump();
    final sw2 = Stopwatch()..start();
    await tester.tap(find.byKey(const ValueKey('voice-play')));
    await until(tester, () => c.read(playerProvider).playing, max: const Duration(seconds: 10), what: 'replay from cache');
    debugPrint('[e2e-voice] replay started in ${sw2.elapsedMilliseconds} ms');

    // Remove in Settings.
    c.read(routerProvider).push('/settings');
    await wait(tester, const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('voice-remove')), 200);
    await tester.pumpAndSettle();
    await shot(tester, 'voice_5_settings');
    await tester.tap(find.byKey(const ValueKey('voice-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
    await until(tester, () => c.read(voiceProvider) is VoiceAbsent, max: const Duration(seconds: 20), what: 'removed');
    expect(c.read(playerProvider).recitation, isNull);
    expect(voiceRoot.existsSync() ? voiceRoot.listSync() : const [], isEmpty);

    await tester.runAsync(() => backend.dispose());
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });
}
