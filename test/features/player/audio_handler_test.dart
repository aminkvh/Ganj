import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/audio_handler.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';

/// Records what reaches the backend without touching a real player.
class _SpyBackend extends JustAudioBackend {
  final seeks = <Duration>[];
  int plays = 0, pauses = 0;

  @override
  Future<void> seek(Duration d) async => seeks.add(d);

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> pause() async => pauses++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SpyBackend backend;
  late GanjAudioHandler handler;

  setUp(() {
    backend = _SpyBackend();
    handler = GanjAudioHandler(backend);
  });

  test('seek does nothing for live media', () async {
    backend.current = const MediaInfo(id: 'voice-7', title: 't', artist: 'a', live: true);
    await handler.seek(const Duration(seconds: 3));
    expect(backend.seeks, isEmpty);
  });

  test('seek reaches the backend for ordinary media', () async {
    backend.current = const MediaInfo(id: '1', title: 't', artist: 'a');
    await handler.seek(const Duration(seconds: 3));
    expect(backend.seeks, [const Duration(seconds: 3)]);
  });

  test('play and pause go through the controller hooks when set', () async {
    var played = 0, paused = 0;
    handler.onPlay = () async {
      played++;
    };
    handler.onPause = () async {
      paused++;
    };
    await handler.play();
    await handler.pause();
    expect((played, paused), (1, 1));
    expect((backend.plays, backend.pauses), (0, 0));
  });

  test('play and pause fall back to the backend without hooks', () async {
    await handler.play();
    await handler.pause();
    expect((backend.plays, backend.pauses), (1, 1));
  });

  group('wired to the player controller', () {
    late FakeAudioBackend fake;
    late ProviderContainer c;

    setUp(() {
      fake = FakeAudioBackend();
      c = ProviderContainer(
        overrides: [
          audioBackendProvider.overrideWithValue(fake),
          poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
        ],
      );
      addTearDown(c.dispose);
      wireAudioHandler(handler, c);
    });

    PlayerController ctrl() => c.read(playerProvider.notifier);

    Future<VoiceStreamToken> stream() async {
      final t = ctrl().startVoiceStream(poem2130(), artist: 'v', first: _item(0, 1000), firstVOrder: 1);
      await t.started;
      return t;
    }

    test('while waiting the OS shows playing with a Pause control; a click pauses for good', () async {
      final t = await stream();
      fake.emitItemPosition(0, const Duration(milliseconds: 900));
      await _tick();
      expect(c.read(playerProvider).waiting, isTrue);
      await _tick();
      final shown = handler.playbackState.value;
      expect(shown.playing, isTrue);
      expect(shown.controls, contains(MediaControl.pause));

      await handler.click();
      await _tick();
      expect(c.read(playerProvider).waiting, isFalse);
      expect(c.read(playerProvider).playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
      await ctrl().addVoiceBeyt(t, _item(1, 1000), 2);
      expect(fake.isPlaying, isFalse, reason: 'the next beyt does not resume after the click');
    });

    test('an OS stop ends a voice stream through the controller', () async {
      final t = await stream();
      await handler.stop();
      expect(ctrl().streaming, isFalse);
      expect(c.read(playerProvider).status, PlayerStatus.idle);
      await ctrl().addVoiceBeyt(t, _item(1, 1000), 2);
      expect(fake.appended, isEmpty);
    });

    test('an OS stop of a plain recitation behaves as before', () async {
      final poem = poem2130();
      await ctrl().play(poem, poem.recitations.first);
      await handler.stop();
      expect(fake.isPlaying, isFalse);
      expect(c.read(playerProvider).status, PlayerStatus.ready, reason: 'the player stays, as in phase 1');
    });
  });
}

PlaylistItem _item(int n, int ms) => PlaylistItem(
  uri: Uri.parse('file:///b$n.wav'),
  duration: Duration(milliseconds: ms),
);

Future<void> _tick() => Future<void>.delayed(Duration.zero);
