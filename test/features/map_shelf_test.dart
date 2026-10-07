import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/category/category_screen.dart';
import 'package:ganj/features/home/book_shelf.dart';
import 'package:ganj/features/home/poet_tile.dart';
import 'package:ganj/features/map/poets_map_screen.dart';
import 'package:ganj/features/poet/poet_screen.dart';

import '../data/extras_test.dart' show ex;
import '../support/fake_adapter.dart';
import '../support/fixture_repository.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// The map and the shelf sit at the end of the poets of the open era, like the site's home page.
  Future<void> scrollToEnd(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.descendant(of: find.byType(PoetGrid).first, matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('book spine colours match ganjoor.net', () {
    // Values from the site's hashBookColorHue() in bk.js.
    expect(bookHue(2204), 140);
    expect(bookHue(727), 100);
    expect(bookHue(1365), 297);
    expect(bookHue(123456789), 315);
  });

  testWidgets('home has the bookshelf; a spine opens to its cover, then to the book', (tester) async {
    tall(tester);
    final apiDb = AppDb(NativeDatabase.memory());
    final adapter = FakeAdapter({'/api/ganjoor/book-catalog': ex('book_catalog.json')});
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/',
        prefs: prefs,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: adapter),
              cache: HttpCache(apiDb),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    await scrollToEnd(tester, find.byKey(const ValueKey('book-2204')));
    expect(find.text('قفسهٔ کتاب‌ها'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('book-2204')));
    await settle(tester);
    expect(find.byKey(const ValueKey('book-cover-2204')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('book-cover-2204')));
    await settle(tester);
    expect(tester.widget<CategoryScreen>(find.byType(CategoryScreen)).id, 2204);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(apiDb.close);
  });

  testWidgets('the home search finds books as well as poets', (tester) async {
    tall(tester);
    final apiDb = AppDb(NativeDatabase.memory());
    final adapter = FakeAdapter({'/api/ganjoor/book-catalog': ex('book_catalog.json')});
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/',
        prefs: prefs,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: adapter),
              cache: HttpCache(apiDb),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'اخلاق');
    await settle(tester);
    expect(find.byKey(const ValueKey('book-result-2156')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-result-2863')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-result-2204')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'عبید');
    await settle(tester);
    expect(find.byKey(const ValueKey('book-result-2156')), findsOneWidget); // by its poet
    await tester.tap(find.byKey(const ValueKey('book-result-2156')));
    await settle(tester);
    expect(tester.widget<CategoryScreen>(find.byType(CategoryScreen)).id, 2156);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(apiDb.close);
  });

  testWidgets('home without the book list just has no shelf', (tester) async {
    tall(tester);
    final apiDb = AppDb(NativeDatabase.memory());
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/',
        prefs: prefs,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: FakeAdapter({})..offline = true),
              cache: HttpCache(apiDb),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    expect(find.text('قفسهٔ کتاب‌ها'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(apiDb.close);
  });

  testWidgets('the map entry on home opens the birthplace map', (tester) async {
    tall(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted('/', prefs: prefs, overrides: [mapTileLayerProvider.overrideWithValue(const SizedBox())]),
    );
    await settle(tester);
    await scrollToEnd(tester, find.byKey(const ValueKey('home-map')));
    await tester.tap(find.byKey(const ValueKey('home-map')));
    await settle(tester);
    expect(find.byType(PoetsMapScreen), findsOneWidget);
  });

  testWidgets('the map shows an era\'s poets at their birthplaces; a poet opens', (tester) async {
    tall(tester);
    final eras = [
      for (final c in await FixtureRepository().centuries())
        if (c.id != 0 && c.poets.any((p) => p.birthLatitude != null)) c,
    ];
    final first = eras.first.poets.firstWhere((p) => p.birthLatitude != null);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted('/map', prefs: prefs, overrides: [mapTileLayerProvider.overrideWithValue(const SizedBox())]),
    );
    await settle(tester);
    expect(find.text(eras.first.name), findsWidgets);
    expect(find.byKey(ValueKey('map-poet-${first.id}')), findsOneWidget);
    // The slider steps through eras.
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await settle(tester);
    expect(find.text(eras.last.name), findsWidgets);
    await tester.drag(find.byType(Slider), const Offset(2000, 0));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('map-poet-${first.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('map-open-poet')));
    await settle(tester);
    expect(tester.widget<PoetScreen>(find.byType(PoetScreen)).id, first.id);
  });
}
