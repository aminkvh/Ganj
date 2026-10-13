import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/tree_view.dart';
import 'package:ganj/features/shahnameh/ui/trees_tab.dart';

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

  testWidgets("Ganjoor's three family trees are listed", (tester) async {
    await open(tester, '/shahnameh?tab=trees');
    expect(find.byType(TreesTab), findsOneWidget);
    for (final t in ['پیشدادیان - تبار کیومرث', 'پیشدادیان - شاخهٔ ضحاک', 'خاندان رستم']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('a tree opens with its people, and a person opens from it', (tester) async {
    await open(tester, '/shahnameh?tab=trees');
    await tester.tap(find.text('خاندان رستم'));
    await settle(tester);
    expect(find.byType(FamilyTreeView), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-node-54')), findsOneWidget, reason: 'Zal is in the tree');
    // The view opens centred on the tree's head, گرشاسپ.
    await tester.tap(find.byKey(const ValueKey('tree-node-64')));
    await settle(tester);
    expect(find.byType(PersonPanel), findsOneWidget);
  });

  testWidgets("anyone's tree, found by search", (tester) async {
    await open(tester, '/shahnameh?tab=trees');
    await tester.enterText(find.byType(TextField), 'سهراب');
    await settle(tester);
    await tester.tap(find.text('سهراب').last);
    await settle(tester);
    expect(find.byType(FamilyTreeView), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-node-128')), findsOneWidget);
  });

  testWidgets('the person sheet leads to the family tree', (tester) async {
    await open(tester, '/shahnameh/person/60');
    final button = find.text('تبارنامه');
    await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(button);
    await settle(tester);
    expect(find.byType(FamilyTreeView), findsOneWidget);
  });

  testWidgets('a tree has a deep link', (tester) async {
    await open(tester, '/shahnameh/tree/1');
    expect(find.byType(FamilyTreeView), findsOneWidget);
    expect(find.byKey(const ValueKey('tree-node-1')), findsOneWidget);
  });

  testWidgets('Ganjoor is credited for the people data', (tester) async {
    await open(tester, '/shahnameh?tab=trees');
    await tester.scrollUntilVisible(find.textContaining('از گنجور'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('هوش مصنوعی برای گنج'), findsOneWidget, reason: 'and says what AI wrote for Ganj');
  });
}
