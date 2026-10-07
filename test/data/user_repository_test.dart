import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/user/user_repository.dart';

import '../support/gdb_builder.dart';
import 'packs/pack_importer_test.dart' show hafezPack;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late UserRepository user;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    user = UserRepository(db);
  });
  tearDown(() => db.close());

  const title = 'غزل شمارهٔ ۱', full = 'حافظ » غزلیات » غزل شمارهٔ ۱';

  test('bookmark toggles for a poem and for a single beyt', () async {
    expect(await user.toggleBookmark(2130, title, full), isTrue);
    expect(await user.isBookmarked(2130), isTrue);
    expect(await user.toggleBookmark(2130, title, full, couplet: 3), isTrue);
    expect(await user.bookmarkedCouplets(2130), {3});
    expect(await user.toggleBookmark(2130, title, full), isFalse);
    expect(await user.isBookmarked(2130), isFalse);
    final list = await user.bookmarks();
    expect(list.single.coupletIndex, 3);
    expect(list.single.fullTitle, full);
  });

  test('history is newest first, one row per poem, keeps scroll offset', () async {
    await user.recordVisit(1, 'a', 'A', couplet: 10);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await user.recordVisit(2, 'b', 'B', couplet: 20);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await user.recordVisit(1, 'a', 'A', couplet: 30);
    await user.recordVisit(1, 'a', 'A'); // revisit without a position keeps the last couplet
    final h = await user.history();
    expect(h.map((e) => e.poemId), [1, 2]);
    expect(await user.lastCouplet(1), 30);
    expect(await user.lastCouplet(99), isNull);
  });

  test('notes: set, read per poem, empty text deletes', () async {
    await user.setNote(2130, 2, 'یادداشت من', title, full);
    expect(await user.notesFor(2130), {2: 'یادداشت من'});
    await user.setNote(2130, 2, '   ', title, full);
    expect(await user.notesFor(2130), isEmpty);
  });

  test('export → import into a fresh database round-trips', () async {
    await user.toggleBookmark(2130, title, full);
    await user.recordVisit(2130, title, full, couplet: 4);
    await user.setNote(2130, 0, 'خوب', title, full);
    final json = await user.exportJson();
    final db2 = AppDb(NativeDatabase.memory());
    addTearDown(db2.close);
    final user2 = UserRepository(db2);
    final n = await user2.importJson(json);
    expect(n, 3);
    expect(await user2.isBookmarked(2130), isTrue);
    expect(await user2.lastCouplet(2130), 4);
    expect(await user2.notesFor(2130), {0: 'خوب'});
  });

  test('user data survives pack install and uninstall', () async {
    await user.toggleBookmark(2130, title, full);
    final dir = Directory.systemTemp.createTempSync('ganj_user_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await importGdb(db, buildHafezGdb(dir), hafezPack);
    await uninstall(db, 2);
    expect(await user.isBookmarked(2130), isTrue);
  });

  test('badly typed backup rows are rejected, existing data untouched', () async {
    await user.toggleBookmark(1, 'a', 'A');
    const bad = '{"bookmarks":[{"poem_id":"x","couplet_index":-1,"poem_title":"a","full_title":"b","created":1}]}';
    await expectLater(user.importJson(bad), throwsFormatException);
    expect((await user.bookmarks()).single.poemId, 1);
  });

  test('v2 database upgrades to v3 keeping packs and cache', () async {
    final dir = Directory.systemTemp.createTempSync('ganj_v3_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/ganj.sqlite');
    // Build a v2 database with the v2 schema, then reopen with the current AppDb.
    final v2 = AppDb(NativeDatabase(file));
    await v2.customStatement("INSERT INTO api_cache (key, body, fetched_at) VALUES ('k', x'00', 1)");
    await v2.customStatement('DROP TABLE IF EXISTS bookmarks');
    await v2.customStatement('DROP TABLE IF EXISTS history');
    await v2.customStatement('DROP TABLE IF EXISTS notes');
    await v2.customStatement('PRAGMA user_version = 2');
    await v2.close();
    final v3 = AppDb(NativeDatabase(file));
    expect(await UserRepository(v3).toggleBookmark(1, 'a', 'A'), isTrue);
    final c = await v3.customSelect('SELECT count(*) AS c FROM api_cache').getSingle();
    expect(c.read<int>('c'), 1);
    await v3.close();
  });

  test('a v3 install (history without couplet_index) upgrades to v4', () async {
    final dir = Directory.systemTemp.createTempSync('ganj_v4_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/ganj.sqlite');
    final fresh = AppDb(NativeDatabase(file));
    await fresh.customStatement('DROP TABLE history');
    await fresh.customStatement(
      'CREATE TABLE history (poem_id INTEGER PRIMARY KEY, poem_title TEXT NOT NULL, full_title TEXT NOT NULL, '
      'visited INTEGER NOT NULL, scroll_offset REAL NOT NULL DEFAULT 0)',
    );
    await fresh.customStatement("INSERT INTO history VALUES (7, 'a', 'A', 1, 120.5)");
    await fresh.customStatement('PRAGMA user_version = 3');
    await fresh.close();
    final v4 = AppDb(NativeDatabase(file));
    final user = UserRepository(v4);
    expect(await user.lastCouplet(7), isNull); // old pixel offsets are not reinterpreted
    await user.recordVisit(7, 'a', 'A', couplet: 3);
    expect(await user.lastCouplet(7), 3);
    expect((await user.history()).single.poemId, 7);
    await v4.close();
  });
}
