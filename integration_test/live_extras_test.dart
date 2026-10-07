import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M4 live check: real extras endpoints, faal, and user data surviving an app restart (file DB).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Directory('build/e2e_shots')..createSync(recursive: true);
  final boundary = GlobalKey();

  Future<void> wait(WidgetTester tester, [int ms = 300]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pumpAndSettle();
  }

  testWidgets('live: extras endpoints, faal, poem panels, bookmark survives restart', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ganj_live_m4_');
    final dbFile = File('${dir.path}/ganj.sqlite');

    // Endpoints against the real API.
    await tester.runAsync(() async {
      final db = AppDb(NativeDatabase(dbFile));
      final api = GanjoorApi(dio: createDio(), cache: HttpCache(db));
      final faal = await api.faal();
      final random = await api.randomPoem(poetId: 2);
      final songs = await api.songs(2130);
      final comments = await api.comments(2130);
      final images = await api.images(2130);
      final related = await api.related(2130, 0);
      final quoted = await api.quoteds(2130);
      final rhythms = await api.rhythms();
      final similar = await api.similar(metre: rhythms.reduce((a, b) => a.verseCount > b.verseCount ? a : b).rhythm);
      final id = await api.poemIdForUrl(related.first.fullUrl);
      debugPrint('[e2e-m4] faal=${faal.id} random=${random.id} songs=${songs.length} comments=${comments.length} '
          'images=${images.length} related=${related.length} quoted=${quoted.length} rhythms=${rhythms.length} '
          'similar=${similar.total} url→$id');
      expect(faal.verses, isNotEmpty);
      expect(songs, isNotEmpty);
      expect(comments, isNotEmpty);
      expect(comments.first.text, isNot(contains('<p>')));
      expect(id, greaterThan(0));
      await UserRepository(db).toggleBookmark(2130, 'غزل شمارهٔ ۱', 'حافظ » غزلیات » غزل شمارهٔ ۱');
      await db.close();
    });

    // "Restart": a new DB connection on the same file still has the bookmark.
    final db = AppDb(NativeDatabase(dbFile));
    expect(await tester.runAsync(() => UserRepository(db).isBookmarked(2130)), isTrue);

    // UI: poem page with the comments panel open.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          appDbProvider.overrideWithValue(db),
          audioBackendProvider.overrideWithValue(JustAudioBackend()),
        ],
        child: const GanjApp(),
      ),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(GanjApp)));
    c.read(routerProvider).push('/poem/2130');
    for (var i = 0; i < 40 && find.byTooltip('نشان‌گذاری').evaluate().isEmpty; i++) {
      await wait(tester, 250);
    }
    await wait(tester, 500);
    expect(find.byIcon(Icons.bookmark), findsWidgets); // restored from the file DB
    final title = find.text('حاشیه‌ها');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    for (var i = 0; i < 20; i++) {
      await wait(tester, 250);
    }
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => ro.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('${shots.path}/20_poem_comments.png').writeAsBytesSync(bytes!.buffer.asUint8List());

    await tester.pumpWidget(const SizedBox());
    await wait(tester);
    await tester.runAsync(db.close);
  });
}
