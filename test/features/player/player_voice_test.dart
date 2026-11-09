import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';

const _artist = 'خوانش ماشینی';
const _sync = [SyncPoint(11, 0), SyncPoint(22, 750), SyncPoint(33, 1500), SyncPoint(-2, 2000)];

Poem _voicePoem({List<Recitation> recitations = const []}) => Poem(
  id: 7,
  title: 'غزل',
  fullTitle: 'غزل',
  fullUrl: '/x',
  plainText: '',
  verses: [
    for (final v in [11, 22, 33]) Verse(vOrder: v, position: VersePosition.right, text: 'v$v'),
  ],
  recitations: recitations,
);

void main() {
  late FakeAudioBackend backend;
  late ProviderContainer c;
  final wav = File('voice-7.wav');

  setUp(() {
    backend = FakeAudioBackend();
    c = ProviderContainer(
      overrides: [
        audioBackendProvider.overrideWithValue(backend),
        poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
      ],
    );
    addTearDown(c.dispose);
  });

  PlayerController ctrl() => c.read(playerProvider.notifier);

  test('playVoice loads the local file and builds the timeline', () async {
    await ctrl().playVoice(_voicePoem(), wav, _sync, artist: _artist);
    final s = c.read(playerProvider);
    expect(backend.loaded.single, Uri.file(wav.path));
    expect(backend.infos.single.id, 'voice-7');
    expect(backend.infos.single.artist, _artist);
    expect(s.recitation!.id, kVoiceRecitationId);
    expect(s.status, PlayerStatus.ready);
    expect(backend.isPlaying, isTrue);
    expect(s.timeline.vOrderAt(const Duration(milliseconds: 800)), 22);
  });

  test('next on voice with no human recitations does nothing', () async {
    await ctrl().playVoice(_voicePoem(), wav, _sync, artist: _artist);
    await ctrl().next();
    expect(backend.loaded, hasLength(1));
    expect(c.read(playerProvider).recitation!.id, kVoiceRecitationId);
  });

  test('next on voice goes to the first human recitation', () async {
    final human = poem2130().recitations;
    final poem = _voicePoem(recitations: human);
    await ctrl().playVoice(poem, wav, _sync, artist: _artist);
    await ctrl().next();
    expect(c.read(playerProvider).recitation!.id, human.first.id);
    await ctrl().playVoice(poem, wav, _sync, artist: _artist);
    await ctrl().previous();
    expect(c.read(playerProvider).recitation!.id, human.last.id);
  });

  test('retry on voice reloads the same file', () async {
    await ctrl().playVoice(_voicePoem(), wav, _sync, artist: _artist);
    await ctrl().retry();
    expect(backend.loaded, [Uri.file(wav.path), Uri.file(wav.path)]);
    expect(c.read(playerProvider).recitation!.id, kVoiceRecitationId);
    expect(c.read(playerProvider).timeline.vOrderAt(const Duration(milliseconds: 800)), 22);
  });

  test('stop while the voice is still loading: it never plays', () async {
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    final playing = ctrl().playVoice(_voicePoem(), wav, _sync, artist: _artist);
    await ctrl().stop();
    gate.complete();
    await playing;
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerProvider).status, PlayerStatus.idle);
    expect(c.read(playerProvider).recitation, isNull);
    expect(backend.isPlaying, isFalse);
  });

  test('seekToVOrder works on the voice', () async {
    await ctrl().playVoice(_voicePoem(), wav, _sync, artist: _artist);
    expect(await ctrl().seekToVOrder(33), isTrue);
    expect(backend.seeks.last, const Duration(milliseconds: 1500));
  });
}
