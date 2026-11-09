import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/voice/app/wav.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

/// Desktop spike: does the platform player handle a playlist, an append while playing, and an
/// append after completion? Logs `[spike]` lines with the gap at each join and monotonicity.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Uri tone(Directory dir, String name, double hz) {
    const rate = 24000;
    final pcm = Int16List(rate);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = (math.sin(2 * math.pi * hz * i / rate) * 8000).round();
    }
    final f = File('${dir.path}/$name.wav')..writeAsBytesSync(pcm16Wav(pcm, rate));
    return f.uri;
  }

  testWidgets('spike: playlist, append mid-play, append after completion', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ganj_spike_');
      final player = AudioPlayer();
      final t0 = DateTime.now();
      int ms() => DateTime.now().difference(t0).inMilliseconds;

      var index = 0;
      var lastGlobal = Duration.zero;
      var monotonic = true;
      var backwardJumps = <String>[];
      final events = <String>[];
      const itemLen = Duration(seconds: 1);

      final subs = <StreamSubscription<Object?>>[
        player.currentIndexStream.distinct().listen((i) {
          index = i ?? 0;
          events.add('${ms()}ms index=$i');
        }),
        player.playingStream.distinct().listen((p) => events.add('${ms()}ms playing=$p')),
        player.positionStream.listen((p) {
          final global = itemLen * index + p;
          if (global < lastGlobal - const Duration(milliseconds: 60)) {
            monotonic = false;
            backwardJumps.add('${ms()}ms $lastGlobal -> $global (index=$index)');
          }
          lastGlobal = global;
        }),
        player.processingStateStream.distinct().listen((s) => events.add('${ms()}ms state=$s')),
        player.durationStream.listen((d) => events.add('${ms()}ms duration=$d')),
      ];

      try {
        final a = tone(dir, 'a', 440), b = tone(dir, 'b', 550), c = tone(dir, 'c', 660), d = tone(dir, 'd', 770);
        await player.setAudioSources([AudioSource.uri(a), AudioSource.uri(b)]);
        events.add('${ms()}ms loaded 2 items');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        unawaited(player.play());
        for (var i = 0; i < 14; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          events.add('${ms()}ms tick pos=${player.position} idx=${player.currentIndex} playing=${player.playing}');
        }
        events.add('${ms()}ms append c (index=$index)');
        try {
          await player.addAudioSource(AudioSource.uri(c));
          events.add('${ms()}ms append c ok, length=${player.sequence.length}');
        } catch (e) {
          events.add('${ms()}ms append c FAILED $e');
        }
        // Let everything finish.
        for (var i = 0; i < 80 && player.processingState != ProcessingState.completed; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        events.add('${ms()}ms after wait state=${player.processingState} index=$index');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final completedAt = ms();
        events.add('${ms()}ms append d after completion');
        try {
          await player.addAudioSource(AudioSource.uri(d));
          events.add('${ms()}ms append d ok, length=${player.sequence.length} state=${player.processingState}');
          unawaited(player.play());
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          events.add('${ms()}ms after d: state=${player.processingState} index=$index pos=${player.position}');
        } catch (e) {
          events.add('${ms()}ms append d FAILED $e');
        }
        debugPrint('[spike] completedAt=$completedAt');
      } finally {
        for (final s in subs) {
          await s.cancel();
        }
        for (final e in events) {
          debugPrint('[spike] $e');
        }
        debugPrint('[spike] monotonic=$monotonic jumps=$backwardJumps lastGlobal=$lastGlobal');
        await player.dispose();
        dir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('JustAudioBackend: global position, seek, append, completed', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('ganj_spike2_');
      final backend = JustAudioBackend();
      final pos = <Duration>[];
      final items = <int?>[];
      var completed = 0;
      final subs = [
        backend.position.listen(pos.add),
        backend.currentItem.listen(items.add),
        backend.completed.listen((c) => c ? completed++ : null),
      ];
      Duration? total;
      subs.add(backend.duration.listen((d) => total = d));
      try {
        PlaylistItem it(String n, double hz) => PlaylistItem(uri: tone(dir, n, hz), duration: const Duration(seconds: 1));
        await backend.loadPlaylist([it('a', 440), it('b', 550)], info: const MediaInfo(id: 'x', title: 't', artist: 'a'));
        // A late subscriber still gets the total.
        expect(await backend.duration.first.timeout(const Duration(seconds: 1)), const Duration(seconds: 2));
        final afterSeek = pos.length;
        await backend.seek(const Duration(milliseconds: 1500)); // item 1, 500 ms in
        await backend.play(); // immediately after loadPlaylist: no sleeps
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(await backend.playing.first.timeout(const Duration(seconds: 1), onTimeout: () => backend.player.playing), isTrue);
        await backend.appendItem(it('c', 660));
        await Future<void>.delayed(const Duration(milliseconds: 2200));
        debugPrint('[spike2] total=$total items=$items completed=$completed');
        debugPrint('[spike2] positions=${pos.map((p) => p.inMilliseconds).toList()}');
        expect(total, const Duration(seconds: 3));
        expect(items.contains(2), isTrue);
        expect(completed, 1);
        // From the seek on, the global position never falls below the seek target, and is monotonic.
        var prev = const Duration(milliseconds: 1500);
        for (final p in pos.skip(afterSeek)) {
          expect(p, greaterThanOrEqualTo(prev - const Duration(milliseconds: 60)), reason: 'positions: $pos');
          prev = p;
        }
        expect(pos.last, greaterThan(const Duration(milliseconds: 2800)));
      } finally {
        for (final s in subs) {
          await s.cancel();
        }
        await backend.dispose();
        // After dispose, loading and appending are no-ops rather than errors.
        await backend.loadPlaylist([PlaylistItem(uri: Uri.file('${dir.path}/a.wav'), duration: const Duration(seconds: 1))], info: const MediaInfo(id: 'x', title: 't', artist: 'a'));
        await backend.appendItem(PlaylistItem(uri: Uri.file('${dir.path}/a.wav'), duration: const Duration(seconds: 1)));
        dir.deleteSync(recursive: true);
      }
    });
  });
}
