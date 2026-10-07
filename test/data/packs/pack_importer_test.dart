import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_catalog.dart';
import 'package:ganj/data/packs/pack_importer.dart';

import '../../support/fixtures.dart';
import '../../support/gdb_builder.dart';

const hafezPack = PackInfo(
  poetId: 2,
  catId: 9,
  name: 'حافظ',
  url: 'https://i.ganjoor.net/android/gdb/hafez.zip',
  imageUrl: '',
  size: 347000,
  pubDate: '2026-09-01',
);

Future<int> count(AppDb db, String sql, [List<Object> args = const []]) async =>
    (await db.customSelect(sql, variables: [for (final a in args) Variable(a)]).getSingle()).read<int>('c');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late AppDb db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ganj_pack_');
    db = AppDb(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('imports poets, cats, poems and verses with site-relative urls', () async {
    final r = await importGdb(db, buildHafezGdb(dir), hafezPack);
    expect(r.poems, 2);
    expect(r.verses, poem2130().verses.length + poem77000().verses.length);
    final url = await db.customSelect('SELECT full_url FROM poems WHERE id = 2130').getSingle();
    expect(url.read<String>('full_url'), '/hafez/ghazal/sh1');
    final root = await db.customSelect('SELECT parent_id FROM cats WHERE id = 9').getSingle();
    expect(root.read<int?>('parent_id'), isNull);
    expect(await installedPoets(db), {2});
  });

  test('rebuilt couplet indexes equal the API', () async {
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    for (final p in [poem2130(), poem77000()]) {
      final rows = await db
          .customSelect(
            'SELECT couplet_index FROM verses WHERE poem_id = ? ORDER BY vorder',
            variables: [Variable(p.id)],
          )
          .get();
      expect([for (final r in rows) r.read<int>('couplet_index')], [for (final v in p.verses) v.coupletIndex]);
    }
  });

  test('full-text index uses normalized text (diacritics stripped)', () async {
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    expect(await count(db, "SELECT count(*) AS c FROM verse_fts WHERE verse_fts MATCH 'الساقی'"), 1);
  });

  test('re-importing does not duplicate rows or index entries', () async {
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    expect(await count(db, 'SELECT count(*) AS c FROM poems'), 2);
    expect(await count(db, "SELECT count(*) AS c FROM verse_fts WHERE verse_fts MATCH 'الساقی'"), 1);
  });

  test('uninstall removes only that poet and keeps the API cache', () async {
    await db.customStatement("INSERT INTO api_cache (key, body, fetched_at) VALUES ('k', x'00', 1)");
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    await uninstall(db, 2);
    for (final t in ['poets', 'cats', 'poems', 'verses', 'verse_fts', 'packs']) {
      expect(await count(db, 'SELECT count(*) AS c FROM $t'), 0, reason: t);
    }
    expect(await count(db, 'SELECT count(*) AS c FROM api_cache'), 1);
  });
}
