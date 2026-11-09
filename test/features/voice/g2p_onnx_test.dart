import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/engine/g2p_onnx.dart';
import 'package:ganj/features/voice/engine/ort.dart';

/// Needs the exported G2P (GANJ_G2P_ONNX: a folder with g2p_encoder.onnx and g2p_decoder.onnx) and an onnxruntime
/// library (GANJ_ORT_LIB); skipped without them. GANJ_G2P_CALLS limits how many recorded calls are checked.
void main() {
  final dir = Platform.environment['GANJ_G2P_ONNX'];
  final lib = Platform.environment['GANJ_ORT_LIB'];
  final skip = dir == null || lib == null ? 'set GANJ_G2P_ONNX and GANJ_ORT_LIB' : null;

  test(
    'ONNX G2P reproduces every recorded model call',
    () {
      final ort = Ort.open(lib);
      final model = OnnxG2pModel(
        ort,
        File('$dir/g2p_encoder.onnx').readAsBytesSync(),
        File('$dir/g2p_decoder.onnx').readAsBytesSync(),
        threads: 4,
      );
      final calls = <Map<String, dynamic>>[
        for (final f in ['reading_units.json', 'reading_units_nometre.json'])
          for (final u in (jsonDecode(File('test/fixtures/voice/$f').readAsStringSync())['units'] as List))
            for (final c in (u['calls'] as List)) c as Map<String, dynamic>,
      ];
      final limit = int.tryParse(Platform.environment['GANJ_G2P_CALLS'] ?? '') ?? 60;
      final bad = <String>[];
      final sw = Stopwatch()..start();
      final picked = calls.take(limit).toList();
      for (final c in picked) {
        final input = c['input'] as String;
        final want = List<String>.from(c['out'] as List);
        final got = c['call'] == 'nbest' ? model.nbest(input, c['n'] as int) : [model.top1(input)];
        if (jsonEncode(got) != jsonEncode(want)) bad.add('$input\n  want ${want.take(3)}\n  got  ${got.take(3)}');
      }
      // ignore: avoid_print
      print(
        '${picked.length - bad.length}/${picked.length} identical, '
        '${sw.elapsedMilliseconds ~/ picked.length} ms per call',
      );
      expect(bad, isEmpty, reason: bad.take(3).join('\n'));
      model.dispose();
      ort.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
