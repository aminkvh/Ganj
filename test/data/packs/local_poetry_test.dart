import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/local_poetry.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/repo/poetry_repository.dart';

import '../../support/fake_adapter.dart';
import '../../support/fixtures.dart';
import '../../support/gdb_builder.dart';
import 'pack_importer_test.dart' show hafezPack;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late AppDb db;
  late LocalPoetry local;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ganj_local_');
    db = AppDb(NativeDatabase.memory());
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    local = LocalPoetry(db);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('poem from pack: verses, couplets, breadcrumb, navigation', () async {
    final p = (await local.poem(2130))!;
    expect(p.title, 'غزل شمارهٔ ۱');
    expect(p.fullUrl, '/hafez/ghazal/sh1');
    expect(p.verses, hasLength(14));
    expect([for (final v in p.verses) v.coupletIndex], [for (final v in poem2130().verses) v.coupletIndex]);
    expect(p.category!.poet.id, 2);
    expect(p.category!.cat.title, 'غزلیات');
    expect(p.category!.cat.ancestors.map((a) => a.title), ['حافظ']);
    expect(p.next, isNull);
    expect(p.recitations, isEmpty);
  });

  test('poet and category from pack', () async {
    final poet = (await local.poet(2))!;
    expect(poet.poet.name, 'حافظ');
    expect(poet.cat.id, 9);
    expect(poet.cat.children.map((c) => c.id), [24, 674]);
    final cat = (await local.cat(24))!;
    expect(cat.cat.ancestors.single.id, 9);
    expect(cat.cat.poems.single.id, 2130);
    expect(cat.cat.poems.single.excerpt, startsWith('اَلا یا'));
  });

  test('unknown ids return null', () async {
    expect(await local.poem(999), isNull);
    expect(await local.cat(999), isNull);
    expect(await local.poet(999), isNull);
  });

  test('repository falls back to the pack when offline, else rethrows', () async {
    final adapter = FakeAdapter({})..offline = true;
    final repo = PoetryRepository(
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
      local: local,
    );
    expect((await repo.poem(2130)).verses, hasLength(14));
    expect((await repo.cat(24)).cat.title, 'غزلیات');
    expect((await repo.poet(2)).poet.id, 2);
    await expectLater(repo.poem(999), throwsA(isA<DioException>()));
  });

  test('offline pack poems include recitations downloaded on this device', () async {
    final adapter = FakeAdapter({})..offline = true;
    final rec = poem2130().recitations.first;
    final repo = PoetryRepository(
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
      local: local,
      offlineRecitations: (poemId) async => poemId == 2130 ? [rec] : const [],
    );
    expect((await repo.poem(2130)).recitations.single.id, rec.id);
  });

  test('with a pack installed, a hanging network falls back to the pack quickly', () async {
    final adapter = FakeAdapter(fixtureRoutes())..delay = const Duration(seconds: 5);
    final repo = PoetryRepository(
      GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      ),
      local: local,
      packTimeout: const Duration(milliseconds: 100),
    );
    final sw = Stopwatch()..start();
    expect((await repo.poem(2130)).verses, hasLength(14));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
