import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';

import '../support/scroll.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  testWidgets('the app speaks English when chosen, laid out left to right', (tester) async {
    final prefs = await mockPrefs({'language': 'en'});
    await tester.pumpWidget(testAppRouted('/settings', prefs: prefs));
    await settle(tester);
    expect(find.text('Settings & about'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Settings & about'))), TextDirection.ltr);
    await tester.scrollUntilVisible(find.text('Designed and built by Amin Akbari'), 300);
    expect(find.text('Designed and built by Amin Akbari'), findsOneWidget);
  });

  testWidgets('switching the language in settings changes the interface at once', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/settings', prefs: prefs));
    await settle(tester);
    expect(find.text('تنظیمات و درباره'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('English')));
    await settle(tester);
    expect(find.text('Settings & about'), findsOneWidget);
    expect(prefs.getString('language'), 'en');
  });

  testWidgets('in the English interface the poem itself stays right to left', (tester) async {
    final prefs = await mockPrefs({'language': 'en'});
    await tester.pumpWidget(testAppRouted('/poem/2130', prefs: prefs));
    await settle(tester);
    final verse = find.text('به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید');
    await bringIntoView(tester, verse);
    expect(verse, findsOneWidget);
    expect(Directionality.of(tester.element(verse)), TextDirection.rtl);
    expect(find.byTooltip('Find in poem'), findsOneWidget);
  });

  testWidgets('in English, poets, centuries, sections and poem titles read in English', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs({'language': 'en'});
    await tester.pumpWidget(testAppRouted('/', prefs: prefs));
    await settle(tester);
    expect(find.text('Hafez'), findsWidgets);
    expect(find.text('8th century AH'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('poet-2')).first);
    await settle(tester);
    expect(find.text('Hafez'), findsWidgets); // poet page title
    expect(find.text('Ghazals'), findsWidgets);
    await tester.pumpWidget(testAppRouted('/cat/24', prefs: prefs));
    await settle(tester);
    expect(find.text('Ghazal 1'), findsWidgets);
  });

  testWidgets('in Persian nothing is translated', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/cat/24', prefs: prefs));
    await settle(tester);
    expect(find.text('Ghazal 1'), findsNothing);
    expect(find.text('غزل شمارهٔ ۱'), findsWidgets);
  });

  test('numbers follow the interface language', () {
    expect(localDigits(42), '۴۲');
    latinNumbers = true;
    expect(localDigits(42), '42');
    expect(localDecimal(1.5), '1.5');
    latinNumbers = false;
    expect(localDecimal(1.5), '۱٫۵');
  });
}
