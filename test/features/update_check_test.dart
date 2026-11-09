import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/home/home_screen.dart';
import 'package:ganj/features/settings/settings_screen.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/update/update_check.dart';

import '../support/fixture_repository.dart';
import '../support/scroll.dart';
import '../support/test_app.dart';

String release(String tag, {bool prerelease = false, String repo = 'aminkvh/Ganj'}) =>
    '{"tag_name":"$tag","html_url":"https://github.com/$repo/releases/tag/$tag","draft":false,"prerelease":$prerelease}';

void main() {
  test('a build made without GANJ_UPDATE_CHECK (store .aab, by hand) never asks GitHub', () async {
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(await mockPrefs())]);
    addTearDown(c.dispose);
    expect(kUpdateCheckBuild, isFalse);
    expect(c.read(updateCheckerProvider), isNull);
    expect(await c.read(updateProvider.future), isNull);
  });

  test('version comparison', () {
    expect(isNewerVersion('1.6.0', '1.2.5'), isTrue);
    expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.2.5', '1.2.5'), isFalse);
    expect(isNewerVersion('1.2.4', '1.2.5'), isFalse);
    expect(isNewerVersion('1.6.0-beta', '1.2.5'), isFalse);
  });

  test('reads GitHub latest release; ignores pre-releases and other repositories', () {
    expect(parseLatestRelease(release('v1.6.0')), ('1.6.0', 'https://github.com/aminkvh/Ganj/releases/tag/v1.6.0'));
    expect(parseLatestRelease(release('v1.6.0', prerelease: true)), isNull);
    expect(parseLatestRelease(release('v1.6.0', repo: 'someone/else')), isNull);
    expect(parseLatestRelease('not json'), isNull);
  });

  group('UpdateChecker', () {
    late DateTime now;
    late int calls;
    late String body;

    UpdateChecker checker(prefs, {String current = '1.2.5', bool fail = false}) => UpdateChecker(
      prefs: prefs,
      current: current,
      now: () => now,
      fetch: () async {
        calls++;
        if (fail) throw StateError('offline');
        return body;
      },
    );

    setUp(() {
      now = DateTime(2026, 11, 9, 12);
      calls = 0;
      body = release('v1.6.0');
    });

    test('a newer release is reported, and GitHub is asked at most once a day', () async {
      final prefs = await mockPrefs();
      expect((await checker(prefs).check())?.version, '1.6.0');
      now = now.add(const Duration(hours: 23));
      expect((await checker(prefs).check())?.version, '1.6.0');
      expect(calls, 1);
      now = now.add(const Duration(hours: 2));
      body = release('v1.7.0');
      expect((await checker(prefs).check())?.version, '1.7.0');
      expect(calls, 2);
    });

    test('up to date: nothing to report', () async {
      final prefs = await mockPrefs();
      expect(await checker(prefs, current: '1.6.0').check(), isNull);
    });

    test('offline keeps the last answer', () async {
      final prefs = await mockPrefs();
      await checker(prefs).check();
      now = now.add(const Duration(days: 2));
      expect((await checker(prefs, fail: true).check())?.version, '1.6.0');
    });

    test('after updating, the remembered release is no longer newer', () async {
      final prefs = await mockPrefs();
      await checker(prefs).check();
      expect(await checker(prefs, current: '1.6.0').check(), isNull);
    });
  });

  const u = UpdateInfo('1.6.0', 'https://github.com/aminkvh/Ganj/releases/tag/v1.6.0');

  testWidgets('home shows the notice until it is closed for that version', (tester) async {
    final prefs = await mockPrefs();
    final app = testApp(
      const HomeScreen(),
      prefs: prefs,
      repo: FixtureRepository(),
      overrides: [updateProvider.overrideWith((ref) async => u)],
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-notice')), findsOneWidget);
    expect(find.textContaining('۱.۶.۰'), findsOneWidget);
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-notice')), findsNothing);
    expect(prefs.getString('update.dismissed'), '1.6.0');
  });

  testWidgets('no notice without a newer version', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-notice')), findsNothing);
  });

  testWidgets('Settings keeps the update row after the home notice is closed', (tester) async {
    final prefs = await mockPrefs({'update.dismissed': '1.6.0'});
    await tester.pumpWidget(
      testApp(const SettingsScreen(), prefs: prefs, overrides: [updateProvider.overrideWith((ref) async => u)]),
    );
    await tester.pumpAndSettle();
    await bringIntoView(tester, find.byKey(const ValueKey('update-row')));
    expect(find.byKey(const ValueKey('update-row')), findsOneWidget);
  });
}
