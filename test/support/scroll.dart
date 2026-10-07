import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scrolls the poem page until [finder] is built and visible (poem couplets are built lazily).
Future<void> bringIntoView(WidgetTester tester, Finder finder, {double step = 300}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, step, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
