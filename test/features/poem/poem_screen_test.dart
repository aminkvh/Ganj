import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/settings/settings_controller.dart';

import '../../support/fixture_repository.dart';
import '../../support/scroll.dart';
import '../../support/test_app.dart';

const verse2 = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';

void main() {
  testWidgets('renders title, metre, rhyme and verses', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.text('غزل شمارهٔ ۱'), findsWidgets);
    expect(find.textContaining('مفاعیلن', findRichText: true), findsOneWidget);
    expect(find.textContaining('لها', findRichText: true), findsWidgets);
    expect(find.text(verse2), findsOneWidget);
    expect(find.text('حافظ'), findsOneWidget); // breadcrumb
  });

  testWidgets('find-in-poem matches across ZWNJ and counts hits', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('جستجو در شعر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('find-field')), 'مشکلها');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('find-count'))).data, '۱ از ۱');
  });

  testWidgets('zoom from overflow menu raises font scale', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بزرگ‌نمایی'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
    expect(container.read(settingsProvider).fontScale, 1.1);
  });

  testWidgets('meaning toggle shows couplet meanings', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('هان ای ساقی'), findsNothing);
    await tester.tap(find.byTooltip('معنی ابیات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('هان ای ساقی'), findsOneWidget);
  });

  testWidgets('unvisited poem offline shows retry; retry recovers', (tester) async {
    final prefs = await mockPrefs();
    final repo = FixtureRepository()..fail = true;
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: repo));
    await tester.pumpAndSettle();
    expect(find.text('تلاش دوباره'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(find.text(verse2), findsOneWidget);
  });

  testWidgets('paragraph poem renders all couplets without error', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 77000), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    await bringIntoView(tester, find.textContaining('سفینهٔ حافظ'));
    expect(find.textContaining('سفینهٔ حافظ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
