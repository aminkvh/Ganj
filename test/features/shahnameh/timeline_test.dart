import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/timeline_river.dart';
import 'package:ganj/features/shahnameh/ui/timeline_tab.dart';
import 'package:ganj/features/shahnameh/ui/timeline_vertical.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> open(WidgetTester tester, String location, {bool isWide = false, String language = 'fa'}) async {
    isWide ? wide(tester) : phone(tester);
    final prefs = await mockPrefs({'language': language});
    await tester.pumpWidget(testAppRouted(location, prefs: prefs, overrides: shOverrides()));
    await settle(tester);
  }

  Finder story(String id) => find.byKey(ValueKey('story-$id'));

  testWidgets('phones open on the story list, ages in order', (tester) async {
    await open(tester, '/shahnameh');
    expect(find.byType(TimelineTab), findsOneWidget);
    expect(find.byType(TimelineVertical), findsOneWidget);
    expect(find.byKey(const ValueKey('age-header-pishdadian')), findsOneWidget);
    expect(story('kayumars'), findsOneWidget);
  });

  testWidgets('the age bar jumps to an age', (tester) async {
    await open(tester, '/shahnameh');
    await tester.tap(find.byKey(const ValueKey('age-bar-sasanian')));
    await settle(tester);
    final header = find.byKey(const ValueKey('age-header-sasanian'));
    final top = tester.getTopLeft(header).dy;
    expect(top, inInclusiveRange(0, 400), reason: 'the Sasanian header is scrolled into view');
  });

  testWidgets('a story card: title, summary, people, and onwards to the map', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    final card = story('sohrab');
    expect(card, findsOneWidget);
    expect(tester.getTopLeft(card).dy, inInclusiveRange(0, 860), reason: 'section 13 is brought into view');
    expect(find.descendant(of: card, matching: find.text('رستم و سهراب')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.widgetWithText(ActionChip, 'سهراب')), findsOneWidget);
    await tester.tap(find.descendant(of: card, matching: find.text('روی نقشه')));
    await settle(tester);
    expect(DefaultTabController.of(tester.element(find.byType(TabBarView))).index, 1);
  });

  testWidgets('a person chip on a story opens the person', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    await tester.tap(find.descendant(of: story('sohrab'), matching: find.widgetWithText(ActionChip, 'سهراب')));
    await settle(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
  });

  testWidgets('the river: ages, reigns, stories and lifelines of the main figures', (tester) async {
    await open(tester, '/shahnameh');
    await tester.tap(find.text('رود زمان'));
    await settle(tester);
    expect(find.byType(TimelineRiver), findsOneWidget);
    expect(find.byKey(const ValueKey('lifeline-60')), findsOneWidget, reason: 'Rostam');
  });

  testWidgets('wide screens open on the river', (tester) async {
    await open(tester, '/shahnameh', isWide: true);
    expect(find.byType(TimelineRiver), findsOneWidget);
  });

  testWidgets('adding someone to the river', (tester) async {
    await open(tester, '/shahnameh', isWide: true);
    expect(find.byKey(const ValueKey('lifeline-547')), findsNothing, reason: 'Manijeh is not a default');
    await tester.tap(find.text('افزودن شخصیت'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'منیژه');
    await settle(tester);
    await tester.tap(find.text('منیژه').last);
    await settle(tester);
    expect(find.byKey(const ValueKey('lifeline-547')), findsOneWidget);
  });

  testWidgets('in English the river reads left to right with English names', (tester) async {
    await open(tester, '/shahnameh', isWide: true, language: 'en');
    expect(
      find.descendant(of: find.byKey(const ValueKey('lifeline-60')), matching: find.text('Rostam')),
      findsOneWidget,
    );
    expect(Directionality.of(tester.element(find.byType(TimelineRiver))), TextDirection.ltr);
  });
}
