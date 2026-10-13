import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/person_hover.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// With a mouse (Windows, Linux, macOS), hovering a person shows who they are.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<TestGesture> mouse(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    return g;
  }

  Future<void> open(WidgetTester tester, String location) async {
    wide(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted(location, prefs: prefs, overrides: shOverrides()));
    await settle(tester);
  }

  testWidgets('hovering a person in the network shows their card', (tester) async {
    await open(tester, '/shahnameh?tab=people&focus=60');
    final m = await mouse(tester);
    await m.moveTo(tester.getCenter(find.byKey(const ValueKey('network-canvas'))));
    await tester.pumpAndSettle();
    final card = find.byType(PersonHoverCard);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('رستم')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('پیوند')), findsOneWidget);
    // Moving away hides it.
    await m.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
  });

  testWidgets('hovering a box in a family tree shows the card', (tester) async {
    await open(tester, '/shahnameh/tree/64');
    final m = await mouse(tester);
    await m.moveTo(tester.getCenter(find.byKey(const ValueKey('tree-node-64'))));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PersonHoverCard), findsOneWidget);
  });

  testWidgets("hovering a name on the river shows the card", (tester) async {
    await open(tester, '/shahnameh');
    final m = await mouse(tester);
    await m.moveTo(tester.getCenter(find.byKey(const ValueKey('lifeline-60'))));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PersonHoverCard), findsOneWidget);
  });

  testWidgets('the card: name, English name, description and appearances', (tester) async {
    wide(tester);
    final prefs = await mockPrefs();
    final p = realWorld.people.values.firstWhere((p) => p.en != null && (p.description?.isNotEmpty ?? false));
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Center(
            child: PersonHoverCard(world: realWorld, id: p.id),
          ),
        ),
        prefs: prefs,
        overrides: shOverrides(),
      ),
    );
    await settle(tester);
    expect(find.text(p.name), findsOneWidget);
    expect(find.text(p.en!), findsOneWidget);
    expect(find.textContaining(p.description!.substring(0, 10)), findsOneWidget);
  });
}
