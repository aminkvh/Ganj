import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/reader_chips.dart';

import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> chips(WidgetTester tester, int poemId, {String language = 'fa'}) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        Scaffold(body: ShahnamehPeopleChips(poemId: poemId)),
        prefs: prefs,
        overrides: shOverrides(),
        language: language,
      ),
    );
    await settle(tester);
  }

  testWidgets('a Shahnameh poem lists the people in it', (tester) async {
    await chips(tester, 1403);
    expect(find.text('نامبردگان'), findsOneWidget);
    for (final n in ['سیندخت', 'سام', 'زال', 'رستم']) {
      expect(find.widgetWithText(ActionChip, n), findsOneWidget, reason: n);
    }
  });

  testWidgets('and the places Ganjoor tagged in it', (tester) async {
    await chips(tester, 1354);
    expect(find.widgetWithText(ActionChip, 'فریدون'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'گنگ دژهوخت (بیت‌المقدس)'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'اروندرود'), findsOneWidget);
  });

  testWidgets('a person chip opens the person', (tester) async {
    await chips(tester, 1403);
    await tester.tap(find.widgetWithText(ActionChip, 'زال'));
    await settle(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
  });

  testWidgets('English names in the English interface', (tester) async {
    await chips(tester, 1403, language: 'en');
    expect(find.text('People'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Zal'), findsOneWidget);
  });

  testWidgets('other poems show nothing', (tester) async {
    await chips(tester, 2130);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('نامبردگان'), findsNothing);
  });

  testWidgets('a Shahnameh poem page carries the chips', (tester) async {
    phone(tester);
    // The Hafez fixture poem, moved into the Shahnameh's «منوچهر» section as poem 1403.
    final j = jsonDecode(File('test/fixtures/poem_2130.json').readAsStringSync()) as Map<String, dynamic>;
    j['id'] = 1403;
    (j['category'] as Map<String, dynamic>)['cat'] = jsonDecode(
      File('test/fixtures/cat_35.json').readAsStringSync(),
    )['cat'];
    final repo = FixtureRepository()..poems[1403] = Poem.fromJson(j);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 1403), prefs: prefs, repo: repo, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(ShahnamehPeopleChips), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'زال'), findsOneWidget);
  });

  testWidgets("other books' poem pages don't", (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository(), overrides: shOverrides()),
    );
    await settle(tester);
    expect(find.byType(ShahnamehPeopleChips), findsNothing);
  });
}
