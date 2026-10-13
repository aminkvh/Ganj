import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// Every part of the hub on a 360 dp phone, in both languages: no overflow anywhere.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  for (final language in ['fa', 'en']) {
    testWidgets('every tab fits a small phone ($language)', (tester) async {
      narrow(tester);
      final prefs = await mockPrefs({'language': language});
      await tester.pumpWidget(testAppRouted('/shahnameh', prefs: prefs, overrides: shOverrides()));
      await settle(tester);
      final tabs = DefaultTabController.of(tester.element(find.byType(TabBarView)));
      for (var i = 0; i < 4; i++) {
        tabs.animateTo(i);
        await settle(tester);
      }
      // The river too.
      tabs.animateTo(0);
      await settle(tester);
      await tester.tap(find.byIcon(Icons.waterfall_chart));
      await settle(tester);
      // And a person.
      await tester.pumpWidget(testAppRouted('/shahnameh/person/60', prefs: prefs, overrides: shOverrides()));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
