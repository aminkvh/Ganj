import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/poet/poet_screen.dart';
import 'package:ganj/features/settings/settings_screen.dart';
import 'package:ganj/features/translate/translator.dart';
import 'package:ganj/widgets/external_link.dart';

import '../support/fixture_repository.dart';
import '../support/fixtures.dart';
import '../support/scroll.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

/// On-device translator double: "translates" by tagging the text.
class FakeDeviceTranslator implements Translator {
  FakeDeviceTranslator({this.ready = false});

  bool ready;
  bool failing = false;
  bool removed = false;
  final prepared = <String>[];
  final asked = <String>[];

  @override
  bool get inApp => true;

  @override
  bool get needsModel => true;

  @override
  Future<bool> isReady(String to) async => ready;

  @override
  Future<void> prepare(String to) async {
    prepared.add(to);
    ready = true;
  }

  @override
  Future<void> remove(String to) async {
    removed = true;
    ready = false;
  }

  @override
  Future<String> translate(String text, String to) async {
    asked.add(text);
    if (failing) throw Exception('blocked');
    return '[$to] ${text.split('\n').first}';
  }
}

void main() {
  // Read from the fixture: Persian diacritics can be stored in more than one order.
  final firstHemistich = poem2130().verses.first.text;

  Future<List<Uri>> pumpPoem(WidgetTester tester, Translator t) async {
    final opened = <Uri>[];
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [
          translatorProvider.overrideWithValue(t),
          urlLauncherProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
      ),
    );
    await settle(tester);
    return opened;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('on a phone, translation asks before downloading the model, then shows under each beyt', (tester) async {
    final t = FakeDeviceTranslator();
    await pumpPoem(tester, t);
    await tester.tap(find.byTooltip('ترجمه'));
    await tester.pumpAndSettle();
    expect(find.text('بارگیری مدل ترجمه'), findsOneWidget);
    await tester.tap(find.text('بارگیری'));
    await settle(tester);
    expect(t.prepared, ['en']);
    expect(find.textContaining('[en]'), findsWidgets);
    expect(find.text('ترجمهٔ ماشینی'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('declining the model download leaves the poem as it was', (tester) async {
    final t = FakeDeviceTranslator();
    await pumpPoem(tester, t);
    await tester.tap(find.byTooltip('ترجمه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انصراف'));
    await settle(tester);
    expect(t.prepared, isEmpty);
    expect(t.asked, isEmpty);
    expect(find.textContaining('[en]'), findsNothing);
    await unmount(tester);
  });

  testWidgets('with the model already on the phone, translation starts at once', (tester) async {
    final t = FakeDeviceTranslator(ready: true);
    await pumpPoem(tester, t);
    await tester.tap(find.byTooltip('ترجمه'));
    await settle(tester);
    expect(find.text('بارگیری مدل ترجمه'), findsNothing);
    expect(find.textContaining('[en]'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('on a computer, translate opens Google Translate with the poem', (tester) async {
    final opened = await pumpPoem(tester, const BrowserTranslator());
    await tester.tap(find.byTooltip('ترجمه'));
    await settle(tester);
    final u = opened.single;
    expect(u.host, 'translate.google.com');
    expect(u.queryParameters['sl'], 'fa');
    expect(u.queryParameters['tl'], 'en');
    expect(u.queryParameters['text'], contains(firstHemistich));
    await unmount(tester);
  });

  testWidgets('on a computer, a beyt\'s menu translates just that beyt', (tester) async {
    final opened = await pumpPoem(tester, const BrowserTranslator());
    const verse3 = 'به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید';
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ترجمهٔ بیت'));
    await settle(tester);
    final text = opened.single.queryParameters['text']!;
    expect(text, contains(verse3));
    expect(text, isNot(contains(firstHemistich)));
    await unmount(tester);
  });

  testWidgets('if in-app translation fails, the beyt can still be opened in Google Translate', (tester) async {
    final t = FakeDeviceTranslator(ready: true)..failing = true;
    final opened = await pumpPoem(tester, t);
    await tester.tap(find.byTooltip('ترجمه'));
    await settle(tester);
    final retry = find.text('باز کردن در Google Translate');
    expect(retry, findsWidgets);
    await tester.ensureVisible(retry.first);
    await tester.pumpAndSettle();
    await tester.tap(retry.first);
    await settle(tester);
    expect(opened.single.host, 'translate.google.com');
    expect(opened.single.queryParameters['text'], contains(firstHemistich));
    await unmount(tester);
  });

  testWidgets("in the English interface a poet's biography can be translated", (tester) async {
    final t = FakeDeviceTranslator(ready: true);
    final prefs = await mockPrefs({'language': 'en'});
    await tester.pumpWidget(
      testApp(
        const PoetScreen(id: 2),
        prefs: prefs,
        repo: FixtureRepository(),
        language: 'en',
        overrides: [translatorProvider.overrideWithValue(t)],
      ),
    );
    await settle(tester);
    expect(find.textContaining('[en]'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Translate'));
    await settle(tester);
    expect(find.textContaining('[en]'), findsOneWidget);
    expect(find.text('Machine translation'), findsOneWidget);
  });

  testWidgets('in the Persian interface there is no translate button on biographies', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoetScreen(id: 2),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [translatorProvider.overrideWithValue(FakeDeviceTranslator(ready: true))],
      ),
    );
    await settle(tester);
    expect(find.widgetWithText(TextButton, 'ترجمه'), findsNothing);
  });

  test('a very long poem is cut to fit a Google Translate link', () {
    final long = List.filled(2000, firstHemistich).join('\n');
    final u = googleTranslateUri(long, 'en');
    expect(u.queryParameters['text']!.length, lessThanOrEqualTo(kMaxTranslateChars));
    expect(u.queryParameters['text'], startsWith(firstHemistich));
  });

  testWidgets('settings: pick the translation language and remove the phone model', (tester) async {
    final t = FakeDeviceTranslator(ready: true);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(const SettingsScreen(), prefs: prefs, overrides: [translatorProvider.overrideWithValue(t)]),
    );
    await settle(tester);
    final picker = find.byKey(const ValueKey('translate-to'));
    await tester.scrollUntilVisible(picker, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await settle(tester);
    expect(prefs.getString('translateTo'), 'fr');
    final remove = find.byKey(const ValueKey('translate-remove'));
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await settle(tester);
    expect(t.removed, isTrue);
  });
}
