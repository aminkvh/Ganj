import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/category/category_screen.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/poet/poet_screen.dart';
import 'package:ganj/widgets/external_link.dart';

import '../support/fixture_repository.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  late List<Uri> opened;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    opened = [];
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        screen,
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [
          urlLauncherProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
      ),
    );
    await settle(tester);
  }

  testWidgets('a poem opens its own page on ganjoor.net', (tester) async {
    await pump(tester, const PoemScreen(id: 2130));
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشاهده در گنجور'));
    await settle(tester);
    expect(opened, [Uri.parse('https://ganjoor.net/hafez/ghazal/sh1')]);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('poem text, meanings and the poet bio can be selected and copied', (tester) async {
    await pump(tester, const PoemScreen(id: 2130));
    final verse = find.text(poem2130().verses.first.text);
    expect(find.ancestor(of: verse, matching: find.byType(SelectionArea)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await pump(tester, const PoetScreen(id: 2));
    expect(find.descendant(of: find.byType(SelectionArea), matching: find.byType(Text)), findsWidgets);
  });

  testWidgets('a poet opens their page on ganjoor.net', (tester) async {
    await pump(tester, const PoetScreen(id: 2));
    await tester.tap(find.byTooltip('مشاهده در گنجور'));
    await settle(tester);
    expect(opened, [Uri.parse('https://ganjoor.net/hafez')]);
  });

  testWidgets('a section opens its page on ganjoor.net', (tester) async {
    await pump(tester, const CategoryScreen(id: 24));
    await tester.tap(find.byTooltip('مشاهده در گنجور'));
    await settle(tester);
    expect(opened.single.toString(), 'https://ganjoor.net/hafez/ghazal');
  });
}
