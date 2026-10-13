import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_providers.dart';
import 'package:ganj/features/shahnameh/ui/timeline_river.dart';
import 'package:ganj/features/shahnameh/ui/timeline_vertical.dart';

import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

/// Findings of the final review, each pinned by a test.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> open(WidgetTester tester, String location, {bool isWide = false}) async {
    isWide ? wide(tester) : phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted(location, prefs: prefs, overrides: shOverrides()));
    await settle(tester);
  }

  TabController tabs(WidgetTester tester) => DefaultTabController.of(tester.element(find.byType(TabBarView)));
  final sheet = find.byKey(const ValueKey('place-sheet'));

  testWidgets('I1: a story chosen on the map is brought into view on the timeline', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    await tester.tap(await revealPin(tester, 'damavand'));
    await settle(tester);
    await tester.tap(find.descendant(of: sheet, matching: find.text('ضحاک ماردوش و کاوهٔ آهنگر')));
    await settle(tester);
    expect(tester.widget<TimelineVertical>(find.byType(TimelineVertical)).section, 4);
  });

  testWidgets('I2: a place opened from the timeline does not reopen on every visit to the map', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('story-sohrab')),
        matching: find.widgetWithText(ActionChip, 'سمنگان'),
      ),
    );
    await settle(tester);
    expect(sheet, findsOneWidget);
    Navigator.of(tester.element(sheet)).pop();
    await settle(tester);
    tabs(tester).animateTo(2);
    await settle(tester);
    tabs(tester).animateTo(1);
    await settle(tester);
    expect(sheet, findsNothing);
  });

  testWidgets('I2: a story closed on the map stays closed after switching tabs', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('story-sohrab')), matching: find.text('روی نقشه')));
    await settle(tester);
    final stops = find.byKey(const ValueKey('story-stops'));
    await tester.tap(find.descendant(of: stops, matching: find.byIcon(Icons.close)));
    await settle(tester);
    tabs(tester).animateTo(0);
    await settle(tester);
    tabs(tester).animateTo(1);
    await settle(tester);
    expect(stops, findsNothing);
  });

  testWidgets('I2: leaving the hub forgets what it was showing', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('story-sohrab')), matching: find.text('روی نقشه')));
    await settle(tester);
    GoRouter.of(tester.element(find.byType(TabBarView))).go('/');
    await settle(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/shahnameh?tab=map');
    await settle(tester);
    expect(find.byKey(const ValueKey('story-stops')), findsNothing);
  });

  testWidgets('I3: a gentle pinch zooms the river a little, not to its limit', (tester) async {
    await open(tester, '/shahnameh', isWide: true);
    double width() => tester
        .widgetList<CustomPaint>(find.descendant(of: find.byType(TimelineRiver), matching: find.byType(CustomPaint)))
        .map((p) => p.size.width)
        .reduce((a, b) => a > b ? a : b);
    final before = width();
    // The middle of the river (the names sit in a gutter at the side).
    final centre = tester.getCenter(find.byType(TimelineRiver)).translate(0, 120);
    final a = await tester.startGesture(centre.translate(-50, 0), pointer: 1);
    final b = await tester.startGesture(centre.translate(50, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(centre.translate(-50.0 - i, 0));
      await b.moveTo(centre.translate(50.0 + i, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // Fingers 100 → 120 apart: about 1.2×.
    expect(width() / before, closeTo(1.2, 0.08));
  });

  testWidgets('I4: in Persian the story-order arrow points right to left', (tester) async {
    await open(tester, '/shahnameh', isWide: true);
    final arrow = find.descendant(of: find.byType(TimelineRiver), matching: find.byIcon(Icons.arrow_forward));
    expect(arrow, findsOneWidget, reason: 'arrow_forward mirrors itself in RTL');
  });

  testWidgets("I5: a poem outside the Shahnameh doesn't load the Shahnameh's data", (tester) async {
    phone(tester);
    var loads = 0;
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [
          ...shOverrides(),
          shahnamehWorldProvider.overrideWith(() => _CountingWorld(() => loads++)),
        ].skip(1).toList(),
      ),
    );
    await settle(tester);
    expect(loads, 0);
  });
}

class _CountingWorld extends ShahnamehWorldNotifier {
  _CountingWorld(this.onLoad);

  final void Function() onLoad;

  @override
  Future<ShWorld> build() async {
    onLoad();
    return realWorld;
  }
}
