import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/library/book_audio.dart';
import 'package:ganj/features/library/book_audio_sheet.dart';
import 'package:ganj/features/player/audio_store.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_app.dart';

Map<String, dynamic> rec(int id, int poemId, String artist, int order, {int size = 1000}) => {
  'id': id,
  'poemId': poemId,
  'audioTitle': 't$id',
  'audioArtist': artist,
  'mp3Url': 'https://i.ganjoor.net/a/$id.mp3',
  'mp3SizeInBytes': size,
  'audioOrder': order,
  'inSyncWithText': true,
};

String catJson(int id, List<int> children, {List<int> poems = const []}) => jsonEncode({
  'poet': {'id': 2, 'name': 'حافظ', 'rootCatId': 9},
  'cat': {
    'id': id,
    'title': 'c$id',
    'children': [
      for (final c in children) {'id': c, 'title': 'c$c', 'fullUrl': '/x/$c'},
    ],
    'poems': [
      for (final p in poems) {'id': p, 'title': 'p$p', 'urlSlug': 'sh$p'},
    ],
  },
});

class MemoryStore implements AudioStore {
  final done = <int>[];
  final failing = <int>{};

  @override
  Future<void> download(Recitation r, {void Function(double)? onProgress}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (failing.contains(r.id)) throw Exception('unreachable');
    done.add(r.id);
  }

  @override
  bool isDownloaded(int id) => done.contains(id);

  @override
  Future<List<DownloadedRecitation>> listDownloaded() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A book (9) with poems of its own and a sub-book (24) that has poems; 25 has none.
FakeAdapter bookAdapter() => FakeAdapter({
  '/api/ganjoor/cat/9': catJson(9, [24, 25], poems: [100]),
  '/api/ganjoor/cat/24': catJson(24, [], poems: [101, 102]),
  '/api/ganjoor/cat/25': catJson(25, []),
  // The adapter answers by path alone, so every catId gets the same rows; fewer than a page ends paging.
  '/api/audio/published': jsonEncode([
    rec(1, 101, 'سهیل قاسمی', 1),
    rec(2, 101, 'فریدون فرح‌اندوز', 2, size: 3000),
    rec(3, 102, 'فریدون فرح‌اندوز', 1),
  ]),
});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  GanjoorApi apiWith(FakeAdapter a) {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    return GanjoorApi(
      dio: createDio(adapter: a),
      cache: HttpCache(db),
    );
  }

  test('lists the recitations of a book and its sub-books, only where there are poems', () async {
    final a = bookAdapter();
    final all = await listBookRecitations(apiWith(a), 9);
    final pages = a.requests.where((u) => u.path == '/api/audio/published').toList();
    expect(pages.map((u) => u.queryParameters['catId']), ['9', '24'], reason: '25 has no poems');
    expect(pages.first.queryParameters['PageSize'], '200');
    expect(all.map((r) => r.id), [1, 2, 3, 1, 2, 3]);
  });

  test('top of each poem, everything, and by reciter', () {
    final all = [
      Recitation.fromJson(rec(1, 101, 'سهیل قاسمی', 1)),
      Recitation.fromJson(rec(2, 101, 'فریدون فرح‌اندوز', 2, size: 3000)),
      Recitation.fromJson(rec(3, 102, 'فریدون فرح‌اندوز', 1)),
    ];
    final top = topOfEach(all);
    expect(top.recitations.map((r) => r.id), [1, 3]);
    expect(top.poems, 2);
    expect(top.totalBytes, 2000);
    final by = byReciter(all);
    expect(by.map((c) => c.artist), ['فریدون فرح‌اندوز', 'سهیل قاسمی']);
    expect(by.first.totalBytes, 4000);
    expect(by.first.poems, 2);
  });

  test('a job downloads one reciter, skips what is there, reports failures, and can be stopped', () async {
    final store = MemoryStore()..done.add(3);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final jobs = c.read(bookAudioJobProvider.notifier);
    final choice = BookAudioChoice([
      Recitation.fromJson(rec(2, 101, 'ف', 2)),
      Recitation.fromJson(rec(3, 102, 'ف', 1)),
    ], artist: 'ف');
    final run = jobs.start(9, 'غزلیات', choice, store);
    expect(c.read(bookAudioJobProvider)?.total, 2);
    expect(await jobs.start(9, 'غزلیات', choice, store), isNull, reason: 'one download at a time');
    expect(await run, BookAudioResult.done);
    expect(store.done, [3, 2]);
    expect(c.read(bookAudioJobProvider), isNull);

    store.failing.add(5);
    expect(
      await jobs.start(9, 'x', BookAudioChoice([Recitation.fromJson(rec(5, 1, 'a', 1))]), store),
      BookAudioResult.someFailed,
    );

    final stopped = jobs.start(
      9,
      'x',
      BookAudioChoice([for (var i = 10; i < 20; i++) Recitation.fromJson(rec(i, i, 'a', 1))]),
      store,
    );
    jobs.stop();
    expect(await stopped, BookAudioResult.stopped);
    expect(store.done.where((id) => id >= 10).length, lessThan(10));
  });

  testWidgets('the book sheet offers the choices and downloads one reciter after confirming', (tester) async {
    final store = MemoryStore();
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          appBar: AppBar(actions: const [BookAudioButton(catId: 24, title: 'غزلیات')]),
        ),
        prefs: prefs,
        overrides: [
          audioStoreProvider.overrideWithValue(store),
          ganjoorApiProvider.overrideWithValue(apiWith(bookAdapter())),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('book-audio')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book-audio-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-audio-all')), findsOneWidget);
    expect(find.text('بهترین خوانش هر شعر'), findsOneWidget);
    expect(find.text('سهیل قاسمی'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('book-audio-فریدون فرح‌اندوز')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بارگیری'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(store.done, [2, 3]);
    expect(find.text('خوانش‌های غزلیات بارگیری شد'), findsOneWidget);
  });
}
