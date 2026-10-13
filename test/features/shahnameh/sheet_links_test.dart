import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/shahnameh/ui/people_tab.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/tree_view.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// Sheets sit above every page: a link from a sheet to a page closes the sheet first,
/// or the page would open hidden underneath it.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> openRostamSheet(WidgetTester tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'تهمتن');
    await settle(tester);
    await tester.tap(find.byType(PersonRow).first);
    await settle(tester);
  }

  Finder panelScroll() => find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first;

  testWidgets('a tagged couplet on the person sheet opens its poem, in view', (tester) async {
    await openRostamSheet(tester);
    final poem = find.descendant(of: find.byType(PersonPanel), matching: find.textContaining('زادن رستم'));
    await tester.scrollUntilVisible(poem, 300, scrollable: panelScroll());
    await tester.ensureVisible(poem);
    await tester.pumpAndSettle();
    await tester.tap(poem);
    await settle(tester);
    expect(find.byType(PersonPanel), findsNothing);
    expect(find.byType(PoemScreen), findsOneWidget);
  });

  testWidgets('"Family tree" on the person sheet opens the tree, in view', (tester) async {
    await openRostamSheet(tester);
    final button = find.text('تبارنامه');
    await tester.scrollUntilVisible(button, 300, scrollable: panelScroll());
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle(tester);
    expect(find.byType(PersonPanel), findsNothing);
    expect(find.byType(FamilyTreeView), findsOneWidget);
  });

  testWidgets("a place's tagged couplet on the map opens its poem, in view", (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=map&place=damavand', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    final sheet = find.byKey(const ValueKey('place-sheet'));
    final couplet = find.descendant(of: sheet, matching: find.byIcon(Icons.format_quote));
    for (var i = 0; i < 6 && couplet.evaluate().isEmpty; i++) {
      await tester.drag(find.descendant(of: sheet, matching: find.byType(Scrollable)).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(couplet.first);
    await tester.pumpAndSettle();
    await tester.tap(couplet.first);
    await settle(tester);
    expect(sheet, findsNothing);
    expect(find.byType(PoemScreen), findsOneWidget);
  });

  testWidgets('wide screens: a tagged couplet in the side panel opens its poem, in view', (tester) async {
    wide(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'تهمتن');
    await settle(tester);
    await tester.tap(find.byType(PersonRow).first);
    await settle(tester);
    final poem = find.descendant(of: find.byType(PersonPanel), matching: find.textContaining('زادن رستم'));
    await tester.scrollUntilVisible(poem, 300, scrollable: panelScroll());
    await tester.ensureVisible(poem);
    await tester.pumpAndSettle();
    await tester.tap(poem);
    await settle(tester);
    expect(find.byType(PersonPanel), findsNothing, reason: 'the panel closes');
    expect(find.byType(PoemScreen), findsOneWidget);
  });
}
