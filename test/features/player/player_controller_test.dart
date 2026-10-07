import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioBackend backend;
  late ProviderContainer c;

  late FixtureRepository repo;

  setUp(() {
    backend = FakeAudioBackend();
    repo = FixtureRepository();
    c = ProviderContainer(
      overrides: [audioBackendProvider.overrideWithValue(backend), poetryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
  });

  PlayerController ctrl() => c.read(playerProvider.notifier);

  test('play loads the mp3 and starts playback', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    expect(backend.loaded.single.toString(), poem.recitations.first.mp3Url);
    expect(backend.isPlaying, isTrue);
    expect(backend.infos.single.title, poem.title);
    expect(c.read(playerProvider).status, PlayerStatus.ready);
  });

  test('position drives the current verse', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    backend.emitPosition(const Duration(seconds: 8));
    await flush();
    expect(c.read(playerProvider).currentVOrder, 2);
  });

  test('seekToVOrder jumps to the verse start; missing verse returns false', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    expect(await ctrl().seekToVOrder(3), isTrue);
    expect(backend.seeks.last, const Duration(milliseconds: 15486));
    expect(await ctrl().seekToVOrder(99), isFalse);
  });

  test('a recitation not in sync never highlights', () async {
    final poem = poem2130();
    final r = poem.recitations.first;
    final unsynced = r.copyWith(inSync: false);
    await ctrl().play(poem, unsynced);
    backend.emitPosition(const Duration(seconds: 8));
    await flush();
    expect(c.read(playerProvider).currentVOrder, isNull);
  });

  test('load failure ends in error state, not stuck loading', () async {
    backend.failLoad = StateError('404');
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    expect(c.read(playerProvider).status, PlayerStatus.error);
  });

  test('toggle pauses and resumes; stop resets', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    await flush();
    await ctrl().toggle();
    await flush();
    expect(backend.isPlaying, isFalse);
    await ctrl().toggle();
    await flush();
    expect(backend.isPlaying, isTrue);
    await ctrl().stop();
    expect(c.read(playerProvider).status, PlayerStatus.idle);
    expect(c.read(playerProvider).currentVOrder, isNull);
  });

  test('MediaInfo carries the reciter as artist', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    expect(backend.infos.single, isA<MediaInfo>());
    expect(backend.infos.single.artist, 'فریدون فرح‌اندوز');
  });

  test('duration reported after load (Windows plugin) updates state', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    backend.emitDuration(const Duration(minutes: 3, seconds: 5));
    await flush();
    expect(c.read(playerProvider).duration, const Duration(minutes: 3, seconds: 5));
  });

  test('duration that arrives during load is kept when load() returns null', () async {
    backend.durationOnlyViaStream = true;
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    expect(c.read(playerProvider).duration, const Duration(minutes: 1, seconds: 37));
  });

  test('a slower, superseded play() never loads its audio', () async {
    final poem = poem2130();
    final a = poem.recitations[0], b = poem.recitations[1];
    repo.syncGates[a.id] = Completer<void>(); // A's sync is slow
    final playA = ctrl().play(poem, a);
    await flush();
    await ctrl().play(poem, b);
    repo.syncGates[a.id]!.complete();
    await playA;
    expect(backend.loaded.map((u) => u.toString()), [b.mp3Url]);
    expect(c.read(playerProvider).recitation!.id, b.id);
  });

  test('a playback error after loading shows the error state', () async {
    final poem = poem2130();
    await ctrl().play(poem, poem.recitations.first);
    backend.emitError(StateError('stream dropped'));
    await flush();
    expect(c.read(playerProvider).status, PlayerStatus.error);
  });
}
