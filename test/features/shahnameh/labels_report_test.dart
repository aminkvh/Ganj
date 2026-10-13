import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/reader_chips.dart';
import 'package:ganj/features/shahnameh/ui/sh_style.dart';
import 'package:ganj/widgets/ai_badge.dart';
import 'package:ganj/widgets/external_link.dart';

import '../../support/test_app.dart';
import 'sh_support.dart';

/// In «جهان شاهنامه» what Ganjoor's AI wrote carries the app's AI badge, and what AI wrote for
/// Ganj (not from Ganjoor) carries «هوش مصنوعی · گنج»; every item can be reported by email.
void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  final launched = <Uri>[];
  List<Override> overrides() => [
    ...shOverrides(),
    urlLauncherProvider.overrideWithValue((u) async {
      launched.add(u);
      return true;
    }),
  ];

  Future<void> open(WidgetTester tester, String location, {String language = 'fa'}) async {
    phone(tester);
    launched.clear();
    final prefs = await mockPrefs({'language': language});
    await tester.pumpWidget(testAppRouted(location, prefs: prefs, overrides: overrides()));
    await settle(tester);
  }

  Finder inPanel(Finder f) => find.descendant(of: find.byType(PersonPanel), matching: f);

  testWidgets("a description Ganjoor's AI wrote is badged, and so is an English name AI wrote for Ganj", (
    tester,
  ) async {
    final p = realWorld.people.values.firstWhere((p) => p.aiDescription && p.en != null);
    await open(tester, '/shahnameh/person/${p.id}');
    expect(inPanel(find.byType(AiBadge)), findsWidgets);
    expect(inPanel(find.byType(GanjAiBadge)), findsOneWidget);
  });

  testWidgets('a description with no AI mark has no badge beside it', (tester) async {
    final p = realWorld.people.values.firstWhere(
      (p) => !p.aiDescription && p.description != null && p.en == null && !realWorld.hasAiTags(p.id),
    );
    await open(tester, '/shahnameh/person/${p.id}');
    expect(inPanel(find.byType(AiBadge)), findsNothing);
    expect(inPanel(find.byType(GanjAiBadge)), findsNothing);
  });

  testWidgets("story cards are Ganj's AI writing; Ganjoor's AI summaries are badged as such", (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    final card = find.byKey(const ValueKey('story-sohrab'));
    expect(find.descendant(of: card, matching: find.byType(GanjAiBadge)), findsOneWidget);
    final s = realWorld.storyById('sohrab')!;
    final firstSummarised = [
      for (final o in s.sections)
        for (final p in realWorld.sections[o].poems)
          if (realWorld.summaries.containsKey(p.id)) p.id,
    ].first;
    expect(
      find.descendant(of: card, matching: find.byType(AiBadge)),
      realWorld.aiSummaries.contains(firstSummarised) ? findsOneWidget : findsNothing,
    );
  });

  testWidgets("a curated place is Ganj's AI writing", (tester) async {
    await open(tester, '/shahnameh?tab=map&place=kabul');
    final sheet = find.byKey(const ValueKey('place-sheet'));
    expect(find.descendant(of: sheet, matching: find.byType(GanjAiBadge)), findsOneWidget);
  });

  testWidgets("a poem's people from AI-suggested tags are badged", (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    final poem = realWorld.aiTags.keys.firstWhere((p) => realWorld.poemPeople[p]?.isNotEmpty ?? false);
    await tester.pumpWidget(
      testApp(
        Scaffold(body: ShahnamehPeopleChips(poemId: poem)),
        prefs: prefs,
        overrides: overrides(),
      ),
    );
    await settle(tester);
    expect(find.byType(AiBadge), findsOneWidget);
  });

  testWidgets('«گزارش خطا» on a person writes an email to Ganj, about that person', (tester) async {
    await open(tester, '/shahnameh/person/60');
    final button = inPanel(find.text('گزارش خطا'));
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle(tester);
    final mail = launched.single;
    expect(mail.scheme, 'mailto');
    expect(mail.path, 'Ganj_app@protonmail.com');
    final subject = Uri.decodeComponent(RegExp(r'subject=([^&]*)').firstMatch(mail.query)!.group(1)!);
    final body = Uri.decodeComponent(RegExp(r'body=([^&]*)').firstMatch(mail.query)!.group(1)!);
    expect(subject, contains('رستم'));
    expect(body, contains('/shahnameh/person/60'));
    expect(mail.query, isNot(contains('+')), reason: 'spaces are %20, not +, so mail apps show them');
  });

  testWidgets('«گزارش خطا» on a story and on a place', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    final card = find.byKey(const ValueKey('story-sohrab'));
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('گزارش خطا')));
    await settle(tester);
    expect(Uri.decodeComponent(launched.single.query), contains('sohrab'));

    await open(tester, '/shahnameh?tab=map&place=kabul');
    final sheet = find.byKey(const ValueKey('place-sheet'));
    final button = find.descendant(of: sheet, matching: find.text('گزارش خطا'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle(tester);
    expect(Uri.decodeComponent(launched.single.query), contains('kabul'));
  });

  testWidgets('without an email app the report is copied, with the address', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh/person/60',
        prefs: prefs,
        overrides: [...shOverrides(), urlLauncherProvider.overrideWithValue((u) async => false)],
      ),
    );
    await settle(tester);
    final button = inPanel(find.text('گزارش خطا'));
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await settle(tester);
    expect(copied, contains('Ganj_app@protonmail.com'));
    expect(copied, contains('/shahnameh/person/60'));
    expect(
      find.textContaining('Ganj_app@protonmail.com'),
      findsOneWidget,
      reason: 'the snackbar says where to send it',
    );
  });
}
