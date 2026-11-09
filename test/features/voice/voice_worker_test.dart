import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/voice_worker.dart';

import 'fakes.dart';

/// The fake pins the [VoiceWorker] contract; the isolate worker runs the real engine only when GANJ_VOICE_DIR and
/// GANJ_SHERPA_LIB_DIR are set (like voice_engine_test.dart).
void main() {
  final dir = Platform.environment['GANJ_VOICE_DIR'];
  final libDir = Platform.environment['GANJ_SHERPA_LIB_DIR'];
  final skip = dir == null || libDir == null ? 'set GANJ_VOICE_DIR and GANJ_SHERPA_LIB_DIR' : null;

  List<BeytRequest> beyts(int n) => [
    for (var i = 0; i < n; i++) BeytRequest(i, ['a$i', 'b$i']),
  ];

  test('fake worker: new read cancels old', () async {
    final w = FakeVoiceWorker(delay: const Duration(milliseconds: 40));
    final first = <int>[];
    final firstDone = w.read(beyts(10)).forEach((a) => first.add(a.index));
    await Future<void>.delayed(const Duration(milliseconds: 110));
    final second = await w.read(beyts(4)).toList();
    await firstDone; // closes without an error
    expect(first.length, lessThan(10));
    expect(second.map((a) => a.index), [0, 1, 2, 3]);
    expect(second.first.sampleRate, 24000);
    expect(second.first.pcm.length, 12000);
    await w.dispose();
  });

  test('fake worker: failOn emits VoiceReadError and carries on; failLoad emits VoiceEngineLoadError', () async {
    final w = FakeVoiceWorker(failOn: 1);
    final got = <int>[];
    final errors = <Object>[];
    final done = Completer<void>();
    w.read(beyts(3)).listen((a) => got.add(a.index), onError: errors.add, onDone: done.complete);
    await done.future;
    expect(got, [0, 2]);
    expect(errors.single, isA<VoiceReadError>().having((e) => e.index, 'index', 1));
    await expectLater(
      FakeVoiceWorker(failLoad: true).read(beyts(2)),
      emitsInOrder([emitsError(isA<VoiceEngineLoadError>()), emitsDone]),
    );
  });

  test('fake worker: cancel() closes the stream at once', () async {
    final w = FakeVoiceWorker(delay: const Duration(seconds: 5));
    var done = false;
    w.read(beyts(3)).listen((_) {}, onDone: () => done = true);
    w.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });

  test('isolate death is VoiceWorkerDied, not VoiceEngineLoadError', () async {
    final tmp = Directory.systemTemp.createTempSync('ganj_voice_empty');
    final w = IsolateVoiceWorker(tmp.path, threads: 2)..debugDieOnRead = true;
    try {
      await expectLater(w.read(beyts(1)), emitsInOrder([emitsError(isA<VoiceWorkerDied>()), emitsDone]));
    } finally {
      await w.dispose();
      tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('bad folder gives VoiceEngineLoadError', () async {
    final tmp = Directory.systemTemp.createTempSync('ganj_voice_empty');
    final w = IsolateVoiceWorker(tmp.path, threads: 2);
    try {
      await expectLater(w.read(beyts(1)), emitsInOrder([emitsError(isA<VoiceEngineLoadError>()), emitsDone]));
    } finally {
      await w.dispose();
      tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('idle: the isolate is released after the idle time, and the next read respawns it', () async {
    final tmp = Directory.systemTemp.createTempSync('ganj_voice_empty');
    final w = IsolateVoiceWorker(tmp.path, threads: 2, idle: const Duration(milliseconds: 300));
    try {
      await expectLater(w.read(beyts(1)), emitsInOrder([emitsError(isA<VoiceEngineLoadError>()), emitsDone]));
      expect(w.debugHasIsolate, isTrue);
      expect(w.debugSpawns, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(w.debugHasIsolate, isFalse);
      // Lazily back: a new isolate, which answers like the first.
      await expectLater(w.read(beyts(1)), emitsInOrder([emitsError(isA<VoiceEngineLoadError>()), emitsDone]));
      expect(w.debugSpawns, 2);
    } finally {
      await w.dispose();
      tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('idle: each read restarts the idle time; the default is 3 minutes', () async {
    final tmp = Directory.systemTemp.createTempSync('ganj_voice_empty');
    expect(IsolateVoiceWorker(tmp.path).idle, const Duration(minutes: 3));
    final w = IsolateVoiceWorker(tmp.path, threads: 2, idle: const Duration(milliseconds: 800));
    try {
      await w.read(beyts(1)).handleError((_) {}).drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await w.read(beyts(1)).handleError((_) {}).drain<void>(); // restarts the idle time
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(w.debugHasIsolate, isTrue, reason: '1000 ms since the first read, but only 500 since the last');
      expect(w.debugSpawns, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(w.debugHasIsolate, isFalse);
    } finally {
      await w.dispose();
      tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('idle: a read that arrives while the isolate is shutting down still works', () async {
    final tmp = Directory.systemTemp.createTempSync('ganj_voice_empty');
    final w = IsolateVoiceWorker(tmp.path, threads: 2, idle: const Duration(milliseconds: 100));
    try {
      await w.read(beyts(1)).handleError((_) {}).drain<void>();
      // Poll until the release starts, then read at once.
      while (w.debugHasIsolate && !w.debugReleasing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await expectLater(w.read(beyts(1)), emitsInOrder([emitsError(isA<VoiceEngineLoadError>()), emitsDone]));
      expect(w.debugSpawns, 2);
    } finally {
      await w.dispose();
      tmp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
    'idle with the real engine: a long read is never cut, then the engine is released and reloads',
    () async {
      final units = (jsonDecode(File('test/fixtures/voice/reading_units.json').readAsStringSync())['units'] as List)
          .cast<Map<String, dynamic>>();
      final reqs = [BeytRequest(0, List<String>.from(units[0]['lines'] as List))];
      // Far shorter than loading the engine and reading a beyt.
      final w = IsolateVoiceWorker(dir!, threads: 4, sherpaLibDir: libDir, idle: const Duration(seconds: 1));
      try {
        final first = await w.read(reqs, metre: units[0]['metre'] as String?).toList();
        expect(first.single.pcm, isNotEmpty);
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(w.debugHasIsolate, isFalse);
        final again = await w.read(reqs, metre: units[0]['metre'] as String?).toList();
        expect(again.single.pcm, isNotEmpty);
        expect(w.debugSpawns, 2);
      } finally {
        await w.dispose();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'isolate worker reads two beyts',
    () async {
      final units = (jsonDecode(File('test/fixtures/voice/reading_units.json').readAsStringSync())['units'] as List)
          .cast<Map<String, dynamic>>();
      final reqs = [for (var i = 0; i < 2; i++) BeytRequest(i, List<String>.from(units[i]['lines'] as List))];
      final w = IsolateVoiceWorker(dir!, threads: 4, sherpaLibDir: libDir);
      try {
        final sw = Stopwatch()..start();
        final got = await w.read(reqs, metre: units[0]['metre'] as String?).toList();
        // ignore: avoid_print
        print(
          'isolate worker: ${got.length} beyts in ${sw.elapsedMilliseconds} ms, '
          'pcm ${got.map((a) => a.pcm.length).toList()}',
        );
        expect(got.length, 2);
        expect(got.map((a) => a.index), [0, 1]);
        for (final a in got) {
          expect(a.sampleRate, 24000);
          expect(a.pcm, isNotEmpty);
        }
      } finally {
        await w.dispose();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
