import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_catalog.dart';

import '../../support/fake_adapter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final xml = File('test/fixtures/packs/androidgdbs.xml').readAsStringSync();

  test('parses all packs with ids, url, size and date', () {
    final packs = parsePackCatalog(xml);
    expect(packs, hasLength(281));
    final hafez = packs.firstWhere((p) => p.poetId == 2);
    expect(hafez.catId, 9);
    expect(hafez.url, endsWith('/hafez.zip'));
    expect(hafez.size, greaterThan(0));
    expect(hafez.pubDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(hafez.name, isNotEmpty);
  });

  test('GanjoorApi.packCatalog fetches the absolute pack list and caches it', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakeAdapter({'/android/androidgdbs.xml': xml});
    final api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
    final packs = await api.packCatalog();
    await api.packCatalog();
    expect(packs, hasLength(281));
    expect(adapter.requests.single.host, 'i.ganjoor.net');
  });

  test('a captive-portal HTML page is not cached as the pack list', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakeAdapter({'/android/androidgdbs.xml': '<html><body>Login to Wi-Fi</body></html>'});
    final api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
    await expectLater(api.packCatalog(), throwsA(anything));
    adapter.routes['/android/androidgdbs.xml'] = xml;
    expect(await api.packCatalog(), hasLength(281));
  });
}
