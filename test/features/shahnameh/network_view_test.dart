import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/network_view.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> open(WidgetTester tester, String location) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted(location, prefs: prefs, overrides: shOverrides()));
    await settle(tester);
  }

  /// Big networks are laid out in an isolate: wait for real time to pass until it lands.
  Future<void> waitForLayout(WidgetTester tester) async {
    final spinner = find.descendant(of: find.byType(NetworkView), matching: find.byType(CircularProgressIndicator));
    for (var i = 0; i < 100 && spinner.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(spinner, findsNothing);
  }

  /// The visible «n نفر» count, in Persian digits.
  int count(WidgetTester tester) {
    final t = tester.widget<Text>(find.byKey(const ValueKey('network-count'))).data!;
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    return int.parse(t.split('').where(fa.contains).map((d) => fa.indexOf(d)).join());
  }

  testWidgets('the people tab switches between the list and the network', (tester) async {
    await open(tester, '/shahnameh?tab=people');
    await tester.tap(find.text('شبکه'));
    await settle(tester);
    expect(find.byType(NetworkView), findsOneWidget);
    await tester.tap(find.text('فهرست'));
    await settle(tester);
    expect(find.byType(NetworkView), findsNothing);
  });

  testWidgets('focused on a person: close ties, two steps, the whole network', (tester) async {
    await open(tester, '/shahnameh?tab=people&focus=60');
    expect(find.byType(NetworkView), findsOneWidget);
    final one = count(tester);
    await tester.tap(find.text('دو گام'));
    await settle(tester);
    final two = count(tester);
    await tester.tap(find.text('همهٔ شبکه'));
    await tester.pump();
    await waitForLayout(tester);
    final all = count(tester);
    expect(one, lessThan(two));
    expect(two, lessThan(all));
  });

  testWidgets('a family of ties can be hidden', (tester) async {
    await open(tester, '/shahnameh?tab=people&focus=60');
    final before = count(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'دشمنی'));
    await settle(tester);
    expect(count(tester), lessThan(before));
  });

  testWidgets('tapping the person in the middle opens them', (tester) async {
    await open(tester, '/shahnameh?tab=people&focus=60');
    final canvas = find.byKey(const ValueKey('network-canvas'));
    await tester.tap(canvas);
    await settle(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
  });

  testWidgets('the person sheet shows the person in the network', (tester) async {
    await open(tester, '/shahnameh/person/60');
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
    expect(find.byType(NetworkView), findsOneWidget);
  });
}
