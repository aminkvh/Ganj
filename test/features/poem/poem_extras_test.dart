import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
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

  Future<void> open(WidgetTester tester, {Map<String, String> extraRoutes = const {}}) async {
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
        repo: FixtureRepository(),
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

  testWidgets('empty panel says there is nothing', (tester) async {
    await open(tester);
    await expand(tester, 'تصاویر نسخه‌های خطی');
    expect(find.text('موردی نیست'), findsOneWidget);
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
}
