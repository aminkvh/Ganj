import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/extras.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../../data/extras_test.dart' show ex;
import '../../support/fake_adapter.dart';
import '../../support/fixture_repository.dart';
import '../../support/scroll.dart';
import '../../support/test_app.dart';

const verse3 = 'به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;

  setUp(() => db = AppDb(NativeDatabase.memory()));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  Future<FakeAdapter> open(
    WidgetTester tester, {
    Map<String, String> extraRoutes = const {},
    PoemExtrasInfo? Function(PoemExtrasInfo? fromServer)? extras,
  }) async {
    final repo = FixtureRepository();
    if (extras != null) {
      final p = await repo.poem(2130);
      repo.poems[2130] = Poem(
        id: p.id,
        title: p.title,
        fullTitle: p.fullTitle,
        fullUrl: p.fullUrl,
        plainText: p.plainText,
        verses: p.verses,
        recitations: p.recitations,
        category: p.category,
        extras: extras(p.extras),
      );
    }
    final adapter = FakeAdapter({
      '/api/ganjoor/poem/2130/songs': ex('songs_2130.json'),
      '/api/ganjoor/poem/2130/comments': ex('comments_2130.json'),
      '/api/ganjoor/poem/2130/images': '[]',
      '/api/ganjoor/section/2130/0/related': ex('related_2130.json'),
      '/api/ganjoor/poem/2130/quoteds': ex('quoteds_2130.json'),
      ...extraRoutes,
    });
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: repo,
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
    return adapter;
  }

  Future<void> closeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox()); // unmount first: leaving the poem writes history
    await settle(tester);
    await tester.runAsync(db.close);
  }

  Future<void> expand(WidgetTester tester, String title) async {
    final f = find.text(title);
    await bringIntoView(tester, f);
    await tester.tap(f);
    await tester.pump();
    await settle(tester);
  }

  testWidgets('songs panel lists artists', (tester) async {
    await open(tester);
    await expand(tester, 'آهنگ‌ها');
    expect(find.text('ایرج بسطامی'), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('comments panel shows author, text and replies', (tester) async {
    await open(tester);
    await expand(tester, 'حاشیه‌ها');
    expect(find.text('رسته'), findsOneWidget);
    expect(find.textContaining('یزید'), findsWidgets);
    await closeAll(tester);
  });

  Future<void> toEnd(WidgetTester tester) async {
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var i = 0; i < 4; i++) {
      page.jumpTo(page.maxScrollExtent); // the end grows as panels appear
      await settle(tester);
    }
    expect(find.byKey(const ValueKey('poem-extras-2130'), skipOffstage: false), findsOneWidget);
  }

  Finder panel(String name) => find.byKey(ValueKey('panel-$name'));

  testWidgets('a panel with nothing in it is not shown', (tester) async {
    await open(tester); // Ganjoor has no manuscript images for this poem
    await toEnd(tester);
    expect(panel('images'), findsNothing);
    expect(find.text('تصاویر نسخه‌های خطی'), findsNothing);
    for (final shown in ['related', 'quoted', 'songs', 'comments']) {
      expect(panel(shown), findsOneWidget, reason: shown);
    }
    await closeAll(tester);
  });

  testWidgets('comments are asked for only when the reader nears the end of the poem', (tester) async {
    final adapter = await open(tester);
    bool asked() => adapter.requests.any((u) => u.path.endsWith('/comments'));
    expect(asked(), isFalse, reason: 'at the top of a long poem, nothing is asked yet');
    await toEnd(tester);
    expect(adapter.requests.where((u) => u.path.endsWith('/comments')), hasLength(1));
    expect(panel('comments'), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('what the poem says is empty is neither shown nor asked for', (tester) async {
    final adapter = await open(
      tester,
      extras: (_) => const PoemExtrasInfo(hasRelated: false, hasQuoted: false, images: [], songs: []),
      extraRoutes: {'/api/ganjoor/poem/2130/comments': '[]'},
    );
    await toEnd(tester);
    for (final name in ['related', 'quoted', 'images', 'songs', 'comments']) {
      expect(panel(name), findsNothing, reason: name);
    }
    final asked = adapter.requests.map((u) => u.path).toList();
    for (final path in ['/related', '/quoteds', '/images', '/songs']) {
      expect(asked.where((p) => p.endsWith(path)), isEmpty, reason: path);
    }
    expect(asked.where((p) => p.endsWith('/comments')), hasLength(1), reason: 'the poem does not count comments');
    await closeAll(tester);
  });

  testWidgets('images that come with the poem show without asking again', (tester) async {
    final adapter = await open(
      tester,
      extras: (e) => PoemExtrasInfo(
        hasRelated: e!.hasRelated,
        hasQuoted: e.hasQuoted,
        songs: const [],
        images: const [PoemImage(thumb: '', target: 'https://museum.ganjoor.net/x', alt: 'نسخهٔ قزوینی')],
      ),
    );
    await expand(tester, 'تصاویر نسخه‌های خطی');
    expect(find.text('نسخهٔ قزوینی'), findsOneWidget);
    expect(panel('songs'), findsNothing);
    expect(adapter.requests.where((u) => u.path.endsWith('/images') || u.path.endsWith('/songs')), isEmpty);
    await closeAll(tester);
  });

  testWidgets('a poem read offline (from a pack) shows no extra panels and asks for none', (tester) async {
    final adapter = await open(tester, extras: (_) => null);
    await toEnd(tester);
    for (final name in ['related', 'quoted', 'images', 'songs', 'comments']) {
      expect(panel(name), findsNothing, reason: name);
    }
    expect(adapter.requests.where((u) => u.path.contains('/2130/')), isEmpty);
    await closeAll(tester);
  });

  testWidgets('bookmark button persists the bookmark', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('نشان‌گذاری'));
    await settle(tester);
    expect(await tester.runAsync(() => UserRepository(db).isBookmarked(2130)), isTrue);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('a note on a beyt is saved and marked', (tester) async {
    await open(tester);
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('یادداشت'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-field')), 'بیت محبوب');
    await tester.tap(find.text('ذخیره'));
    await settle(tester);
    expect(await tester.runAsync(() => UserRepository(db).notesFor(2130)), {1: 'بیت محبوب'});
    expect(find.byIcon(Icons.sticky_note_2), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('leaving the poem records the couplet at the top of the screen', (tester) async {
    await open(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final couplet = await tester.runAsync(() => UserRepository(db).lastCouplet(2130));
    expect(couplet, greaterThan(0));
    await closeAll(tester);
  });

  Map<String, String> literaryRoutes({bool tagged = true}) => {
    '/api/ganjoor/literary/stats/overview': tagged ? ex('literary_overview.json') : '{"poets": []}',
    '/api/ganjoor/literary/devices': ex('literary_devices.json'),
    '/api/ganjoor/literary/poem/2130/tags': ex('literary_tags_2130.json'),
  };

  testWidgets('the beyt sheet lists its literary devices', (tester) async {
    await open(tester, extraRoutes: literaryRoutes());
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    expect(find.text('آرایه‌های ادبی'), findsWidgets);
    expect(find.textContaining('مستعارٌمنه: نافه‌ای'), findsOneWidget);
    expect(find.textContaining('معنای دوم: به رنج و محنت افتادن'), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('the literary devices panel lists tagged beyts and credits the corpus', (tester) async {
    await open(tester, extraRoutes: literaryRoutes());
    await expand(tester, 'آرایه‌های ادبی');
    expect(find.textContaining('بیت ۲'), findsOneWidget);
    expect(find.textContaining('بیت ۳'), findsOneWidget);
    expect(find.textContaining('پیکرهٔ متن ادبی فارسی'), findsOneWidget);
    await closeAll(tester);
  });

  testWidgets('poets Ganjoor has not tagged: no panel, no tags request', (tester) async {
    final adapter = await open(tester, extraRoutes: literaryRoutes(tagged: false));
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    expect(find.text('آرایه‌های ادبی'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    await bringIntoView(tester, find.text('آهنگ‌ها'));
    expect(find.text('آرایه‌های ادبی'), findsNothing);
    expect(adapter.requests.where((u) => u.path.contains('/literary/poem/')), isEmpty);
    await closeAll(tester);
  });
}
