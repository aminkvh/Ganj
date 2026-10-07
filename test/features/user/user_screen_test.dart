import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/user/user_screen.dart';
import 'package:ganj/widgets/external_link.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  Future<(AppDb, UserRepository)> pump(WidgetTester tester, Future<void> Function(UserRepository) seed) async {
    final db = AppDb(NativeDatabase.memory());
    final user = UserRepository(db);
    await tester.runAsync(() => seed(user));
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const UserScreen(), prefs: prefs, db: db));
    await settle(tester);
    return (db, user);
  }

  testWidgets('bookmarks tab lists poems and beyts; delete removes', (tester) async {
    final (db, user) = await pump(tester, (u) async {
      await u.toggleBookmark(2130, 'غزل شمارهٔ ۱', 'حافظ » غزلیات » غزل شمارهٔ ۱');
      await u.toggleBookmark(2131, 'غزل شمارهٔ ۲', 'حافظ » غزلیات » غزل شمارهٔ ۲', couplet: 2);
    });
    expect(find.text('حافظ » غزلیات » غزل شمارهٔ ۱'), findsOneWidget);
    expect(find.textContaining('بیت ۳'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('del-bookmark-2130--1')));
    await settle(tester);
    expect(find.text('حافظ » غزلیات » غزل شمارهٔ ۱'), findsNothing);
    expect(await tester.runAsync(() => user.isBookmarked(2130)), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('history and notes tabs show entries', (tester) async {
    final (db, _) = await pump(tester, (u) async {
      await u.recordVisit(2130, 'غزل شمارهٔ ۱', 'حافظ » غزلیات » غزل شمارهٔ ۱', couplet: 2);
      await u.setNote(2130, 0, 'یادداشت آزمایشی', 'غزل شمارهٔ ۱', 'حافظ » غزلیات » غزل شمارهٔ ۱');
    });
    await tester.tap(find.text('تاریخچه'));
    await settle(tester);
    expect(find.text('حافظ » غزلیات » غزل شمارهٔ ۱'), findsOneWidget);
    await tester.tap(find.text('یادداشت‌ها'));
    await settle(tester);
    expect(find.text('یادداشت آزمایشی'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('import merges pasted JSON', (tester) async {
    final source = UserRepository(AppDb(NativeDatabase.memory()));
    final json = await tester.runAsync(() async {
      await source.toggleBookmark(77000, 'شمارهٔ ۲۴', 'حافظ » اشعار منتسب » شمارهٔ ۲۴');
      return source.exportJson();
    });
    final (db, user) = await pump(tester, (_) async {});
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ورود از پشتیبان'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('import-field')), json!);
    await tester.tap(find.text('ورود'));
    await settle(tester);
    expect(await tester.runAsync(() => user.isBookmarked(77000)), isTrue);
    expect(find.text('حافظ » اشعار منتسب » شمارهٔ ۲۴'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  test('entries link to their beyt', () {
    final t = DateTime(2026);
    expect(poemRoute(UserEntry(poemId: 2131, coupletIndex: 2, title: '', fullTitle: '', time: t)), '/poem/2131?c=2');
    expect(poemRoute(UserEntry(poemId: 2130, coupletIndex: -1, title: '', fullTitle: '', time: t)), '/poem/2130');
  });

  testWidgets('corrupted rows show an error instead of spinning forever', (tester) async {
    final (db, _) = await pump(tester, (u) async {
      await u.toggleBookmark(1, 'a', 'A');
    });
    await tester.runAsync(() => db.customStatement("UPDATE bookmarks SET created = 'oops'"));
    await tester.pumpWidget(const SizedBox());
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const UserScreen(), prefs: prefs, db: db));
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('خواندن داده‌ها ممکن نشد'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('external links: invalid or failing links explain themselves', (tester) async {
    final prefs = await mockPrefs();
    final opened = <Uri>[];
    var result = true;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => openExternal(context, '', launcher: (u) async => true),
                  child: const Text('empty'),
                ),
                TextButton(
                  onPressed: () => openExternal(context, 'javascript:alert(1)', launcher: (u) async => true),
                  child: const Text('js'),
                ),
                TextButton(
                  onPressed: () => openExternal(
                    context,
                    'https://museum.ganjoor.net/x',
                    launcher: (u) async {
                      opened.add(u);
                      return result;
                    },
                  ),
                  child: const Text('ok'),
                ),
              ],
            ),
          ),
        ),
        prefs: prefs,
      ),
    );
    await tester.tap(find.text('empty'));
    await tester.pumpAndSettle();
    expect(find.text('پیوند نامعتبر است'), findsOneWidget);
    await tester.tap(find.text('js'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'museum.ganjoor.net');
    result = false;
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(find.text('باز کردن پیوند ممکن نشد'), findsOneWidget);
  });
}
