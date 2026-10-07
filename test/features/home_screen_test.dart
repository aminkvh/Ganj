import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poet.dart';
import 'package:ganj/features/home/home_screen.dart';
import 'package:ganj/features/home/poet_tile.dart';

import '../support/fixture_repository.dart';
import '../support/test_app.dart';

import 'package:ganj/l10n/l10n.dart';

void main() {
  testWidgets('shows century tabs and pinned poets', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.text('قرن سوم'), findsOneWidget);
    expect(find.byKey(const ValueKey('poet-2')), findsWidgets);
  });

  testWidgets('filter narrows poets, tolerating Arabic ي', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('poet-filter')), 'سعدي');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('poet-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('poet-2')), findsNothing);
  });

  testWidgets('offline with repo failure shows retry', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()..fail = true));
    await tester.pumpAndSettle();
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('header offers search and the offline library', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('جستجو در اشعار'), findsOneWidget);
    expect(find.byTooltip('کتابخانهٔ آفلاین'), findsOneWidget);
  });

  testWidgets('menu offers faal, random poem, metres and bookmarks', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('منو'));
    await tester.pumpAndSettle();
    for (final t in ['فال حافظ', 'شعر تصادفی', 'وزن‌ها', 'نشان‌ها و یادداشت‌ها']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  test('poetYears', () {
    final fa = lookupL10n(const Locale('fa'));
    Poet p({int? b, int? d}) =>
        Poet(id: 1, name: '', nickname: '', fullUrl: '', rootCatId: 1, birthYear: b, deathYear: d);
    expect(poetYears(fa, p(b: 726, d: 792)), '۷۲۶ – ۷۹۲');
    expect(poetYears(fa, p(d: 792)), 'د. ۷۹۲');
    expect(poetYears(fa, p()), '');
  });
}
