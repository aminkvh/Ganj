import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/features/search/search_service.dart';

import '../../data/packs/pack_importer_test.dart' show hafezPack;
import '../../support/fake_adapter.dart';
import '../../support/gdb_builder.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late AppDb db;
  late FakeAdapter adapter;
  late SearchService service;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ganj_search_');
    db = AppDb(NativeDatabase.memory());
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    adapter = FakeAdapter({'/api/ganjoor/poems/search': File('test/fixtures/search_saghi.json').readAsStringSync()});
    adapter.headers['/api/ganjoor/poems/search'] = {
      'paging-headers': '{"totalCount":130,"pageSize":20,"currentPage":1,"totalPages":7,"hasNextPage":true}',
    };
    service = SearchService(
      db,
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  group('local full-text search', () {
    for (final q in ['ساقی', 'ساقي', 'السّاقی', '  ساقی  ']) {
      test('«$q» finds ghazal 1', () async {
        final page = await service.searchLocal(q);
        expect(page.hits.map((h) => h.poemId), contains(2130));
        expect(page.hits.first.local, isTrue);
        expect(page.hits.first.poetName, 'حافظ');
      });
    }

    test('poet filter excludes other poets', () async {
      expect((await service.searchLocal('ساقی', poetId: 7)).hits, isEmpty);
    });

    test('FTS syntax characters in the query do not throw', () async {
      expect((await service.searchLocal('"ساقی* OR (')).hits, isA<List<SearchHit>>());
    });
  });

  test('API search parses hits and paging header', () async {
    final page = await service.searchOnline('ساقی', poetId: 2);
    expect(page.hits, hasLength(20));
    expect(page.total, 130);
    expect(page.hasMore, isTrue);
    expect(page.hits.first.poetName, 'حافظ');
    expect(page.hits.first.snippet, contains('ساقی'));
    final uri = adapter.requests.single;
    expect(uri.queryParameters['term'], 'ساقی');
    expect(uri.queryParameters['poetId'], '2');
  });

  test('merged search: local first, no duplicate poems, offline still returns local', () async {
    final merged = await service.search('ساقی', poetId: 2);
    final ids = merged.hits.map((h) => h.poemId).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(merged.hits.first.local, isTrue);
    adapter.offline = true;
    final offline = await service.search('ساقی', poetId: 2);
    expect(offline.offline, isTrue);
    expect(offline.hits.map((h) => h.poemId), contains(2130));
  });

  test('a hanging network does not hold back local results', () async {
    adapter.delay = const Duration(seconds: 5);
    final fast = SearchService(
      db,
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
      onlineTimeout: const Duration(milliseconds: 100),
    );
    final sw = Stopwatch()..start();
    final page = await fast.search('ساقی', poetId: 2);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(page.offline, isTrue);
    expect(page.hits.map((h) => h.poemId), contains(2130));
  });
}
