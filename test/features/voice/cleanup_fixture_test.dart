import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/post/clean.dart';
import 'package:ganj/features/voice/post/deess.dart';
import 'package:ganj/features/voice/post/pause_trim.dart';

/// The voice side's clean-up fixtures (app_cleanup_handoff, 2026-11-07): ten real lines read by sherpa, after each
/// step, plus two made-up trim edge cases. The edge cases live in test/fixtures/voice/cleanup; the ten lines (36 MB)
/// are read from GANJ_CLEANUP_FIXTURES when it is set.

/// A float32 (format 3) or PCM16 mono WAV.
Float32List readWav(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var p = 12;
  int? format, bits;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(p, p + 4));
    final size = d.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') {
      format = d.getUint16(p + 8, Endian.little);
      bits = d.getUint16(p + 22, Endian.little);
    } else if (id == 'data') {
      final n = size ~/ (bits! ~/ 8);
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = format == 3
            ? d.getFloat32(p + 8 + 4 * i, Endian.little)
            : d.getInt16(p + 8 + 2 * i, Endian.little) / 32768;
      }
      return out;
    }
    p += 8 + size + (size & 1);
  }
  throw FormatException('no data chunk in $path');
}

double maxErr(Float32List a, Float32List b) {
  expect(a.length, b.length);
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    final e = (a[i] - b[i]).abs();
    if (e > m) m = e;
  }
  return m;
}

int bitDiffs(Float32List a, Float32List b) {
  expect(a.length, b.length);
  final x = Uint32List.view(a.buffer, a.offsetInBytes, a.length);
  final y = Uint32List.view(b.buffer, b.offsetInBytes, b.length);
  var n = 0;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) n++;
  }
  return n;
}

List<List<int>> _pairs(Object? v) => [for (final p in (v as List)) List<int>.from(p as List)];

/// The trim on KEY.3_deess.wav against KEY.trim.json and KEY.4_trim.wav.
void checkTrim(String dir, String key) {
  final j = jsonDecode(File('$dir/$key.trim.json').readAsStringSync()) as Map<String, dynamic>;
  final y = readWav('$dir/$key.3_deess.wav');
  final plan = planTrim(y, 24000, nBreaks: j['n_breaks'] as int);
  final wantDb = List<double>.from((j['frame_db'] as List).map((e) => (e as num).toDouble()));
  expect(plan.frameDb.length, wantDb.length);
  var dbErr = 0.0;
  for (var i = 0; i < wantDb.length; i++) {
    dbErr = (plan.frameDb[i] - wantDb[i]).abs() > dbErr ? (plan.frameDb[i] - wantDb[i]).abs() : dbErr;
  }
  expect(dbErr, lessThan(1e-9), reason: '$key frame dB');
  expect(plan.threshold, closeTo((j['threshold_db'] as num).toDouble(), 1e-9), reason: '$key threshold');
  expect(
    [
      for (final s in plan.stops) [s.from, s.to],
    ],
    _pairs(j['stops_frames']),
    reason: '$key stops',
  );
  expect(plan.breaks.toList()..sort(), List<int>.from(j['breaks'] as List), reason: '$key breaks');
  expect(
    [
      for (final s in plan.cut) [s.from, s.to],
    ],
    _pairs(j['cut_frames']),
    reason: '$key cuts',
  );
  final out = trimPauses(y, 24000, nBreaks: j['n_breaks'] as int);
  final want = readWav('$dir/$key.4_trim.wav');
  expect(out.length, j['out_samples'], reason: '$key length');
  expect(bitDiffs(out, want), 0, reason: '$key trim must match bit for bit');
}

void main() {
  test('trim edge cases: exact cap kept, tie goes to the earlier stop', () {
    for (final key in ['edge_exact_cap', 'edge_tie_break']) {
      checkTrim('test/fixtures/voice/cleanup', key);
    }
  });

  final big = Platform.environment['GANJ_CLEANUP_FIXTURES'];
  test('ten sherpa lines, step by step', () {
    final index = jsonDecode(File('$big/index.json').readAsStringSync()) as Map<String, dynamic>;
    final after = index['after'] as Map<String, dynamic>;
    final gain = (after['gain'] as num).toDouble();
    var hpErr = 0.0, deErr = 0.0, endErr = 0.0;
    for (final line in (index['lines'] as List).cast<Map<String, dynamic>>()) {
      final key = line['key'] as String;
      if (key.startsWith('edge_')) continue;
      final raw = readWav('$big/$key.0_sherpa.wav');
      // 1-2: gain in float32, clamp: bit for bit.
      final g = Float32List.fromList([gain])[0];
      final gc = Float32List(raw.length);
      for (var i = 0; i < raw.length; i++) {
        gc[i] = (raw[i] * g).clamp(-1.0, 1.0);
      }
      expect(bitDiffs(gc, readWav('$big/$key.1_gain_clamp.wav')), 0, reason: '$key gain+clamp');
      // 3: high-pass, 4: de-ess, each from the fixture's previous step: to float rounding.
      final hp = highpass(readWav('$big/$key.1_gain_clamp.wav'));
      final e3 = maxErr(hp, readWav('$big/$key.2_highpass.wav'));
      final de = deess(readWav('$big/$key.2_highpass.wav'), depthDb: 6);
      final e4 = maxErr(de, readWav('$big/$key.3_deess.wav'));
      hpErr = e3 > hpErr ? e3 : hpErr;
      deErr = e4 > deErr ? e4 : deErr;
      // 5: the trim from the fixture's de-essed audio: bit for bit, with every working value.
      checkTrim(big!, key);
      // The whole chain from sherpa's output.
      final all = finishLine(raw, 24000, gain: gain, nBreaks: line['n_breaks'] as int);
      final want = readWav('$big/$key.4_trim.wav');
      expect(all.length, want.length, reason: '$key chain length');
      final e = maxErr(all, want);
      endErr = e > endErr ? e : endErr;
    }
    // ignore: avoid_print
    print('max error: high-pass $hpErr, de-ess $deErr, whole chain $endErr');
    expect(hpErr, lessThan(1e-6));
    expect(deErr, lessThan(1e-6));
    expect(endErr, lessThan(1e-5));
  }, skip: big == null ? 'set GANJ_CLEANUP_FIXTURES to the handoff fixture folder' : null);
}
