import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/player/unavailable_audio.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  test('Windows N (no Media Foundation) is recognised from its missing system files', () {
    bool exists(String p) => p.toLowerCase().endsWith(r'system32\mfplat.dll');
    expect(mediaFoundationAvailable(systemRoot: r'C:\Windows', exists: exists), isTrue);
    expect(mediaFoundationAvailable(systemRoot: r'C:\Windows', exists: (_) => false), isFalse);
  });

  test('Linux without libmpv is recognised; any of its usual names counts', () {
    expect(libmpvAvailable(exists: (p) => p == '/usr/lib/x86_64-linux-gnu/libmpv.so.2'), isTrue);
    expect(libmpvAvailable(exists: (p) => p == '/usr/lib64/libmpv.so.1'), isTrue);
    expect(libmpvAvailable(exists: (_) => false), isFalse);
  });

  testWidgets('pressing play on Linux without libmpv says how to install it', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/poem/2130',
        prefs: prefs,
        backend: const UnavailableAudioBackend(),
        overrides: [audioUnavailableProvider.overrideWithValue(AudioUnavailableReason.linuxNoMpv)],
      ),
    );
    await settle(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
    final poem = poem2130();
    await tester.runAsync(() => c.read(playerProvider.notifier).play(poem, poem.recitations.first));
    await settle(tester);
    expect(find.textContaining('libmpv'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  test('the stand-in player refuses to play, with a reason the app can explain', () async {
    const b = UnavailableAudioBackend();
    await expectLater(
      b.load(
        Uri.parse('https://i.ganjoor.net/a/2130.mp3'),
        info: const MediaInfo(id: '1', title: 't', artist: 'a'),
      ),
      throwsA(isA<AudioUnavailable>()),
    );
  });

  testWidgets('pressing play on Windows N explains how to enable audio instead of failing', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testAppRouted(
        '/poem/2130',
        prefs: prefs,
        backend: const UnavailableAudioBackend(),
        overrides: [audioUnavailableProvider.overrideWithValue(AudioUnavailableReason.windowsN)],
      ),
    );
    await settle(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
    final poem = poem2130();
    await tester.runAsync(() => c.read(playerProvider.notifier).play(poem, poem.recitations.first));
    await settle(tester);
    expect(find.textContaining('Media Feature Pack'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
