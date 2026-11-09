import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/engine/voice_engine.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// End to end on this computer: poem text -> phonemes -> sherpa-onnx -> clean-up -> wav. Needs a voice folder
/// (GANJ_VOICE_DIR) and the folder holding sherpa-onnx-c-api and onnxruntime (GANJ_SHERPA_LIB_DIR); skipped
/// without them. Writes the renders to GANJ_VOICE_OUT when set.
void main() {
  final dir = Platform.environment['GANJ_VOICE_DIR'];
  final libDir = Platform.environment['GANJ_SHERPA_LIB_DIR'];
  final out = Platform.environment['GANJ_VOICE_OUT'];
  final skip = dir == null || libDir == null ? 'set GANJ_VOICE_DIR and GANJ_SHERPA_LIB_DIR' : null;

  test(
    'reads beyts from the fixtures with the same phonemes as the Python front-end',
    () {
      final ortPath = '$libDir${Platform.pathSeparator}${Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'}';
      // Load sherpa's onnxruntime by full path first: Windows 11 has an older onnxruntime.dll in System32 that the
      // loader would otherwise pick for flutter_tester (the app finds its own next to the exe).
      DynamicLibrary.open(ortPath);
      sherpa.initBindings(libDir);
      final files = VoiceFiles(dir!);
      expect(files.complete, isTrue, reason: 'missing files in $dir');
      final engine = VoiceEngine.load(files, onnxruntimePath: ortPath);
      final units = (jsonDecode(File('test/fixtures/voice/reading_units.json').readAsStringSync())['units'] as List)
          .cast<Map<String, dynamic>>();
      final steps = int.tryParse(Platform.environment['GANJ_VOICE_STEPS'] ?? '') ?? 8;
      for (final key in [
        '100389-5',
        units.firstWhere((u) => (u['lines'] as List).join().contains('ژ'), orElse: () => units[1])['key'],
      ]) {
        final u = units.firstWhere((x) => x['key'] == key);
        final lines = List<String>.from(u['lines'] as List);
        final sw = Stopwatch()..start();
        final line = engine.read(lines, metre: u['metre'] as String?, steps: steps);
        final secs = line.duration.inMilliseconds / 1000;
        // ignore: avoid_print
        print(
          '$key: ${lines.join(' / ')}\n  ${secs.toStringAsFixed(1)} s of audio in ${sw.elapsedMilliseconds} ms '
          '(${(secs * 1000 / sw.elapsedMilliseconds).toStringAsFixed(2)}x)',
        );
        expect(line.target, u['target'], reason: 'phonemes differ from the Python front-end');
        expect(secs, greaterThan(2));
        if (out != null) {
          sherpa.writeWave(filename: '$out/$key.wav', samples: line.samples, sampleRate: line.sampleRate);
        }
      }
      engine.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
