import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/post/butterworth.dart';
import 'package:ganj/features/voice/post/clean.dart';
import 'package:ganj/features/voice/post/deess.dart';

const _dir = 'test/fixtures/voice/dsp';
const _tol = 1e-4;

Float32List _read(String name) {
  final bytes = File('$_dir/$name').readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getFloat32(i * 4, Endian.little);
  }
  return out;
}

double _maxErr(Float32List a, Float32List b) {
  expect(a.length, b.length);
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

void main() {
  final meta = jsonDecode(File('$_dir/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final sr = meta['sr'] as int;

  test('Butterworth SOS design matches scipy', () {
    final want = (meta['butter8_highpass70_sos'] as List)
        .map((r) => (r as List).map((v) => (v as num).toDouble()).toList())
        .toList();
    final got = butterHighpassSos(8, 70, sr.toDouble());
    expect(got.length, want.length);
    var worst = 0.0;
    for (var s = 0; s < want.length; s++) {
      for (var j = 0; j < 6; j++) {
        final d = (got[s][j] - want[s][j]).abs();
        if (d > worst) worst = d;
      }
    }
    // ignore: avoid_print
    print('sos max abs diff: $worst');
    expect(worst, lessThan(1e-12));
  });

  for (final c in meta['cases'] as List) {
    final name = (c as Map<String, dynamic>)['name'] as String;
    group(name, () {
      final input = _read('$name.in.f32');
      test('highpass', () {
        final e = _maxErr(highpass(input, sr: sr), _read('$name.highpass70.f32'));
        // ignore: avoid_print
        print('$name highpass max err: $e');
        expect(e, lessThan(_tol));
      });
      test('deess', () {
        final e = _maxErr(deess(input, sr: sr, depthDb: 6), _read('$name.deess6.f32'));
        // ignore: avoid_print
        print('$name deess max err: $e');
        expect(e, lessThan(_tol));
      });
      test('cleanVoice', () {
        final e = _maxErr(cleanVoice(input), _read('$name.highpass70_deess6.f32'));
        // ignore: avoid_print
        print('$name highpass+deess max err: $e');
        expect(e, lessThan(_tol));
      });
    });
  }

  test('deess with depth 0 is a copy; timing for 10 s', () {
    final input = _read('line0_A_as_heard.in.f32');
    expect(deess(input, depthDb: 0), input);
    final long = Float32List(240000);
    for (var i = 0; i < long.length; i++) {
      long[i] = input[i % input.length];
    }
    final sw = Stopwatch()..start();
    cleanVoice(long);
    // ignore: avoid_print
    print('cleanVoice 10 s: ${sw.elapsedMilliseconds} ms');
  });
}
