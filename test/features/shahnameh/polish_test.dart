import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/relation_kinds.dart';
import 'package:ganj/features/shahnameh/ui/hub_screen.dart';
import 'package:ganj/features/shahnameh/ui/network_view.dart';
import 'package:ganj/features/shahnameh/ui/people_tab.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';
import 'world_loader_test.dart' show fixtureWorld;

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  test('M7: a satirist is a conflict, not an alliance', () {
    expect(relationKind('A', 10).family, RelationFamily.conflict);
  });

  testWidgets('M2: two kin ties to the same person both show, without clashing', (tester) async {
    phone(tester);
    final f = fixtureWorld();
    // Zal is Rostam's parent; a second, redundant "ancestor" edge from the data.
    final w = ShWorld(
      builtAt: f.builtAt,
      people: f.people,
      edges: [...f.edges, ShEdge(31, 30, relationKind('R', 3), degree: 1)],
      sections: f.sections,
      presence: f.presence,
      passing: f.passing,
      poemPeople: f.poemPeople,
      summaries: f.summaries,
      ages: f.ages,
      places: f.places,
      routes: f.routes,
      ganjoorTags: f.ganjoorTags,
      treeRoots: f.treeRoots,
    );
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh/person/30',
        prefs: prefs,
        overrides: shOverrides(world: w),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.descendant(of: find.byType(PersonPanel), matching: find.text('زال')), findsNWidgets(2));
  });

  testWidgets('M3: the people list follows a change of language', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    Widget app(String language) => testApp(
      Scaffold(body: PeopleTab(world: realWorld)),
      prefs: prefs,
      overrides: shOverrides(),
      language: language,
    );
    await tester.pumpWidget(app('fa'));
    await settle(tester);
    expect(find.text('نامداران'), findsOneWidget);
    await tester.pumpWidget(app('en'));
    await settle(tester);
    expect(find.text('Major figures'), findsOneWidget);
  });

  testWidgets('M5: from a person opened in the hub, "show in the network" stays in the same hub', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'تهمتن');
    await settle(tester);
    await tester.tap(find.byType(PersonRow).first);
    await settle(tester);
    final button = find.text('نمایش در شبکه');
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle(tester);
    expect(find.byType(ShahnamehHubScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(PersonPanel), findsNothing, reason: 'the sheet closes');
    expect(find.byType(NetworkView), findsOneWidget);
  });

  testWidgets('M5: a place on the person sheet opens on the map of the same hub', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/shahnameh?tab=people', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'تهمتن');
    await settle(tester);
    await tester.tap(find.byType(PersonRow).first);
    await settle(tester);
    final chip = find.widgetWithText(ActionChip, 'زابلستان');
    await tester.scrollUntilVisible(
      chip,
      300,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await settle(tester);
    expect(find.byType(ShahnamehHubScreen, skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('place-sheet')), findsOneWidget);
  });
}
