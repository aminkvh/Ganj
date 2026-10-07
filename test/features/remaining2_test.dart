import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/repo/poetry_repository.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/home/home_screen.dart';
import 'package:ganj/features/library/library_providers.dart';
import 'package:ganj/features/library/library_screen.dart';
import 'package:ganj/features/player/audio_store.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/settings/settings_screen.dart';

import '../data/packs/pack_importer_test.dart' show hafezPack;
import '../support/fake_adapter.dart';
import '../support/fake_audio_backend.dart';
import '../support/fixture_repository.dart';
import '../support/fixtures.dart';
import '../support/gdb_builder.dart';
import '../support/scroll.dart';
import '../support/test_app.dart';
import 'library/library_screen_test.dart' show FakeInstaller;
import 'player/audio_store_test.dart' show MemoryAudioStore;
import 'poem/long_poem_test.dart' show longPoem;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('home started offline from the bundled list refreshes once the network is back', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final adapter = FakeAdapter(fixtureRoutes())..offline = true;
    // The bundled list here has one made-up poet so it is easy to tell apart.
    final seed = jsonEncode([
      {
        'id': 0,
        'name': '',
        'poets': [
          {'id': 999, 'name': 'شاعر بذر', 'nickname': 'شاعر بذر', 'rootCatId': 1, 'fullUrl': '/x'},
        ],
      },
    ]);
    final repo = PoetryRepository(
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
      loadSeed: () async => seed,
    );
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: repo, db: db));
    await settle(tester);
    expect(find.text('شاعر بذر'), findsWidgets);
    expect(find.byKey(const ValueKey('seed-refresh')), findsOneWidget);
    adapter.offline = false;
    await tester.tap(find.byKey(const ValueKey('seed-refresh')));
    await settle(tester);
    expect(find.byKey(const ValueKey('poet-2')), findsWidgets); // real list arrived
    expect(find.byKey(const ValueKey('seed-refresh')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('removing a pack asks first; cancel keeps it', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() => importGdb(db, buildHafezGdb(Directory.systemTemp.createTempSync('rm_')), hafezPack));
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const LibraryScreen(),
        prefs: prefs,
        db: db,
        overrides: [
          packCatalogProvider.overrideWith((ref) async => [hafezPack]),
          packInstallerProvider.overrideWithValue(FakeInstaller(db)),
          audioStoreProvider.overrideWithValue(MemoryAudioStore()),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pack-del-2')));
    await tester.pumpAndSettle();
    expect(find.text('حذف حافظ از دستگاه؟'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await settle(tester);
    expect(await tester.runAsync(() => installedPoets(db)), {2});
    await tester.tap(find.byKey(const ValueKey('pack-del-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await settle(tester);
    expect(await tester.runAsync(() => installedPoets(db)), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('deleting the recitation that is playing stops it first', (tester) async {
    final backend = FakeAudioBackend();
    final store = MemoryAudioStore()..done.add(2840);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const LibraryScreen(),
        prefs: prefs,
        backend: backend,
        repo: FixtureRepository(),
        overrides: [
          packCatalogProvider.overrideWith((ref) async => [hafezPack]),
          audioStoreProvider.overrideWithValue(store),
        ],
      ),
    );
    await settle(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    final poem = poem2130();
    await tester.runAsync(() => c.read(playerProvider.notifier).play(poem, poem.recitations.first));
    await tester.tap(find.text('خوانش‌ها'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('audio-del-2840')));
    await settle(tester);
    expect(c.read(playerProvider).status, PlayerStatus.idle);
    expect(store.done, isEmpty);
  });

  testWidgets('with the find bar open, the saved position is the beyt shown at the top', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = FixtureRepository()..poems[999] = longPoem(1500);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 999, couplet: 300), prefs: prefs, repo: repo, db: db));
    await settle(tester);
    await tester.tap(find.byTooltip('جستجو در شعر'));
    await settle(tester);
    // Put couplet 300 right under the find bar.
    final f = find.text('مصراع نخست بیت 300');
    await bringIntoView(tester, f);
    final viewportTop = tester.getRect(find.byType(CustomScrollView)).top;
    await tester.drag(find.byType(CustomScrollView), Offset(0, viewportTop - tester.getRect(f).top + 8));
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    expect(await tester.runAsync(() => UserRepository(db).lastCouplet(999)), 300);
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('clearing the cache gives the space back', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ganj_vac_');
    final file = File('${dir.path}/c.sqlite');
    final db = AppDb(NativeDatabase(file));
    await tester.runAsync(() async {
      for (var i = 0; i < 200; i++) {
        await db.customStatement("INSERT INTO api_cache (key, body, fetched_at) VALUES ('k$i', randomblob(20000), 1)");
      }
    });
    final before = file.lengthSync();
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const SettingsScreen(), prefs: prefs, db: db));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('پاک‌کردن حافظهٔ موقت'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('پاک‌کردن حافظهٔ موقت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('پاک‌کردن حافظهٔ موقت'));
    await settle(tester);
    expect(file.lengthSync(), lessThan(before ~/ 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('play from a beyt uses a synced recitation even if the first is not synced', (tester) async {
    final j = jsonDecode(fx('poem_2130')) as Map<String, dynamic>;
    final recs = (j['recitations'] as List).cast<Map<String, dynamic>>();
    recs.first['inSyncWithText'] = false;
    final repo = FixtureRepository()..poems[2130] = Poem.fromJson(j);
    final backend = FakeAudioBackend();
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: repo, backend: backend));
    await settle(tester);
    const verse3 = 'به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید';
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('پخش از این بیت'));
    await settle(tester);
    expect(backend.loaded.single.toString(), isNot(recs.first['mp3Url']));
    expect(backend.seeks, isNotEmpty);
  });
}
