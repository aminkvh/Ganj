import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/audio_handler.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';

const _artist = 'خوانش ماشینی';

Poem _poem({int id = 7}) => Poem(
  id: id,
  title: 'غزل',
  fullTitle: 'غزل',
  fullUrl: '/x',
  plainText: '',
  verses: [
    for (final v in [1, 2, 3, 4]) Verse(vOrder: v, position: VersePosition.right, text: 'v$v'),
  ],
  recitations: const [],
);

PlaylistItem _item(int n, int ms) => PlaylistItem(
  uri: Uri.parse('file:///b$n.wav'),
  duration: Duration(milliseconds: ms),
);

Duration _ms(int ms) => Duration(milliseconds: ms);

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioBackend backend;
  late ProviderContainer c;

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
  PlayerState st() => c.read(playerProvider);

  late VoiceStreamToken tok;
  VoiceStreamToken begin({int id = 7}) => tok = ctrl().startVoiceStream(
    _poem(id: id),
    artist: _artist,
    first: _item(0, 1000),
    firstVOrder: 1,
  );
  Future<VoiceStreamToken> start({int id = 7}) async {
    final t = begin(id: id);
    await t.started;
    return t;
  }

  Future<void> add(PlaylistItem item, int vOrder) => ctrl().addVoiceBeyt(tok, item, vOrder);
  void end() => ctrl().endVoiceStream(tok);

  test('stream starts on first beyt, timeline grows', () async {
    expect(ctrl().canStream, isTrue);
    await start();
    expect(ctrl().streaming, isTrue);
    expect(backend.playlists.single, hasLength(1));
    expect(backend.isPlaying, isTrue);
    expect(st().status, PlayerStatus.ready);
    expect(st().recitation!.id, kVoiceRecitationId);
    expect(st().duration, _ms(1000));
    expect(st().timeline.vOrderAt(_ms(500)), 1);
    expect(st().timeline.startOf(2), isNull);

    await add(_item(1, 1200), 2);
    expect(backend.appended, hasLength(1));
    expect(st().duration, _ms(2200));
    expect(st().timeline.startOf(2), _ms(1000));
    expect(st().timeline.vOrderAt(_ms(1500)), 2);

    backend.emitItemPosition(1, _ms(300));
    await _tick();
    expect(st().position, _ms(1300));
    expect(st().currentVOrder, 2);
  });

  test('canStream follows the backend', () {
    backend.playlistSupported = false;
    expect(ctrl().canStream, isFalse);
  });

  test('stall waits at the boundary and resumes on the next beyt', () async {
    final stalls = <void>[];
    final sub = ctrl().voiceStalls.listen(stalls.add);
    addTearDown(sub.cancel);
    await start();

    backend.emitItemPosition(0, _ms(600));
    await _tick();
    expect(st().waiting, isFalse);

    backend.emitItemPosition(0, _ms(900)); // within 150 ms of the end of the last ready item
    await _tick();
    expect(st().waiting, isTrue);
    expect(backend.isPlaying, isFalse);
    expect(st().playing, isTrue, reason: 'the intent stays «playing» while waiting');
    expect(stalls, hasLength(1));

    // More position events at the boundary do not count as new stalls.
    backend.emitItemPosition(0, _ms(910));
    await _tick();
    expect(stalls, hasLength(1));

    await add(_item(1, 1000), 2);
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
    expect(backend.seeks, isEmpty, reason: 'nothing is skipped: playback continues from the boundary');
    expect(st().position, _ms(910));

    backend.emitItemPosition(1, _ms(50));
    await _tick();
    expect(st().position, _ms(1050));
    expect(st().currentVOrder, 2);
  });

  test('completion before the next beyt also waits, and the append resumes', () async {
    await start();
    backend.emitItemCompleted(0);
    await _tick();
    expect(st().waiting, isTrue);
    await add(_item(1, 1000), 2);
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
    expect(backend.resumed, 0, reason: 'the controller plays after the append, not the backend');
    backend.emitItemPosition(1, _ms(100));
    await _tick();
    expect(st().position, _ms(1100), reason: 'positions are not ignored after the waiting completion');
  });

  test('pausing while waiting does not resume on the next beyt', () async {
    await start();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isTrue);
    await ctrl().toggle();
    expect(st().waiting, isFalse);
    expect(st().playing, isFalse);
    await add(_item(1, 1000), 2);
    expect(backend.isPlaying, isFalse);
  });

  test('seek to an unready beyt is ignored', () async {
    await start();
    await add(_item(1, 1000), 2);
    backend.emitItemPosition(0, _ms(400));
    await _tick();
    expect(await ctrl().seekToVOrder(3), isFalse);
    expect(backend.seeks, isEmpty);
    expect(st().position, _ms(400));

    expect(await ctrl().seekToVOrder(2), isTrue);
    expect(backend.seeks.single, _ms(1000));
  });

  test('a plain seek past the ready part is ignored', () async {
    await start();
    await ctrl().seek(_ms(5000));
    expect(backend.seeks, isEmpty);
    await ctrl().seek(_ms(300));
    expect(backend.seeks.single, _ms(300));
  });

  test('end marker after endVoiceStream', () async {
    await start();
    await add(_item(1, 1000), 2);
    expect(st().timeline.end, isNull);
    end();
    expect(st().timeline.end, _ms(2000));
    expect(st().timeline.vOrderAt(_ms(2000)), isNull);

    // After the end, reaching the last item's end is a real finish, not a stall.
    backend.emitItemPosition(1, _ms(950));
    await _tick();
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
    backend.emitItemCompleted(1);
    await _tick();
    expect(st().playing, isFalse);
    expect(st().currentVOrder, isNull);

    // No more beyts are taken after the end.
    await add(_item(2, 1000), 3);
    expect(backend.appended, hasLength(1));
  });

  test('endVoiceStream while waiting plays out the last beyt', () async {
    await start();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isTrue);
    end();
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
  });

  test('endVoiceStream after the backend completed finishes instead of playing', () async {
    await start();
    backend.emitItemCompleted(0);
    await _tick();
    expect(st().waiting, isTrue);
    end();
    expect(st().waiting, isFalse);
    expect(st().playing, isFalse);
    expect(backend.isPlaying, isFalse);
  });

  test('beyts added while a retry reloads are appended in order, with the same token', () async {
    final first = await start();
    backend.emitError(Exception('boom'));
    await _tick();
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    final retried = ctrl().retry();
    await _tick();
    final added = ctrl().addVoiceBeyt(first, _item(1, 1000), 2);
    gate.complete();
    await retried;
    await added;
    expect(backend.playlists.last, hasLength(1));
    expect(backend.appended.single.uri, Uri.parse('file:///b1.wav'));
    expect(st().timeline.startOf(2), _ms(1000));
  });

  test('an old token is ignored after a new startVoiceStream', () async {
    final old = await start();
    final fresh = await start(id: 8);
    expect(fresh, isNot(old));
    await ctrl().addVoiceBeyt(old, _item(1, 1000), 2);
    ctrl().endVoiceStream(old);
    expect(backend.appended, isEmpty);
    expect(st().timeline.end, isNull);
    await ctrl().addVoiceBeyt(fresh, _item(1, 1000), 2);
    expect(backend.appended, hasLength(1));
  });

  test('endVoiceStream before the load finishes still places the end marker', () async {
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    begin();
    await _tick();
    end();
    gate.complete();
    await tok.started;
    expect(st().timeline.end, _ms(1000));
  });

  test('beyts added while the playlist is still loading are appended in order', () async {
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    begin();
    await _tick();
    final added = add(_item(1, 1000), 2);
    gate.complete();
    await tok.started;
    await added;
    expect(backend.playlists.single, hasLength(1));
    expect(backend.appended.single.uri, Uri.parse('file:///b1.wav'));
    expect(st().timeline.startOf(2), _ms(1000));
  });

  test('endVoiceStream during a retry reload still places the end marker', () async {
    await start();
    backend.emitError(Exception('boom'));
    await _tick();
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    final retried = ctrl().retry();
    await _tick();
    end();
    gate.complete();
    await retried;
    expect(st().timeline.end, _ms(1000));
  });

  test('completion wait, pause, play at the edge, then end: the reading finishes', () async {
    await start();
    backend.emitItemCompleted(0);
    backend.emitItemPosition(0, _ms(1000)); // platforms report the final position after finishing
    await _tick();
    expect(st().waiting, isTrue);
    await ctrl().toggle(); // pause
    await _tick();
    expect(st().waiting, isFalse);
    await ctrl().toggle(); // play: nothing to play yet
    await _tick();
    expect(st().waiting, isTrue);
    expect(backend.isPlaying, isFalse);
    end();
    expect(st().waiting, isFalse);
    expect(st().playing, isFalse);
    expect(st().currentVOrder, isNull);
    expect(backend.isPlaying, isFalse, reason: 'no play() into silence');
  });

  test('completion wait, pause, then end: the reading is marked finished', () async {
    await start();
    backend.emitItemPosition(0, _ms(500));
    await _tick();
    backend.emitItemCompleted(0);
    await _tick();
    await ctrl().toggle(); // pause
    await _tick();
    end();
    expect(st().playing, isFalse);
    expect(st().currentVOrder, isNull);
    backend.emitItemPosition(0, _ms(1000)); // the final position report after finishing
    await _tick();
    expect(st().position, _ms(500));
  });

  test('a pause during an in-flight append is respected', () async {
    await start();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isTrue);
    final gate = Completer<void>();
    backend.beforeAppend = gate.future;
    final added = add(_item(1, 1000), 2);
    await _tick();
    await ctrl().pause();
    gate.complete();
    await added;
    expect(backend.isPlaying, isFalse);
    expect(backend.resumed, 0);
    expect(st().playing, isFalse);
  });

  test('a pause wins over a completion already queued in the same tick', () async {
    final stalls = <void>[];
    final sub = ctrl().voiceStalls.listen(stalls.add);
    addTearDown(sub.cancel);
    await start();
    backend.emitItemPosition(0, _ms(700));
    await _tick();
    backend.emitItemCompleted(0); // queued, not yet delivered
    final paused = ctrl().toggle();
    expect(st().playing, isFalse, reason: 'the pause is in the state at once');
    await paused;
    await _tick();
    expect(st().waiting, isFalse);
    expect(stalls, isEmpty);
  });

  test('an end with the last append in flight still plays the last beyt', () async {
    await start();
    await add(_item(1, 1000), 2);
    final gate = Completer<void>();
    backend.beforeAppend = gate.future;
    final added = add(_item(2, 1000), 3);
    await _tick();
    end(); // right after the last add, its append still held
    backend.emitItemCompleted(1); // the previous beyt ends before the append lands
    await _tick();
    expect(st().waiting, isTrue, reason: 'the last beyt is still coming');
    expect(st().playing, isTrue);
    gate.complete();
    await added;
    expect(backend.appended, hasLength(2));
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
    expect(st().timeline.startOf(3), _ms(2000));
    backend.emitItemPosition(2, _ms(500));
    await _tick();
    expect(st().currentVOrder, 3);
    expect(st().waiting, isFalse, reason: 'after the last append, reaching the end is a finish, not a wait');
    backend.emitItemCompleted(2);
    await _tick();
    expect(st().playing, isFalse);
    expect(st().currentVOrder, isNull);
  });

  test('token.started completes after the first load even while an append is held', () async {
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    backend.beforeAppend = Completer<void>().future; // never lets the append finish
    begin();
    await _tick();
    unawaited(add(_item(1, 1000), 2));
    gate.complete();
    var done = false;
    unawaited(tok.started.then((_) => done = true));
    await _tick();
    await _tick();
    expect(done, isTrue);
    expect(st().status, PlayerStatus.ready);
  });

  test('a completion while paused is not turned into a wait or a stall', () async {
    final stalls = <void>[];
    final sub = ctrl().voiceStalls.listen(stalls.add);
    addTearDown(sub.cancel);
    await start();
    backend.emitItemPosition(0, _ms(700));
    await _tick();
    await ctrl().toggle(); // pause near the end
    await _tick();
    backend.emitItemCompleted(0);
    await _tick();
    expect(st().waiting, isFalse);
    expect(stalls, isEmpty);
    await add(_item(1, 1000), 2);
    expect(backend.isPlaying, isFalse);
    expect(backend.resumed, 0);
  });

  test('an outside pause while waiting cancels the wait', () async {
    await start();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isTrue);
    await ctrl().pause(); // what the OS controls call
    expect(st().waiting, isFalse);
    expect(st().playing, isFalse);
    await add(_item(1, 1000), 2);
    expect(backend.isPlaying, isFalse);
    await ctrl().resume();
    expect(backend.isPlaying, isTrue);
  });

  test('play at the edge waits without reporting a stall', () async {
    final stalls = <void>[];
    final sub = ctrl().voiceStalls.listen(stalls.add);
    addTearDown(sub.cancel);
    await start();
    await ctrl().toggle(); // pause
    await _tick();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isFalse);
    await ctrl().toggle(); // play at the edge
    await _tick();
    expect(st().waiting, isTrue);
    expect(stalls, isEmpty);
  });

  test('a seek to the edge waits without reporting a stall', () async {
    final stalls = <void>[];
    final sub = ctrl().voiceStalls.listen(stalls.add);
    addTearDown(sub.cancel);
    await start();
    await ctrl().seek(_ms(950));
    await _tick();
    expect(st().waiting, isTrue);
    expect(stalls, isEmpty);
  });

  test('a seek while waiting leaves waiting and plays', () async {
    await start();
    backend.emitItemPosition(0, _ms(900));
    await _tick();
    expect(st().waiting, isTrue);
    await ctrl().seek(_ms(200));
    await _tick();
    expect(st().waiting, isFalse);
    expect(backend.isPlaying, isTrue);
    expect(backend.seeks.single, _ms(200));
  });

  test('the stall margin scales with the playback speed', () async {
    await start();
    await ctrl().setSpeed(2);
    backend.emitItemPosition(0, _ms(750)); // 250 ms of audio left = 125 ms of wall time at ×2
    await _tick();
    expect(st().waiting, isTrue);
  });

  test('stop ends the stream and later beyts are ignored', () async {
    await start();
    await ctrl().stop();
    expect(ctrl().streaming, isFalse);
    await add(_item(1, 1000), 2);
    expect(backend.appended, isEmpty);
    expect(st().status, PlayerStatus.idle);
  });

  test('stop resets the state at once; a stream started before its backend stop ends keeps its state', () async {
    await start();
    final stopping = ctrl().stop();
    expect(st().poem, isNull); // synchronously
    expect(st().status, PlayerStatus.idle);
    final next = begin(id: 8);
    await next.started;
    await stopping;
    await _tick();
    expect(st().poem?.id, 8);
    expect(st().status, PlayerStatus.ready);
    expect(ctrl().streaming, isTrue);
    expect(ctrl().isCurrentStream(next), isTrue);
  });

  test('isCurrentStream names only the stream being played', () async {
    final a = await start();
    expect(ctrl().isCurrentStream(a), isTrue);
    final b = await start(id: 8);
    expect(ctrl().isCurrentStream(a), isFalse);
    expect(ctrl().isCurrentStream(b), isTrue);
    await ctrl().stop();
    expect(ctrl().isCurrentStream(b), isFalse);
  });

  test('a stop during the playlist load never starts the stream', () async {
    final gate = Completer<void>();
    backend.beforeLoad = gate.future;
    final started = start();
    await _tick();
    await ctrl().stop();
    gate.complete();
    await started;
    expect(backend.isPlaying, isFalse);
    expect(st().status, PlayerStatus.idle);
    expect(ctrl().streaming, isFalse);
  });

  test('a new play ends the stream', () async {
    await start();
    await ctrl().playVoice(_poem(), File('voice-7.wav'), const [], artist: _artist);
    expect(ctrl().streaming, isFalse);
    await add(_item(1, 1000), 2);
    expect(backend.appended, isEmpty);
  });

  test('retry reloads the ready beyts and keeps streaming', () async {
    await start();
    await add(_item(1, 1000), 2);
    backend.emitError(Exception('boom'));
    await _tick();
    expect(st().status, PlayerStatus.error);
    await ctrl().retry();
    expect(backend.playlists.last, hasLength(2));
    expect(ctrl().streaming, isTrue);
    expect(st().status, PlayerStatus.ready);
    await add(_item(2, 1000), 3);
    expect(st().timeline.startOf(3), _ms(2000));
  });

  test('media session has no duration and no seek while streaming', () async {
    await start();
    final info = backend.infos.single;
    expect(info.live, isTrue);
    expect(info.id, 'voice-7');
    expect(mediaItemFor(info, _ms(5000)).duration, isNull);
    expect(mediaSystemActions(info), isNot(contains(MediaAction.seek)));

    const human = MediaInfo(id: '1', title: 't', artist: 'a');
    expect(mediaItemFor(human, _ms(5000)).duration, _ms(5000));
    expect(mediaSystemActions(human), contains(MediaAction.seek));
  });
}
