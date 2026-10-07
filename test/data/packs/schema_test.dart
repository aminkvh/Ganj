import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/couplet_index.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/fixtures.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('couplet indexes rebuilt from positions match the API', () {
    for (final poem in [poem2130(), poem77000()]) {
      expect(coupletIndexes([for (final v in poem.verses) v.position]), [for (final v in poem.verses) v.coupletIndex]);
    }
    expect(coupletIndexes([0, 1, 2, 3, 4, 5, -1, 0, 1]), [0, 0, 1, 1, 2, 3, 4, 5, 5]);
    expect(coupletIndexes([1, 0]), [0, 1]); // a stray left line still starts couplet 0
  });

  test('fresh database has content tables and FTS', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final names = (await db.customSelect("SELECT name FROM sqlite_master WHERE type IN ('table')").get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(names, containsAll(['api_cache', 'poets', 'cats', 'poems', 'verses', 'packs', 'verse_fts']));
  });

  test('v1 database upgrades to v2 keeping cached API rows', () async {
    final dir = Directory.systemTemp.createTempSync('ganj_mig_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v1.sqlite';
    final raw = sqlite3.open(path)
      ..execute(
        'CREATE TABLE api_cache (key TEXT NOT NULL PRIMARY KEY, body BLOB NOT NULL, fetched_at INTEGER NOT NULL)',
      )
      ..execute("INSERT INTO api_cache VALUES ('k', x'00', 1)")
      ..execute('PRAGMA user_version = 1');
    raw.close();
    final db = AppDb(NativeDatabase(File(path)));
    final cached = await db.customSelect('SELECT count(*) AS c FROM api_cache').getSingle();
    expect(cached.read<int>('c'), 1);
    final fts = await db.customSelect("SELECT count(*) AS c FROM sqlite_master WHERE name = 'verse_fts'").getSingle();
    expect(fts.read<int>('c'), 1);
    await db.close();
  });
}
