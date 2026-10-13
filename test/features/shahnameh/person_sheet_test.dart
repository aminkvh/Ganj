import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/people_tab.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Finder inSheet(Finder f) => find.descendant(of: find.byType(PersonPanel), matching: f);

  Future<void> openRostam(WidgetTester tester, {String language = 'fa', FakeAdapter? adapter}) async {
    phone(tester);
    final prefs = await mockPrefs({'language': language});
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh?tab=people',
        prefs: prefs,
        overrides: shOverrides(adapter: adapter),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField), language == 'en' ? 'rostam' : 'تهمتن');
    await settle(tester);
    await tester.tap(find.byType(PersonRow).first);
    await settle(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
  }

  testWidgets('a person opens in a sheet with names, aliases and where they appear', (tester) async {
    await openRostam(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
    expect(inSheet(find.text('رستم')), findsWidgets);
    expect(inSheet(find.textContaining('تهمتن')), findsOneWidget);
    expect(inSheet(find.text('حضور در داستان‌ها')), findsOneWidget);
  });

  testWidgets('relatives read from the person: father, mother, son', (tester) async {
    await openRostam(tester);
    expect(inSheet(find.text('خویشاوندان')), findsOneWidget);
    final zal = find.byKey(const ValueKey('kin-54'));
    await scrollTo(tester, zal);
    expect(find.descendant(of: zal, matching: find.text('پدر')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kin-58')), matching: find.text('مادر')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kin-128')), matching: find.text('پسر')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kin-48')), matching: find.text('نیا')), findsOneWidget);
  });

  testWidgets('evidence couplets unfold from the live data', (tester) async {
    await openRostam(tester);
    final chip = find.descendant(of: find.byKey(const ValueKey('kin-54')), matching: find.text('مستند (۳۱)'));
    await scrollTo(tester, chip);
    await tester.tap(chip);
    await settle(tester);
    expect(inSheet(find.textContaining('غم آمد به سر')), findsWidgets);
  });

  testWidgets('ties name the role: «قاتلِ» for the person, «قاتل» for the other', (tester) async {
    await openRostam(tester);
    final ties = find.byKey(const ValueKey('tie-128-A:14'));
    await scrollTo(tester, ties);
    expect(find.descendant(of: ties, matching: find.text('قاتلِ')), findsOneWidget);
  });

  testWidgets('tapping a relative opens them in the same sheet, with a way back', (tester) async {
    await openRostam(tester);
    final zal = find.descendant(of: find.byKey(const ValueKey('kin-54')), matching: find.text('زال'));
    await scrollTo(tester, zal);
    await tester.tap(zal);
    await settle(tester);
    expect(inSheet(find.textContaining('دستان')), findsWidgets, reason: "Zal's alias");
    await tester.tap(inSheet(find.byIcon(Icons.arrow_back)));
    await settle(tester);
    expect(inSheet(find.textContaining('تهمتن')), findsOneWidget);
  });

  testWidgets('tagged couplets list the poems', (tester) async {
    await openRostam(tester);
    final title = inSheet(find.textContaining('زادن رستم'));
    await scrollTo(tester, title);
    expect(title, findsOneWidget);
  });

  testWidgets('offline: everything bundled still shows; only live parts offer a retry', (tester) async {
    final offline = FakeAdapter({})..offline = true;
    await openRostam(tester, adapter: offline);
    final zal = find.byKey(const ValueKey('kin-54'));
    await scrollTo(tester, zal);
    expect(zal, findsOneWidget);
    expect(inSheet(find.text('این بخش بارگیری نشد')), findsWidgets);
  });

  testWidgets('in English', (tester) async {
    await openRostam(tester, language: 'en');
    expect(inSheet(find.text('Rostam')), findsWidgets);
    final zal = find.byKey(const ValueKey('kin-54'));
    await scrollTo(tester, zal);
    expect(find.descendant(of: zal, matching: find.text('Father')), findsOneWidget);
    expect(find.descendant(of: zal, matching: find.text('Zal')), findsOneWidget);
  });
}
