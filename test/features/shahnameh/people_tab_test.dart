import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/people_tab.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> open(WidgetTester tester, {String language = 'fa'}) async {
    phone(tester);
    final prefs = await mockPrefs({'language': language});
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
  }

  testWidgets('major figures come first', (tester) async {
    await open(tester);
    expect(find.byType(PeopleTab), findsOneWidget);
    expect(find.text('نامداران'), findsOneWidget);
    expect(find.text('رستم'), findsWidgets);
  });

  testWidgets('searching by an alias finds the person', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'تهمتن');
    await settle(tester);
    expect(find.descendant(of: find.byType(PersonRow), matching: find.text('رستم')), findsOneWidget);
    expect(find.text('نامداران'), findsNothing, reason: 'results replace the sections');
  });

  testWidgets('no match says so', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await settle(tester);
    expect(find.text('کسی پیدا نشد'), findsOneWidget);
  });

  testWidgets('people never seen in the story are still listed, under «دیگران»', (tester) async {
    await open(tester);
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('دیگران'), 2000, scrollable: list);
    expect(find.text('دیگران'), findsOneWidget);
  });

  testWidgets('English names in the English interface, with the Persian beside', (tester) async {
    await open(tester, language: 'en');
    await tester.enterText(find.byType(TextField), 'rostam');
    await settle(tester);
    final row = find.byType(PersonRow).first;
    expect(find.descendant(of: row, matching: find.text('Rostam')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('رستم')), findsOneWidget);
  });
}
