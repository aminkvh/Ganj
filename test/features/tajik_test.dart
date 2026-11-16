import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/settings/settings_screen.dart';
import 'package:ganj/features/tajik/tajik_text.dart';

import '../data/extras_test.dart' show ex;
import '../support/fake_adapter.dart';
import '../support/fixture_repository.dart';
import '../support/scroll.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const file = '/gh/ganjoor/ganjoor-tajik-data@main/poets/hafez/ghazal/sh1.json';
  const tajik3 = 'Ба буии нофае кохри сабо зон турра бигушоед';

  TajikSource source(FakeAdapter a) => TajikSource(
    dio: createDio(adapter: a),
    cache: HttpCache(AppDb(NativeDatabase.memory())),
  );

  test('a poem\'s Tajik (Cyrillic) text comes from Ganjoor\'s Tajik data, by verse', () async {
    final adapter = FakeAdapter({file: ex('tajik_sh1.json')});
    final t = await source(adapter).poem('/hafez/ghazal/sh1');
    expect(adapter.requests.single.host, 'cdn.jsdelivr.net');
    expect(t[3], tajik3);
    expect(t, hasLength(14));
  });

  test('a poem without Tajik text is just empty, not an error', () async {
    expect(await source(FakeAdapter({})).poem('/nobody/x/sh1'), isEmpty);
  });

  Future<void> pumpPoem(WidgetTester tester, {bool tajik = false, String? mode, FakeAdapter? adapter}) async {
    // `showTajik` is how the option was saved before 1.6.3: on now means under the verses.
    final prefs = await mockPrefs({'showTajik': tajik, 'tajikScript': ?mode});
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [
          tajikSourceProvider.overrideWithValue(source(adapter ?? FakeAdapter({file: ex('tajik_sh1.json')}))),
        ],
      ),
    );
    await settle(tester);
  }

  testWidgets('with Tajik script on, each beyt shows its Cyrillic text', (tester) async {
    await pumpPoem(tester, tajik: true);
    await bringIntoView(tester, find.textContaining(tajik3));
    expect(find.textContaining(tajik3), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('off by default, and nothing is fetched', (tester) async {
    final adapter = FakeAdapter({file: ex('tajik_sh1.json')});
    await pumpPoem(tester, adapter: adapter);
    expect(find.textContaining(tajik3), findsNothing);
    expect(adapter.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('the poem menu turns Tajik script on', (tester) async {
    await pumpPoem(tester);
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خط تاجیکی (سیریلیک)'));
    await settle(tester);
    await bringIntoView(tester, find.textContaining(tajik3));
    expect(find.textContaining(tajik3), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('Tajik only: the beyt in Cyrillic in place of the Persian', (tester) async {
    await pumpPoem(tester, mode: 'only');
    await bringIntoView(tester, find.textContaining(tajik3));
    expect(find.textContaining(tajik3), findsOneWidget);
    expect(find.text('به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('a poem with no Tajik text says so, instead of showing nothing silently', (tester) async {
    await pumpPoem(tester, mode: 'below', adapter: FakeAdapter({}));
    expect(find.byKey(const ValueKey('no-tajik')), findsOneWidget);
    await bringIntoView(tester, find.text('به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید'));
    expect(find.text('به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('Settings: off, under the verses, or Tajik only', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const SettingsScreen(), prefs: prefs));
    await settle(tester);
    final only = find.text('فقط تاجیکی');
    await tester.scrollUntilVisible(only, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(only);
    await tester.pumpAndSettle();
    await tester.tap(only);
    await settle(tester);
    expect(prefs.getString('tajikScript'), 'only');
  });
}
