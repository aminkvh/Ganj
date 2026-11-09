// Golden tests for the Ganj voice reading front-end: replays the model calls recorded from the Python reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/reading/glue.dart';
import 'package:ganj/features/voice/reading/pauses.dart';
import 'package:ganj/features/voice/reading/reading.dart';

/// Replays a unit's recorded model calls in order; any other call fails loudly.
class ReplayModel implements G2pModel {
  ReplayModel(this.calls);
  final List<dynamic> calls;
  int _next = 0;

  Map<String, dynamic> _take(String kind, String input, [int? n]) {
    if (_next >= calls.length) {
      throw StateError('unexpected $kind call #$_next (only ${calls.length} recorded): $input');
    }
    final c = calls[_next++] as Map<String, dynamic>;
    if (c['call'] != kind || c['input'] != input || (n != null && c['n'] != n)) {
      throw StateError(
        'call #${_next - 1}: expected ${c['call']}(${c['input']}, n=${c['n']}), got $kind($input, n=$n)',
      );
    }
    return c;
  }

  @override
  String top1(String text) {
    final out = _take('top1', text)['out'];
    return out is List ? out.first as String : out as String;
  }

  @override
  List<String> nbest(String text, int n) => ((_take('nbest', text, n)['out']) as List).cast<String>();

  bool get exhausted => _next == calls.length;
}

List<Map<String, dynamic>> _load(String name) {
  final f = File('test/fixtures/voice/$name');
  if (!f.existsSync()) return [];
  return ((jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['units'] as List).cast<Map<String, dynamic>>();
}

String _esc(String s) => s.runes
    .map((r) => (r >= 0xE000 && r <= 0xF8FF) ? '<U+${r.toRadixString(16).toUpperCase()}>' : String.fromCharCode(r))
    .join();

void _runUnits(String file) {
  final units = _load(file);
  if (units.isEmpty) {
    test('$file (fixture missing, skipped)', () {}, skip: 'fixture not present');
    return;
  }
  test('$file: label, reading and target equal for all ${units.length} units', () {
    final bad = <String>[];
    for (final u in units) {
      final lines = (u['lines'] as List).cast<String>();
      final kind = u['kind'] as String;
      final metre = u['metre'] as String?;
      final model = ReplayModel(u['calls'] as List);
      final g2p = G2P(model);
      final diffs = <String>[];
      try {
        final label = g2p.phonemizeUnit(lines, kind, metre);
        final reading = readingLabel(label, lines, prose: kind == 'prose', pauses: true, va: false);
        final target = leadPause(glueVav(reading));
        if (u['error'] != null) diffs.add('expected error ${u['error']} but got a label');
        if (label != u['label']) diffs.add('label\n  want ${_esc(u['label'] as String)}\n  got  ${_esc(label)}');
        if (reading != u['reading']) {
          diffs.add('reading\n  want ${_esc(u['reading'] as String)}\n  got  ${_esc(reading)}');
        }
        if (target != u['target']) diffs.add('target\n  want ${_esc(u['target'] as String)}\n  got  ${_esc(target)}');
        if (target != readingTarget(G2P(ReplayModel(u['calls'] as List)), lines, kind: kind, metre: metre)) {
          diffs.add('readingTarget differs from the step-by-step pipeline');
        }
      } on PhonemizeError catch (e) {
        if (u['error'] == null) {
          diffs.add('unexpected ${e.message}');
        } else if (!(u['error'] as String).contains(e.message)) {
          diffs.add('error\n  want ${u['error']}\n  got  ${e.message}');
        }
      } on StateError catch (e) {
        diffs.add(e.message);
      }
      if (diffs.isEmpty && !model.exhausted) diffs.add('recorded calls left unused');
      if (diffs.isNotEmpty) bad.add('${u['key']} ${jsonEncode(lines)}\n${diffs.join('\n')}');
    }
    if (bad.isNotEmpty) {
      // ignore: avoid_print
      print('${bad.length} of ${units.length} units differ in $file; first mismatches:\n${bad.take(5).join('\n\n')}');
    }
    expect(bad.length, 0);
  });
}

void main() {
  group('reading front-end', () {
    _runUnits('reading_units.json');
    _runUnits('reading_units_nometre.json');
  });
}
