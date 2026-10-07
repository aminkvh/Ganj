import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/poem/couplets.dart';
import 'package:ganj/features/poem/widgets/beyt_view.dart';

import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  final first = groupCouplets(poem2130().verses).first;
  final m1 = first.verses[0].text, m2 = first.verses[1].text;

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(1200, 600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        Scaffold(body: SingleChildScrollView(child: child)),
        prefs: prefs,
      ),
    );
  }

  testWidgets('wide: hemistichs side by side, first on the right', (tester) async {
    await pump(tester, BeytView(couplet: first, wide: true, scale: 1));
    final a = tester.getCenter(find.text(m1)), b = tester.getCenter(find.text(m2));
    expect(a.dy, closeTo(b.dy, 1));
    expect(a.dx, greaterThan(b.dx));
  });

  testWidgets('wide: a long hemistich stays on one line (scaled down, not wrapped)', (tester) async {
    await pump(tester, BeytView(couplet: first, wide: true, scale: 1), size: const Size(1000, 600));
    final lineHeight = 19 * 2.2;
    expect(tester.getSize(find.text(m2)).height, lessThanOrEqualTo(lineHeight + 1));
  });

  testWidgets('narrow: hemistichs stacked', (tester) async {
    await pump(tester, BeytView(couplet: first, wide: false, scale: 1), size: const Size(400, 800));
    expect(tester.getCenter(find.text(m1)).dy, lessThan(tester.getCenter(find.text(m2)).dy));
  });

  testWidgets('meaning and language badge', (tester) async {
    await pump(tester, BeytView(couplet: first, wide: true, scale: 1, showMeaning: true));
    expect(find.text('عربی'), findsOneWidget);
    expect(find.textContaining('هان ای ساقی'), findsOneWidget);
  });

  testWidgets('on a phone a tap opens the beyt actions; a long press is left for selecting text', (tester) async {
    final opened = <Offset?>[];
    // Inside the poem's SelectionArea, as on the poem page.
    await pump(
      tester,
      SelectionArea(
        child: BeytView(couplet: first, wide: true, scale: 1, onMenu: opened.add),
      ),
    );
    await tester.longPress(find.text(m1));
    expect(opened, isEmpty);
    await tester.tap(find.text(m1));
    expect(opened, [null]);
  });

  testWidgets('on a computer a right-click opens the actions at the pointer; the hover ⋮ too', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final opened = <Offset?>[];
      await pump(tester, BeytView(couplet: first, wide: true, scale: 1, onMenu: opened.add));
      await tester.tap(find.text(m1));
      expect(opened, isEmpty); // a left click is for selecting
      final at = tester.getCenter(find.text(m1));
      await tester.tapAt(at, buttons: kSecondaryButton);
      expect(opened.single, at);
      final more = find.byKey(ValueKey('beyt-more-${first.index}'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.ancestor(of: more, matching: find.byType(AnimatedOpacity))).opacity,
        1,
      );
      await tester.tap(more);
      expect(opened, hasLength(2));
      expect(opened.last, isNotNull);
      await mouse.removePointer();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('max zoom on a 360px phone does not overflow', (tester) async {
    await loadAppFonts();
    final all = groupCouplets(poem2130().verses);
    await pump(
      tester,
      Column(children: [for (final c in all) BeytView(couplet: c, wide: false, scale: 1.8, showMeaning: true)]),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
  });
}
