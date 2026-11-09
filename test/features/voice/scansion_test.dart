// Golden tests for the aruz scansion: every case recorded from the Python reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/reading/scansion.dart';

void main() {
  test('scans() equals the reference for every recorded case', () {
    final cases =
        ((jsonDecode(File('test/fixtures/voice/scansion.json').readAsStringSync()) as Map<String, dynamic>)['cases']
                as List)
            .cast<Map<String, dynamic>>();
    final bad = <String>[];
    for (final c in cases) {
      final got = scans(c['phonemes'] as String, c['metre'] as String);
      if (got != c['scans']) bad.add('${c['phonemes']} | ${c['metre']}: want ${c['scans']}, got $got');
    }
    if (bad.isNotEmpty) {
      // ignore: avoid_print
      print('${bad.length} of ${cases.length} scansion cases differ; first mismatches:\n${bad.take(10).join('\n')}');
    }
    expect(cases.length, greaterThan(7000));
    expect(bad.length, 0);
  });
}
