import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/features/player/sync_engine.dart';

void main() {
  final pts2840 = parseSyncJson(File('test/fixtures/audio/verses_2840.json').readAsStringSync());
  final valid = {for (var i = 1; i <= 14; i++) i};

  test('maps positions to verses (2840)', () {
    final t = SyncTimeline(pts2840, validVOrders: valid);
    expect(t.vOrderAt(Duration.zero), 1);
    expect(t.vOrderAt(const Duration(milliseconds: 7385)), 1);
    expect(t.vOrderAt(const Duration(milliseconds: 7386)), 2);
    expect(t.vOrderAt(const Duration(hours: 1)), 14);
    expect(t.startOf(3), const Duration(milliseconds: 15486));
  });

  test('before the first verse there is no current verse', () {
    final t = SyncTimeline(const [SyncPoint(0, 0), SyncPoint(1, 5000), SyncPoint(2, 9000)]);
    expect(t.vOrderAt(const Duration(seconds: 2)), isNull);
    expect(t.vOrderAt(const Duration(seconds: 6)), 1);
  });

  test('normalises out-of-order, duplicate and invalid points', () {
    final t = SyncTimeline(
      const [SyncPoint(3, 9000), SyncPoint(1, 1000), SyncPoint(2, 5000), SyncPoint(2, 6000), SyncPoint(77, 7000)],
      validVOrders: {1, 2, 3},
    );
    expect(t.startOf(2), const Duration(milliseconds: 5000));
    expect(t.vOrderAt(const Duration(milliseconds: 7500)), 2);
    expect(t.startOf(77), isNull);
    expect(t.vOrderAt(const Duration(milliseconds: 9500)), 3);
  });

  test('records the end marker and missing lines', () {
    final t = SyncTimeline(const [SyncPoint(1, 1000), SyncPoint(3, 5000), SyncPoint(-2, 9000)]);
    expect(t.end, const Duration(milliseconds: 9000));
    expect(t.startOf(2), isNull);
    expect(t.vOrderAt(const Duration(milliseconds: 9500)), isNull);
  });

  test('empty timeline', () {
    final t = SyncTimeline(const []);
    expect(t.isEmpty, isTrue);
    expect(t.vOrderAt(const Duration(seconds: 1)), isNull);
  });

  test('band poem (hafez montasab 45, recitation 19373): sync is by vOrder; unread lines are missing', () {
    final pts = parseSyncJson(File('test/fixtures/audio/verses_19373.json').readAsStringSync());
    final t = SyncTimeline(pts, validVOrders: {for (var i = 1; i <= 20; i++) i});
    expect(t.vOrderAt(const Duration(seconds: 70)), 9);
    expect(t.startOf(7), isNull); // skipped by the reciter
    expect(t.startOf(19), isNull); // band line (position 2) not read
    expect(t.startOf(18), const Duration(milliseconds: 134250));
  });
}
