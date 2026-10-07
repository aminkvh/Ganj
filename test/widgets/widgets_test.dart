import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/cat.dart';
import 'package:ganj/widgets/breadcrumb.dart';
import 'package:ganj/widgets/error_retry.dart';
import 'package:ganj/widgets/gold_card.dart';
import 'package:ganj/widgets/poet_portrait.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('GoldCard never exceeds 752 wide', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: GoldCard(
            child: SizedBox(key: ValueKey('inner'), height: 10, width: double.infinity),
          ),
        ),
        prefs: prefs,
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('inner'))).width, lessThanOrEqualTo(752));
  });

  testWidgets('portrait without url shows placeholder', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const Scaffold(body: PoetPortrait(url: null)), prefs: prefs));
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('portrait whose image fails to load shows placeholder', (tester) async {
    final prefs = await mockPrefs();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        testApp(
          const Scaffold(body: PoetPortrait(url: 'https://api.ganjoor.net/api/ganjoor/poet/image/none.gif')),
          prefs: prefs,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('ErrorRetry calls back', (tester) async {
    final prefs = await mockPrefs();
    var retried = 0;
    await tester.pumpWidget(
      testApp(
        Scaffold(body: ErrorRetry(onRetry: () => retried++)),
        prefs: prefs,
      ),
    );
    await tester.tap(find.text('تلاش دوباره'));
    expect(retried, 1);
  });

  test('crumbsFor maps the root category to the poet page', () {
    final pc = PoetCat.fromJson(jsonDecode(fx('cat_24')) as Map<String, dynamic>);
    final withSelf = crumbsFor(pc, includeSelf: true);
    expect([for (final c in withSelf) (c.title, c.route)], [('حافظ', '/poet/2'), ('غزلیات', '/cat/24')]);
    expect(crumbsFor(pc, includeSelf: false), hasLength(1));
  });
}
