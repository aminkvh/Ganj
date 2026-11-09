import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/theme/ganj_colors.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';
import '../../support/scroll.dart';
import '../../support/test_app.dart';

const verse2 = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';
const verse3 = 'به بویِ نافه‌ای کآخِر صبا زان طُرّه بُگشاید';

Finder highlighted(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == GanjColors.light.goldLight,
  ),
);

void main() {
  late FakeAudioBackend backend;
  late FixtureRepository repo;

  setUp(() {
    backend = FakeAudioBackend();
    repo = FixtureRepository();
  });

  Future<ProviderContainer> open(WidgetTester tester, int id) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        PoemScreen(id: id),
        prefs: prefs,
        repo: repo,
        backend: backend,
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
  }

  testWidgets('recitations panel lists reciters and plays', (tester) async {
    await open(tester, 2130);
    expect(find.textContaining('خوانش‌ها'), findsOneWidget);
    await tester.tap(find.textContaining('خوانش‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('فریدون فرح‌اندوز'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rec-play-2840')));
    await tester.pumpAndSettle();
    expect(backend.loaded.single.toString(), contains('2130-ff.mp3'));
    expect(backend.isPlaying, isTrue);
  });

  testWidgets('playback position highlights the current verse', (tester) async {
    final c = await open(tester, 2130);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    backend.emitPosition(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(highlighted(verse2), findsOneWidget);
    expect(highlighted(verse3), findsNothing);
  });

  testWidgets('another poem is not highlighted while 2130 plays', (tester) async {
    final c = await open(tester, 77000);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    backend.emitPosition(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == GanjColors.light.goldLight,
      ),
      findsNothing,
    );
  });

  testWidgets('poem without recitations shows no panel', (tester) async {
    final j = jsonDecode(fx('poem_2130')) as Map<String, dynamic>..['recitations'] = <dynamic>[];
    repo.poems[2130] = Poem.fromJson(j);
    await open(tester, 2130);
    expect(find.textContaining('خوانش‌ها'), findsNothing);
  });

  testWidgets('play from this beyt seeks to its start', (tester) async {
    await open(tester, 2130);
    await bringIntoView(tester, find.text(verse3));
    await tester.tap(find.text(verse3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('پخش از این بیت'));
    await tester.pumpAndSettle();
    expect(backend.seeks.last, const Duration(milliseconds: 15486));
  });

  group('play from a beyt during a voice stream', () {
    final first = PlaylistItem(uri: Uri.parse('file:///b0.wav'), duration: const Duration(seconds: 1));

    Future<void> playFromVerse3(WidgetTester tester) async {
      await bringIntoView(tester, find.text(verse3));
      await tester.tap(find.text(verse3));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.text('پخش از این بیت'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('a beyt not made yet shows no snackbar', (tester) async {
      final c = await open(tester, 2130);
      await c
          .read(playerProvider.notifier)
          .startVoiceStream(poem2130(), artist: 'v', first: first, firstVOrder: 1)
          .started;
      await playFromVerse3(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(backend.seeks, isEmpty);
    });

    testWidgets('while the first playlist loads, no snackbar', (tester) async {
      final c = await open(tester, 2130);
      backend.beforeLoad = Completer<void>().future; // the load never finishes
      c.read(playerProvider.notifier).startVoiceStream(poem2130(), artist: 'v', first: first, firstVOrder: 1);
      await tester.pump();
      expect(c.read(playerProvider).status, PlayerStatus.loading);
      await playFromVerse3(tester);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('after the end, a line the reading lacks still shows the snackbar', (tester) async {
      final c = await open(tester, 2130);
      final ctrl = c.read(playerProvider.notifier);
      final t = ctrl.startVoiceStream(poem2130(), artist: 'v', first: first, firstVOrder: 1);
      await t.started;
      ctrl.endVoiceStream(t);
      await playFromVerse3(tester);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a beyt read from its second hemistich plays from there', (tester) async {
      // Its first hemistich was skipped (not Persian): the reading keys the beyt on vOrder 4.
      final c = await open(tester, 2130);
      final ctrl = c.read(playerProvider.notifier);
      final t = ctrl.startVoiceStream(poem2130(), artist: 'v', first: first, firstVOrder: 4);
      await t.started;
      ctrl.endVoiceStream(t);
      await playFromVerse3(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(c.read(playerProvider).currentVOrder, 4);
    });
  });

  testWidgets('tapping the errored recitation retries it', (tester) async {
    final c = await open(tester, 2130);
    backend.failLoad = StateError('offline');
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    await tester.pumpAndSettle();
    backend.failLoad = null;
    await tester.tap(find.textContaining('خوانش‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-play-2840')));
    await tester.pumpAndSettle();
    expect(backend.loaded, hasLength(1));
    expect(backend.isPlaying, isTrue);
  });
}
