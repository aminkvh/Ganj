import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/player/mini_player.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

void main() {
  late FakeAudioBackend backend;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    backend = FakeAudioBackend();
    final prefs = await mockPrefs();
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
    return ProviderScope.containerOf(tester.element(find.byType(MiniPlayer)));
  }

  testWidgets('hidden while idle', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('mini-player')), findsNothing);
  });

  testWidgets('shows poem and reciter while playing; pause toggles', (tester) async {
    final c = await pump(tester);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    expect(find.text('غزل شمارهٔ ۱'), findsOneWidget);
    expect(find.text('فریدون فرح‌اندوز'), findsOneWidget);
    await tester.tap(find.byTooltip('توقف'));
    await tester.pumpAndSettle();
    expect(backend.isPlaying, isFalse);
  });

  testWidgets('speed menu changes playback speed', (tester) async {
    final c = await pump(tester);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('سرعت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('×۱٫۲۵'));
    await tester.pumpAndSettle();
    expect(backend.speed, 1.25);
  });

  testWidgets('load error shows retry that plays again', (tester) async {
    final c = await pump(tester);
    backend.failLoad = StateError('offline');
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    await tester.pumpAndSettle();
    expect(find.text('پخش ممکن نشد'), findsOneWidget);
    backend.failLoad = null;
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(backend.loaded, hasLength(1));
    expect(backend.isPlaying, isTrue);
  });

  testWidgets('close stops and hides', (tester) async {
    final c = await pump(tester);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-player')), findsNothing);
  });
}
