import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/post/pause_trim.dart';

/// Sound (a 200 Hz tone) and silence in seconds, alternating, starting with sound.
Float32List _clip(List<double> parts, {int sr = 24000}) {
  final out = <double>[];
  for (var i = 0; i < parts.length; i++) {
    final n = (parts[i] * sr).round();
    for (var k = 0; k < n; k++) {
      out.add(i.isEven ? 0.3 * math.sin(2 * math.pi * 200 * k / sr) : 1e-5 * math.sin(k.toDouble()));
    }
  }
  return Float32List.fromList(out);
}

void main() {
  test('finds the stops between the first and last sound', () {
    final y = _clip([0.2, 0.5, 0.8, 0.6, 0.7, 0.4]);
    final stops = planTrim(y, 24000, nBreaks: 0).stops;
    expect(stops.length, 2, reason: 'the 0.5 and 0.6 s gaps; the trailing 0.4 s silence is not a stop');
    expect(stops[0].frames * 0.01, closeTo(0.5, 0.02));
    expect(stops[1].frames * 0.01, closeTo(0.6, 0.02));
  });

  test('cuts inner stops to 0.30 s and keeps the hemistich break', () {
    // sound, stop 0.6 (cut), sound, break 1.0 (kept), sound, stop 0.2 (short, kept), sound
    final y = _clip([1.0, 0.6, 1.0, 1.0, 1.0, 0.2, 1.0]);
    final out = trimPauses(y, 24000, nBreaks: 1);
    final removed = (y.length - out.length) / 24000;
    expect(removed, closeTo(0.30 + 0.01, 0.02), reason: 'only the 0.6 s stop loses 0.3 s (plus the crossfade)');
    final again = planTrim(out, 24000, nBreaks: 0).stops.map((s) => s.frames * 0.01).toList()..sort();
    expect(again.last, closeTo(1.0, 0.02));
    expect(again.first, closeTo(0.2, 0.02));
  });

  test('one hemistich: every long stop is cut', () {
    final y = _clip([1.0, 0.8, 1.0, 0.9, 1.0]);
    final out = trimPauses(y, 24000, nBreaks: 0);
    for (final s in planTrim(out, 24000, nBreaks: 0).stops) {
      expect(s.frames * 0.01, lessThan(0.32));
    }
  });

  test('a stop of exactly the cap is kept; of equal stops the earlier is the break', () {
    final exact = _clip([1.0, 0.30, 1.0]);
    expect(trimPauses(exact, 24000, nBreaks: 0).length, exact.length);
    final tie = _clip([1.0, 0.8, 1.0, 0.8, 1.0]);
    final out = trimPauses(tie, 24000, nBreaks: 1);
    final stops = planTrim(out, 24000, nBreaks: 0).stops;
    expect(stops.first.frames * 0.01, closeTo(0.8, 0.02), reason: 'the earlier stop is the break');
    expect(stops.last.frames * 0.01, lessThan(0.32));
  });

  group('hemistichOnsetsMs', () {
    test('finds where the second hemistich starts in the trimmed audio', () {
      // sound 1.0, stop 0.6 (cut to 0.3), sound 1.0, break 1.0 (kept), sound 1.0, stop 0.2, sound 1.0
      final out = trimPauses(_clip([1.0, 0.6, 1.0, 1.0, 1.0, 0.2, 1.0]), 24000, nBreaks: 1);
      final on = hemistichOnsetsMs(out, 24000, hemistichs: 2);
      expect(on, hasLength(1));
      expect(on.single, closeTo(1000 + 300 + 1000 + 1000, 20));
    });

    test('three lines: two onsets in order', () {
      final out = trimPauses(_clip([1.0, 0.9, 1.0, 0.5, 1.0, 0.8, 1.0]), 24000, nBreaks: 2);
      final on = hemistichOnsetsMs(out, 24000, hemistichs: 3);
      expect(on, hasLength(2));
      expect(on[0], closeTo(1900, 20));
      expect(on[1], closeTo(1900 + 1000 + 300 + 1000 + 800, 20));
    });

    test('none for one hemistich, or when the breaks cannot all be found', () {
      final out = trimPauses(_clip([1.0, 0.8, 1.0]), 24000, nBreaks: 1);
      expect(hemistichOnsetsMs(out, 24000, hemistichs: 1), isEmpty);
      expect(hemistichOnsetsMs(out, 24000, hemistichs: 3), isEmpty, reason: 'one stop for two breaks');
      expect(hemistichOnsetsMs(_clip([2.0]), 24000, hemistichs: 2), isEmpty, reason: 'no stop at all');
    });
  });

  test('percentile matches numpy linear interpolation', () {
    expect(percentile([1, 2, 3, 4], 50), 2.5);
    expect(percentile([10, 0, 5], 95), closeTo(9.5, 1e-12));
  });
}
