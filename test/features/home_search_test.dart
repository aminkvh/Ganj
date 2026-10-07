import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/search/search_screen.dart';

import '../data/extras_test.dart' show ex;
import '../support/fake_adapter.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

/// One search box on home, like ganjoor.net: typing filters poets and books, Enter searches
/// the poems, × clears, and a query that matches nothing leaves the home page as it was.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final box = find.byKey(const ValueKey('poet-filter'));

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    final db = AppDb(NativeDatabase.memory());
    await tester.pumpWidget(
      testAppRouted(
        '/',
        prefs: prefs,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: FakeAdapter({'/api/ganjoor/book-catalog': ex('book_catalog.json')})),
              cache: HttpCache(db),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
  }

  testWidgets('Enter searches the poems for what was typed', (tester) async {
    await pumpHome(tester);
    await tester.enterText(box, 'ساقی');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    final s = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(s.query, 'ساقی');
    expect(s.meaning, isFalse);
  });

  testWidgets('× clears the box and brings the home page back', (tester) async {
    await pumpHome(tester);
    await tester.enterText(box, 'حافظ');
    await settle(tester);
    expect(find.byTooltip('پاک کردن'), findsOneWidget);
    await tester.tap(find.byTooltip('پاک کردن'));
    await settle(tester);
    expect(tester.widget<TextField>(box).controller!.text, isEmpty);
    expect(find.byType(TabBar), findsOneWidget); // eras are back
    expect(find.byTooltip('پاک کردن'), findsNothing);
  });

  testWidgets('a query matching no poet or book leaves the home page as it was', (tester) async {
    await pumpHome(tester);
    await tester.enterText(box, 'زززز');
    await settle(tester);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byKey(const ValueKey('poet-2')), findsWidgets);
  });

  testWidgets('a query matching only a book still shows that book', (tester) async {
    await pumpHome(tester);
    await tester.enterText(box, 'اخلاق ناصری');
    await settle(tester);
    expect(find.byKey(const ValueKey('book-result-2863')), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });
}
