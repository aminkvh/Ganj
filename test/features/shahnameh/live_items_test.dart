import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/reader_chips.dart';
import 'package:ganj/widgets/ai_badge.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

/// What is opened is refreshed from Ganjoor: a person's appearances, a poem's people and places.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  FakeAdapter live(Map<String, String> extra) => FakeAdapter({
    '/api/people/60/relations': shFx('relations_60.json'),
    '/api/people/60/poems': shFx('poems_60.json'),
    '/api/locations': '[{"id":34,"name":"کابل","latitude":34.55,"longitude":69.2}]',
    ...extra,
  });

  testWidgets("a person's appearances come from Ganjoor when it answers", (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    final presence = jsonEncode({
      'rootId': 60,
      'columns': [
        {'catId': 35, 'title': 'کیومرث'},
        {'catId': 36, 'title': 'هوشنگ'},
      ],
      'people': [
        {
          'id': 60,
          'columns': [0, 1],
        },
      ],
    });
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh/person/60',
        prefs: prefs,
        overrides: shOverrides(adapter: live({'/api/people/60/presence': presence})),
      ),
    );
    await settle(tester);
    expect(find.descendant(of: find.byType(PersonPanel), matching: find.text('۲ بخش')), findsOneWidget);
  });

  testWidgets('offline, the bundled appearances stay', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh/person/60',
        prefs: prefs,
        overrides: shOverrides(adapter: FakeAdapter({})..offline = true),
      ),
    );
    await settle(tester);
    final n = realWorld.presence[60]!.length;
    expect(find.descendant(of: find.byType(PersonPanel), matching: find.text('${localDigits(n)} بخش')), findsOneWidget);
  });

  testWidgets("a poem's people and places come from Ganjoor when it answers", (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    final tags = jsonEncode([
      {
        'poemId': 1403,
        'coupletIndex': 2,
        'personId': 62,
        'personMention': 0,
        'note': 'پیشنهاد هوش مصنوعی (x): شاه توران',
        'locationId': null,
      },
      {'poemId': 1403, 'coupletIndex': 5, 'personId': null, 'personMention': 0, 'note': null, 'locationId': 34},
    ]);
    await tester.pumpWidget(
      testApp(
        const Scaffold(body: ShahnamehPeopleChips(poemId: 1403)),
        prefs: prefs,
        overrides: shOverrides(adapter: live({'/api/ganjoor/poem/1403/geotag': tags})),
      ),
    );
    await settle(tester);
    expect(find.widgetWithText(ActionChip, 'افراسیاب'), findsOneWidget);
    expect(
      find.widgetWithText(ActionChip, 'زال'),
      findsNothing,
      reason: "Ganjoor's current tags replace the bundled ones",
    );
    expect(find.widgetWithText(ActionChip, 'کابل'), findsOneWidget);
    expect(find.byType(AiBadge), findsOneWidget);
  });
}
