import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/features/poem/couplets.dart';
import 'package:ganj/features/poem/widgets/beyt_view.dart';
import 'package:ganj/features/search/search_service.dart';

import '../data/packs/pack_importer_test.dart' show hafezPack;
import '../support/fake_adapter.dart';
import '../support/fixtures.dart';
import '../support/gdb_builder.dart';
import '../support/test_app.dart';

Verse v(int order, int pos, String text, {int? ci}) =>
    Verse(vOrder: order, position: pos, text: text, coupletIndex: ci);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('couplet grouping', () {
    test('a verse missing coupletIndex among indexed ones never merges into the next couplet', () {
      final cs = groupCouplets([
        v(1, VersePosition.right, 'a', ci: 0),
        v(2, VersePosition.left, 'b', ci: 0),
        v(3, VersePosition.comment, 'note'), // no index from the source
        v(4, VersePosition.right, 'c', ci: 1),
        v(5, VersePosition.left, 'd', ci: 1),
      ]);
      expect(cs.map((c) => c.kind), [CoupletKind.beyt, CoupletKind.comment, CoupletKind.beyt]);
      expect(cs.last.verses.map((x) => x.text), ['c', 'd']);
    });
  });

  testWidgets('a three-line couplet keeps every line in the wide layout', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    final couplet = Couplet(
      index: 0,
      kind: CoupletKind.beyt,
      verses: [
        v(1, VersePosition.right, 'نخست', ci: 0),
        v(2, VersePosition.left, 'دوم', ci: 0),
        v(3, VersePosition.left, 'سوم', ci: 0),
      ],
    );
    await tester.pumpWidget(
      testApp(
        Scaffold(body: BeytView(couplet: couplet, wide: true, scale: 1)),
        prefs: prefs,
      ),
    );
    expect(find.text('سوم'), findsOneWidget);
  });

  testWidgets('screen readers hear bookmark, note and language marks', (tester) async {
    final prefs = await mockPrefs();
    final first = groupCouplets(poem2130().verses).first;
    await tester.pumpWidget(
      testApp(
        Scaffold(body: BeytView(couplet: first, wide: false, scale: 1, bookmarked: true, hasNote: true)),
        prefs: prefs,
      ),
    );
    final node = find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').contains('اَلا'));
    final label = tester.widget<Semantics>(node).properties.label ?? '';
    expect(label, contains('نشان‌دار'));
    expect(label, contains('یادداشت دارد'));
    expect(label, contains('عربی'));
  });

  test('a poem whose category lacks poet or cat still parses', () {
    final p = Poem.fromJson({
      'id': 1,
      'title': 't',
      'verses': <dynamic>[],
      'category': {'cat': null, 'poet': null},
    });
    expect(p.category, isNull);
  });

  testWidgets('a malformed poem link shows a friendly page, not a crash', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/poem/abc', prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('این صفحه پیدا نشد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('offline search', () {
    late Directory dir;
    late AppDb db;
    late SearchService service;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ganj_rem_');
      db = AppDb(NativeDatabase.memory());
      await importGdb(db, buildHafezGdb(dir), hafezPack);
      service = SearchService(
        db,
        GanjoorApi(
          dio: createDio(adapter: FakeAdapter({})..offline = true),
          cache: HttpCache(db),
        ),
      );
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('a word written without its half-space still matches (مشکلها → مشکل‌ها)', () async {
      expect((await service.searchLocal('مشکلها')).hits.map((h) => h.poemId), contains(2130));
      expect((await service.searchLocal('مشکل‌ها')).hits.map((h) => h.poemId), contains(2130));
      expect((await service.searchLocal('مشکل ها')).hits.map((h) => h.poemId), contains(2130));
    });

    test('upgrading from v4 rebuilds the index of installed packs (half-space search works)', () async {
      final file = File('${dir.path}/old.sqlite');
      final old = AppDb(NativeDatabase(file));
      await importGdb(old, buildHafezGdb(Directory(dir.path)..createSync(recursive: true)), hafezPack);
      // Simulate the v4 index, where a half-space became a space.
      await old.customStatement("UPDATE verse_fts SET norm = replace(norm, 'مشکلها', 'مشکل ها')");
      await old.customStatement('PRAGMA user_version = 4');
      await old.close();
      final upgraded = AppDb(NativeDatabase(file));
      final s = SearchService(
        upgraded,
        GanjoorApi(
          dio: createDio(adapter: FakeAdapter({})..offline = true),
          cache: HttpCache(upgraded),
        ),
      );
      expect((await s.searchLocal('مشکلها')).hits.map((h) => h.poemId), contains(2130));
      await upgraded.close();
    });

    test('% and _ in a short query are literal', () async {
      expect((await service.searchLocal('%')).hits, isEmpty);
      expect((await service.searchLocal('_')).hits, isEmpty);
    });

    test('offline results say the total is not known exactly', () async {
      final page = await service.search('ساقی');
      expect(page.offline, isTrue);
      expect(page.totalKnown, isFalse);
    });
  });
}
