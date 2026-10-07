import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/repo/poetry_repository.dart';

import '../support/fake_adapter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  PoetryRepository build(FakeAdapter adapter, AppDb db) => PoetryRepository(
    GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    ),
    loadSeed: () async => File('assets/seed/centuries.json').readAsStringSync(),
  );

  test('first launch offline with empty cache still lists poets from seed', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = build(FakeAdapter({})..offline = true, db);
    final cs = await repo.centuries();
    expect(cs.first.id, 0);
    expect(cs.expand((c) => c.poets), isNotEmpty);
  });

  test('online centuries come from the API', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakeAdapter(fixtureRoutes());
    final cs = await build(adapter, db).centuries();
    expect(cs, hasLength(13));
    expect(adapter.requests.single.path, '/api/ganjoor/centuries');
  });
}
