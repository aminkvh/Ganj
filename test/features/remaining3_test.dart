import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/extras/random_poem.dart';
import 'package:ganj/features/extras/url_screen.dart';
import 'package:ganj/features/library/library_providers.dart';
import 'package:ganj/features/library/library_screen.dart';
import 'package:ganj/features/metre/similar_screen.dart';
import 'package:ganj/features/player/audio_store.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../data/extras_test.dart' show ex;
import '../data/packs/pack_importer_test.dart' show hafezPack;
import '../support/fake_adapter.dart';
import '../support/fixture_repository.dart';
import '../support/gdb_builder.dart';
import '../support/scroll.dart';
import '../support/test_app.dart';
import 'extras/extras_screens_test.dart' show pumpRouted, settle;
import 'player/audio_store_test.dart' show MemoryAudioStore;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('user data', () {
    late AppDb db;
    late UserRepository repo;
    setUp(() {
      db = AppDb(NativeDatabase.memory());
      repo = UserRepository(db);
    });
    tearDown(() => db.close());

    test('toggling a bookmark twice at once ends where it started', () async {
      final results = await Future.wait([repo.toggleBookmark(1, 't', 'f'), repo.toggleBookmark(1, 't', 'f')]);
      expect(results.toSet(), {true, false});
      expect(await repo.isBookmarked(1), isFalse);
    });

    test('importing an older backup never overwrites newer notes; a newer one does', () async {
      await repo.setNote(1, 0, 'تازه', 't', 'f');
      Map<String, Object?> note(String text, int updated) => {
        'poem_id': 1,
        'couplet_index': 0,
        'text': text,
        'poem_title': 't',
        'full_title': 'f',
        'updated': updated,
      };
      await repo.importJson(
        jsonEncode({
          'notes': [note('کهنه', 1)],
        }),
      );
      expect((await repo.notesFor(1))[0], 'تازه');
      final later = DateTime.now().millisecondsSinceEpoch + 100000;
      await repo.importJson(
        jsonEncode({
          'notes': [note('تازه‌تر', later)],
        }),
      );
      expect((await repo.notesFor(1))[0], 'تازه‌تر');
    });

    test('history keeps only the most recent 500 poems', () async {
      for (var i = 0; i < 510; i++) {
        await repo.recordVisit(i, 't$i', 'f$i');
      }
      final all = await repo.history(limit: 10000);
      expect(all.length, 500);
      expect(all.map((e) => e.poemId), contains(509));
    });
  });

  testWidgets('library total counts installed packs missing from the catalog, without crashing', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() => importGdb(db, buildHafezGdb(Directory.systemTemp.createTempSync('orph_')), hafezPack));
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const LibraryScreen(),
        prefs: prefs,
        db: db,
        overrides: [
          packCatalogProvider.overrideWith((ref) async => []),
          audioStoreProvider.overrideWithValue(MemoryAudioStore()),
        ],
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('شاعر روی دستگاه'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a link opened offline asks to check the connection, not "not found"', (tester) async {
    await pumpRouted(tester, const UrlScreen(url: '/hafez/ghazal/sh1'), FakeAdapter({})..offline = true);
    await settle(tester);
    expect(find.text('اتصال به گنجور برقرار نشد'), findsOneWidget);
    expect(find.text('این شعر پیدا نشد'), findsNothing);
  });

  testWidgets('similar poems: a later page that fails says so and retries', (tester) async {
    final adapter = FakeAdapter({'/api/ganjoor/poems/similar': ex('similar.json')});
    adapter.headers['/api/ganjoor/poems/similar'] = {
      'paging-headers': '{"totalCount":46,"pageSize":20,"currentPage":1,"totalPages":3,"hasNextPage":true}',
    };
    await pumpRouted(tester, const SimilarScreen(metre: 'مفاعیلن مفاعیلن مفاعیلن مفاعیلن'), adapter);
    await settle(tester);
    adapter.offline = true;
    await tester.tap(find.text('نتایج بیشتر'));
    await settle(tester);
    final retry = find.text('نتایج بیشتر دریافت نشد — تلاش دوباره');
    expect(retry, findsOneWidget);
    adapter.offline = false;
    await tester.tap(retry);
    await settle(tester);
    expect(adapter.requests.last.queryParameters['PageNumber'], '2');
    expect(find.byType(ListTile), findsNWidgets(6));
  });

  testWidgets('random poem: a second tap while loading does not open a second poem', (tester) async {
    final adapter = FakeAdapter({'/api/ganjoor/poem/random': ex('random.json')})
      ..delay = const Duration(milliseconds: 200);
    await pumpRouted(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(onPressed: () => openRandomPoem(context, ref), child: const Text('تصادفی')),
        ),
      ),
      adapter,
    );
    await tester.tap(find.text('تصادفی'));
    await tester.tap(find.text('تصادفی'));
    await settle(tester);
    await settle(tester);
    expect(adapter.requests.where((u) => u.path.endsWith('/random')).length, 1);
  });

  testWidgets('a poet picture that cannot load in the related panel is not an error', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final adapter = FakeAdapter({
      '/api/ganjoor/section/2130/0/related': ex('related_2130.json'),
      '/api/ganjoor/poem/2130/images': '[]',
    });
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        db: db,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: adapter),
              cache: HttpCache(db),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    final title = find.text('اشعار هم‌وزن و هم‌قافیه');
    await bringIntoView(tester, title);
    await tester.tap(title);
    await settle(tester);
    expect(find.byType(CircleAvatar), findsWidgets);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });
}
