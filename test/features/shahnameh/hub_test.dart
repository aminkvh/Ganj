import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/hub_screen.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/router.dart';
import 'package:ganj/features/shahnameh/ui/shahnameh_entry.dart';
import 'package:ganj/widgets/error_retry.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  testWidgets('the hub opens with its four parts', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(ShahnamehHubScreen), findsOneWidget);
    expect(find.text('جهان شاهنامه'), findsOneWidget);
    for (final t in ['گاه‌شمار', 'نقشه', 'نامبردگان', 'تبارنامه‌ها']) {
      expect(find.widgetWithText(Tab, t), findsOneWidget, reason: t);
    }
  });

  testWidgets('in English', (tester) async {
    phone(tester);
    final prefs = await mockPrefs({'language': 'en'});
    await tester.pumpWidget(testAppRouted('/shahnameh', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.text('World of the Shahnameh'), findsOneWidget);
    for (final t in ['Timeline', 'Map', 'People', 'Family trees']) {
      expect(find.widgetWithText(Tab, t), findsOneWidget, reason: t);
    }
  });

  testWidgets('?tab= opens a given part', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(DefaultTabController.of(tester.element(find.byType(TabBarView))).index, 2);
  });

  testWidgets('the Shahnameh and its sections show a banner into the hub', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/cat/35', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(ShahnamehBanner), findsOneWidget);
    await tester.tap(find.byType(ShahnamehBanner));
    await settle(tester);
    expect(find.byType(ShahnamehHubScreen), findsOneWidget);
  });

  testWidgets('other books have no banner', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/cat/24', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(ShahnamehBanner), findsNothing);
  });

  testWidgets('the home menu leads to the hub', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('جهان شاهنامه'));
    await settle(tester);
    expect(find.byType(ShahnamehHubScreen), findsOneWidget);
  });

  testWidgets('a broken bundle shows a retry, not a crash', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh', prefs: prefs, overrides: shOverrides(brokenWorld: true)));
    await settle(tester);
    expect(find.byType(ErrorRetry), findsOneWidget);
  });

  testWidgets('a person has a deep link', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh/person/60', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
    expect(find.textContaining('تهمتن'), findsOneWidget);
  });

  testWidgets('an unknown person id is a not-found page', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh/person/abc', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(NotFoundScreen), findsOneWidget);
  });

  testWidgets('a person id the Shahnameh does not know says so instead of spinning', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh/person/99999', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('این صفحه پیدا نشد'), findsOneWidget);
  });
}
