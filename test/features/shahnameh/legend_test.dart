import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// «راهنما»: what the lines, colours and marks mean.
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

  testWidgets('the family tree explains its lines and marks', (tester) async {
    await open(tester, '/shahnameh/tree/64');
    expect(find.text('همسران'), findsNothing);
    await tester.tap(find.byTooltip('راهنما'));
    await settle(tester);
    for (final t in [
      'پدر یا مادر و فرزند',
      'همسران',
      'نیا و نواده، با چند نسل فاصله',
      'کسی که تبارنامه‌اش را می‌بینید',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // And closes again.
    await tester.tap(find.byTooltip('راهنما'));
    await settle(tester);
    expect(find.text('همسران'), findsNothing);
  });

  testWidgets('the network explains its lines and circles', (tester) async {
    await open(tester, '/shahnameh?tab=people&focus=60');
    await tester.tap(find.byTooltip('راهنما'));
    await settle(tester);
    expect(find.text('کسی که شبکه بر گرد او است'), findsOneWidget);
    expect(find.textContaining('خط‌چین'), findsOneWidget);
  });
}
