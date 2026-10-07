import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/audio_store.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M2 live check on the real platform audio stack: play, verse sync, download, offline replay.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Directory('build/e2e_shots')..createSync(recursive: true);
  final boundary = GlobalKey();

  Future<void> wait(WidgetTester tester, Duration d) async {
    await tester.runAsync(() => Future<void>.delayed(d));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => ro.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  testWidgets('live: recitation plays in sync, downloads, replays from file', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    final audioDir = Directory.systemTemp.createTempSync('ganj_live_audio_');
    final backend = JustAudioBackend();

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            appDbProvider.overrideWithValue(db),
            audioBackendProvider.overrideWithValue(backend),
            audioStoreProvider.overrideWith(
              (ref) => FileAudioStore(audioDir, createDio(), ref.watch(poetryRepositoryProvider)),
            ),
          ],
          child: const GanjApp(),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(GanjApp)));
    c.read(routerProvider).push('/poem/2130');
    const verse2 = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';
    for (var i = 0; i < 100 && find.text(verse2).evaluate().isEmpty; i++) {
      await wait(tester, const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('خوانش‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-play-2840')));
    // Verse 2 starts at 7.386 s in recitation 2840.
    for (var i = 0; i < 60 && (c.read(playerProvider).currentVOrder ?? 0) < 2; i++) {
      await wait(tester, const Duration(milliseconds: 500));
    }
    final st = c.read(playerProvider);
    debugPrint('[e2e-audio] player.duration=${backend.player.duration} event=${backend.player.playbackEvent.duration}');
    debugPrint('[e2e-audio] status=${st.status} pos=${st.position} vOrder=${st.currentVOrder} dur=${st.duration}');
    expect(st.status, PlayerStatus.ready);
    expect(st.currentVOrder, greaterThanOrEqualTo(2));
    expect(st.duration, greaterThan(const Duration(seconds: 30)));
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    await shot(tester, '10_audio_playing');

    // Download for offline listening.
    await tester.ensureVisible(find.byKey(const ValueKey('rec-dl-2840')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-dl-2840')));
    final store = c.read(audioStoreProvider)!;
    for (var i = 0; i < 120 && !store.isDownloaded(2840); i++) {
      await wait(tester, const Duration(milliseconds: 500));
    }
    expect(store.isDownloaded(2840), isTrue);
    expect(File.fromUri(store.mp3Uri(2840)).lengthSync(), greaterThan(100000));

    // Replay: the controller now loads the local file.
    final poem = c.read(playerProvider).poem!;
    await tester.runAsync(() => c.read(playerProvider.notifier).play(poem, poem.recitations.first));
    final src = backend.player.audioSource as UriAudioSource;
    expect(src.uri.scheme, 'file');
    await wait(tester, const Duration(seconds: 3));
    expect(c.read(playerProvider).position, greaterThan(Duration.zero));
    debugPrint('[e2e-audio] offline replay from ${src.uri} pos=${c.read(playerProvider).position}');

    await tester.runAsync(() => c.read(playerProvider.notifier).stop());
    await tester.runAsync(() => store.delete(2840));
    await tester.runAsync(() => backend.dispose());
    await db.close();
    audioDir.deleteSync(recursive: true);
  });
}
