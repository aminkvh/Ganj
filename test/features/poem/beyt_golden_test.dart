@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/poem/couplets.dart';
import 'package:ganj/features/poem/widgets/beyt_view.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  for (final wide in [true, false]) {
    for (final b in Brightness.values) {
      final name = '${wide ? 'wide' : 'narrow'}_${b.name}';
      testWidgets('golden $name', (tester) async {
        await loadAppFonts();
        tester.view.physicalSize = Size(wide ? 1200 : 400, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefs = await mockPrefs();
        final couplets = groupCouplets(poem2130().verses).take(2).toList();
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: Column(
                children: [
                  for (final c in couplets) BeytView(couplet: c, wide: wide, scale: 1, showMeaning: c.index == 0),
                ],
              ),
            ),
            prefs: prefs,
            brightness: b,
          ),
        );
        await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/beyt_$name.png'));
      });
    }
  }
}
