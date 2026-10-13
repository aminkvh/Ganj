import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/data/tree_layout.dart';
import 'package:ganj/features/shahnameh/ui/network_view.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// Getting around the network and the family trees: zoom out to everything, collapse and
/// expand branches, hide and add people.
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

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  /// The visible «n نفر» count, in Persian digits.
  int count(WidgetTester tester) {
    final t = tester.widget<Text>(find.byKey(const ValueKey('network-count'))).data!;
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    return int.parse(t.split('').where(fa.contains).map((d) => fa.indexOf(d)).join());
  }

  group('family tree', () {
    testWidgets("a big tree opens compact, and a branch opens with its toggle", (tester) async {
      await open(tester, '/shahnameh/tree/1');
      final full = layoutTree(realWorld, 1).nodes.length;
      final boxes = find.byWidgetPredicate((w) => '${w.key}'.contains('tree-node-'));
      final before = boxes.evaluate().length;
      expect(before, lessThan(full), reason: 'not every one of $full people at once');
      // See the whole (compact) tree, then open a folded branch.
      await tester.tap(find.byTooltip('نمایش همه'));
      await settle(tester);
      // A folded branch: its toggle reads «+n».
      final toggle = find
          .descendant(
            of: find.byWidgetPredicate((w) => '${w.key}'.contains('tree-toggle-')),
            matching: find.textContaining('+'),
          )
          .first;
      await tester.ensureVisible(toggle);
      await tester.tap(toggle, warnIfMissed: false);
      await settle(tester);
      expect(boxes.evaluate().length, greaterThan(before));
    });

    testWidgets('"show all" fits the whole tree on screen', (tester) async {
      await open(tester, '/shahnameh/tree/1');
      await tester.tap(find.byTooltip('نمایش همه'));
      await settle(tester);
      final viewer = tester.getSize(find.byType(InteractiveViewer));
      final content = tester.getSize(find.byKey(const ValueKey('tree-canvas')));
      final s = scaleOf(tester);
      expect(content.width * s, lessThanOrEqualTo(viewer.width + 1));
      expect(content.height * s, lessThanOrEqualTo(viewer.height + 1));
    });

    testWidgets('zoom out and in buttons', (tester) async {
      await open(tester, '/shahnameh/tree/1');
      final s0 = scaleOf(tester);
      await tester.tap(find.byTooltip('کوچک‌نمایی'));
      await settle(tester);
      expect(scaleOf(tester), lessThan(s0));
      await tester.tap(find.byTooltip('بزرگ‌نمایی'));
      await settle(tester);
      expect(scaleOf(tester), closeTo(s0, 0.01));
    });
  });

  group('network', () {
    testWidgets('tapping the focused person offers: open, hide', (tester) async {
      await open(tester, '/shahnameh?tab=people&focus=60');
      await tester.tap(find.byKey(const ValueKey('network-canvas')));
      await settle(tester);
      expect(find.text('باز کردن'), findsOneWidget);
      expect(find.text('پنهان کردن'), findsOneWidget);
      expect(find.text('مرکز شبکه شود'), findsNothing, reason: 'Rostam is already the focus');
      await tester.tap(find.text('باز کردن'));
      await settle(tester);
      expect(find.byType(PersonPanel), findsOneWidget);
    });

    testWidgets('hiding a person, and bringing them back', (tester) async {
      await open(tester, '/shahnameh?tab=people&focus=60');
      final before = count(tester);
      // Zal is one of Rostam's close ties; hide him from the chip of the focused list.
      final net = tester.state<State<NetworkView>>(find.byType(NetworkView));
      expect(net, isNotNull);
      await tester.tap(find.byKey(const ValueKey('network-canvas')));
      await settle(tester);
      await tester.tap(find.text('پنهان کردن'));
      await settle(tester);
      // Hiding the focus itself leaves its neighbours without a centre: the view keeps them.
      expect(find.byKey(const ValueKey('hidden-60')), findsOneWidget);
      expect(count(tester), lessThan(before));
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('hidden-60')), matching: find.byIcon(Icons.close)),
      );
      await settle(tester);
      expect(count(tester), before);
    });

    testWidgets('adding someone to the network', (tester) async {
      await open(tester, '/shahnameh?tab=people&focus=60');
      final before = count(tester);
      await tester.tap(find.byTooltip('افزودن شخصیت'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'کاوه');
      await settle(tester);
      await tester.tap(find.text('کاوه').last);
      await settle(tester);
      expect(count(tester), before + 1);
    });

    testWidgets('zoom out, and "show all"', (tester) async {
      await open(tester, '/shahnameh?tab=people&focus=60');
      final s0 = scaleOf(tester);
      await tester.tap(find.byTooltip('کوچک‌نمایی'));
      await settle(tester);
      expect(scaleOf(tester), lessThan(s0));
      await tester.tap(find.byTooltip('نمایش همه'));
      await settle(tester);
      final viewer = tester.getSize(find.byType(InteractiveViewer));
      final content = tester.getSize(find.byKey(const ValueKey('network-paint')));
      final s = scaleOf(tester);
      expect(content.width * s, lessThanOrEqualTo(viewer.width + 1));
    });
  });
}
