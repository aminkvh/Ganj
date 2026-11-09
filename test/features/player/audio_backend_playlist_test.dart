import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/unavailable_audio.dart';

import '../../support/fake_audio_backend.dart';

const _info = MediaInfo(id: 'p1', title: 't', artist: 'a');

PlaylistItem _item(int n, int ms) => PlaylistItem(uri: Uri.parse('file:///b$n.wav'), duration: Duration(milliseconds: ms));

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlaylistTimeline', () {
    final tl = PlaylistTimeline([
      const Duration(milliseconds: 1000),
      const Duration(milliseconds: 1250),
      const Duration(milliseconds: 800),
    ]);

    test('global position = earlier items + offset', () {
      expect(tl.global(1, const Duration(milliseconds: 200)), const Duration(milliseconds: 1200));
      expect(tl.total, const Duration(milliseconds: 3050));
    });

    test('locate maps global to item and offset', () {
      expect(tl.locate(const Duration(milliseconds: 500)), (index: 0, offset: const Duration(milliseconds: 500)));
      expect(tl.locate(const Duration(milliseconds: 1000)), (index: 1, offset: Duration.zero));
      expect(tl.locate(const Duration(milliseconds: 2300)), (index: 2, offset: const Duration(milliseconds: 50)));
    });

    test('locate clamps past the end to the end of the last item', () {
      expect(tl.locate(const Duration(seconds: 10)), (index: 2, offset: const Duration(milliseconds: 800)));
      expect(tl.locate(const Duration(seconds: -1)), (index: 0, offset: Duration.zero));
    });

    test('add extends the table', () {
      final t = PlaylistTimeline([const Duration(seconds: 1)])..add(const Duration(seconds: 2));
      expect(t.length, 2);
      expect(t.total, const Duration(seconds: 3));
      expect(t.locate(const Duration(milliseconds: 1500)), (index: 1, offset: const Duration(milliseconds: 500)));
    });
  });

  group('playlistCompletionCounts', () {
    test('the blip right after a seek gives no completion', () {
      expect(playlistCompletionCounts(index: 1, length: 2, sinceSeek: const Duration(milliseconds: 90)), isFalse);
    });

    test('a real end gives a completion', () {
      expect(playlistCompletionCounts(index: 2, length: 3), isTrue);
      expect(playlistCompletionCounts(index: 2, length: 3, sinceSeek: const Duration(seconds: 5)), isTrue);
    });

    test('an end on the last item counts even when the platform reports position 0', () {
      // Position is not an input at all: only index, length and time since a seek.
      expect(playlistCompletionCounts(index: 2, length: 3, sinceSeek: const Duration(seconds: 1)), isTrue);
    });

    test('completion on an earlier item never counts', () {
      expect(playlistCompletionCounts(index: 0, length: 3), isFalse);
    });
  });

  group('PlaylistSeekGate', () {
    test('passes everything when no seek happened', () {
      expect(PlaylistSeekGate().admit(0, Duration.zero), isTrue);
    });

    test('holds stale events until the target item is near the target offset', () {
      final gate = PlaylistSeekGate()..seek((index: 1, offset: const Duration(milliseconds: 500)));
      expect(gate.admit(0, const Duration(milliseconds: 500)), isFalse); // old item
      expect(gate.admit(1, Duration.zero), isFalse); // right item, offset 0 is 500 ms off
      expect(gate.admit(1, const Duration(milliseconds: 520)), isTrue);
      expect(gate.admit(1, const Duration(milliseconds: 600)), isTrue); // released
      // The stale pair repeating after the first good one is still dropped.
      expect(gate.admit(1, Duration.zero), isFalse);
      expect(gate.admit(0, const Duration(milliseconds: 500)), isFalse);
      expect(gate.admit(1, const Duration(milliseconds: 700)), isTrue);
      expect(gate.admit(2, Duration.zero), isTrue); // natural progress to the next item
    });

    test('releases after the timeout so a missed event cannot freeze the position', () {
      var now = DateTime(2026);
      final gate = PlaylistSeekGate(now: () => now)..seek((index: 3, offset: Duration.zero));
      expect(gate.admit(0, const Duration(seconds: 1)), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(gate.admit(0, const Duration(seconds: 1)), isTrue);
    });

    test('sinceSeek tracks the clock and clear forgets the seek', () {
      var now = DateTime(2026);
      final gate = PlaylistSeekGate(now: () => now);
      expect(gate.sinceSeek, isNull);
      gate.seek((index: 0, offset: Duration.zero));
      now = now.add(const Duration(milliseconds: 100));
      expect(gate.sinceSeek, const Duration(milliseconds: 100));
      gate.clear();
      expect(gate.sinceSeek, isNull);
    });
  });

  group('FakeAudioBackend playlist', () {
    test('appendItem counts resume requests and defaults to no resume', () async {
      final f = FakeAudioBackend();
      await f.loadPlaylist([_item(0, 1000)], info: _info);
      await f.appendItem(_item(1, 500));
      expect(f.resumed, 0);
      await f.appendItem(_item(2, 500), resume: true);
      expect(f.resumed, 1);
    });

    late FakeAudioBackend fake;
    setUp(() async {
      fake = FakeAudioBackend();
      await fake.loadPlaylist([_item(0, 1000), _item(1, 1250), _item(2, 800)], info: _info);
    });

    test('supports playlists', () {
      expect(fake.supportsPlaylist, isTrue);
      expect(const UnavailableAudioBackend().supportsPlaylist, isFalse);
    });

    test('global position spans items', () async {
      final seen = <Duration>[];
      fake.position.listen(seen.add);
      fake.emitItemPosition(1, const Duration(milliseconds: 200));
      await _tick();
      expect(seen.single, const Duration(milliseconds: 1200));
    });

    test('duration is the sum of the item durations', () async {
      final seen = <Duration?>[];
      fake.duration.listen(seen.add);
      await fake.appendItem(_item(3, 500));
      await _tick();
      expect(seen.single, const Duration(milliseconds: 3550));
    });

    test('seek global maps to item and offset', () async {
      final items = <int?>[];
      final seen = <Duration>[];
      fake.currentItem.listen(items.add);
      fake.position.listen(seen.add);
      await fake.seek(const Duration(milliseconds: 2300));
      await _tick();
      expect(fake.itemSeeks.single, (index: 2, offset: const Duration(milliseconds: 50)));
      expect(items, [2]);
      expect(seen.single, const Duration(milliseconds: 2300));
    });

    test('append extends the playlist', () async {
      await fake.appendItem(_item(3, 500));
      expect(fake.appended.single.uri.path, '/b3.wav');
      // The new item is reachable by a global seek.
      await fake.seek(const Duration(milliseconds: 3200));
      expect(fake.itemSeeks.last, (index: 3, offset: const Duration(milliseconds: 150)));
    });

    test('completed only after the last item', () async {
      var completed = 0;
      fake.completed.listen((c) => c ? completed++ : null);
      fake.emitItemCompleted(0);
      fake.emitItemCompleted(1);
      await _tick();
      expect(completed, 0);
      fake.emitItemCompleted(2);
      await _tick();
      expect(completed, 1);
    });

    test('an appended item moves the finish line', () async {
      var completed = 0;
      fake.completed.listen((c) => c ? completed++ : null);
      await fake.appendItem(_item(3, 500));
      fake.emitItemCompleted(2);
      await _tick();
      expect(completed, 0);
      fake.emitItemCompleted(3);
      await _tick();
      expect(completed, 1);
    });
  });
}
