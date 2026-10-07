import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ganj/features/player/mini_player.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../support/fake_audio_backend.dart';
import '../support/fixture_repository.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('each beyt reads as one unit: both hemistichs, in order', (tester) async {
    final handle = tester.ensureSemantics();
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    final beyt = find.byWidgetPredicate((w) {
      final label = w is Semantics ? w.properties.label ?? '' : '';
      final lines = label.split('\n');
      final first = lines.indexWhere((l) => l.startsWith('اَلا یا'));
      final second = lines.indexWhere((l) => l.startsWith('که عشق آسان نمود'));
      return first >= 0 && second == first + 1; // hemistichs adjacent and in order
    });
    expect(beyt, findsOneWidget);
    expect(tester.widget<Semantics>(beyt).properties.hintOverrides?.onTapHint, 'گزینه‌های بیت');
    handle.dispose();
  });

  for (final (name, screen) in [('home', const HomeScreen() as Widget), ('poem', const PoemScreen(id: 2130))]) {
    testWidgets('$name: no overflow on a phone at max verse size and large system text', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await loadAppFonts(); // real Vazirmatn line heights, not the test font
      final prefs = await mockPrefs({'fontScale': 1.8, 'showMeaning': true});
      await tester.pumpWidget(testApp(screen, prefs: prefs, repo: FixtureRepository()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final failing in [false, true]) {
    testWidgets('mini-player (${failing ? 'error' : 'playing'}): no overflow on a phone with large system text', (
      tester,
    ) async {
      await loadAppFonts();
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = FakeAudioBackend()..failLoad = failing ? StateError('offline') : null;
      final prefs = await mockPrefs({'fontScale': 1.8});
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: Column(
              children: [
                Expanded(child: SizedBox()),
                MiniPlayer(),
              ],
            ),
          ),
          prefs: prefs,
          repo: FixtureRepository(),
          backend: backend,
        ),
      );
      final c = ProviderScope.containerOf(tester.element(find.byType(MiniPlayer)));
      final poem = poem2130();
      await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
