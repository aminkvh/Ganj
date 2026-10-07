import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/features/category/category_screen.dart';
import 'package:ganj/features/library/library_providers.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/poet/poet_screen.dart';

import '../data/packs/pack_importer_test.dart' show hafezPack;
import '../support/fixture_repository.dart';
import '../support/test_app.dart';
import 'library/library_screen_test.dart' show FakeInstaller;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a poet\'s page can download the poet for offline reading', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoetScreen(id: 2),
        prefs: prefs,
        db: db,
        repo: FixtureRepository(),
        overrides: [
          packCatalogProvider.overrideWith((ref) async => [hafezPack]),
          packInstallerProvider.overrideWithValue(FakeInstaller(db)),
        ],
      ),
    );
    await settle(tester);
    final get = find.byKey(const ValueKey('poet-pack-get'));
    expect(get, findsOneWidget);
    await tester.tap(get);
    await settle(tester);
    expect(await tester.runAsync(() => installedPoets(db)), {2});
    expect(find.byKey(const ValueKey('poet-pack-get')), findsNothing);
    expect(find.textContaining('روی دستگاه'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a poet with no offline pack shows no download button', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoetScreen(id: 2),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [packCatalogProvider.overrideWith((ref) async => [])],
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('poet-pack-get')), findsNothing);
  });

  for (final (name, screen) in [
    ('poem', const PoemScreen(id: 2130) as Widget),
    ('poet', const PoetScreen(id: 2) as Widget),
    ('section', const CategoryScreen(id: 24) as Widget),
  ]) {
    testWidgets('the $name page has a home button', (tester) async {
      final prefs = await mockPrefs();
      await tester.pumpWidget(
        testApp(
          screen,
          prefs: prefs,
          repo: FixtureRepository(),
          overrides: [packCatalogProvider.overrideWith((ref) async => [])],
        ),
      );
      await settle(tester);
      expect(find.byTooltip('خانه'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }

  testWidgets('home button goes back to the home page from deep inside', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/poem/2130', prefs: prefs));
    await settle(tester);
    await tester.tap(find.byTooltip('خانه'));
    await settle(tester);
    expect(find.byKey(const ValueKey('poet-filter')), findsOneWidget);
  });
}
