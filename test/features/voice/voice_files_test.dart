import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';
import 'package:ganj/features/voice/engine/voice_engine.dart';

void main() {
  late Directory d;
  setUp(() => d = Directory.systemTemp.createTempSync('voicefiles'));
  tearDown(() => d.deleteSync(recursive: true));

  test('full encoder and decoder when there are no int8 files', () {
    final f = VoiceFiles(d.path);
    expect(f.encoder, endsWith('/text_encoder.onnx'));
    expect(f.decoder, endsWith('/fm_decoder.onnx'));
  });

  test('the int8 pair wins when present', () {
    File('${d.path}/text_encoder_int8.onnx').writeAsStringSync('x');
    File('${d.path}/fm_decoder_int8.onnx').writeAsStringSync('x');
    final f = VoiceFiles(d.path);
    expect(f.encoder, endsWith('/text_encoder_int8.onnx'));
    expect(f.decoder, endsWith('/fm_decoder_int8.onnx'));
  });

  test('the voice comes from the v2 folders', () {
    expect(kVoiceSources, {
      'hf': 'https://huggingface.co/aminkvh/Ganj_voice/resolve/main/ganj-zip-distill-1.2.0/',
      'github': 'https://github.com/aminkvh/Ganj_voice/releases/download/phone-1.2.0/',
    });
  });

  test('compareVersions is numeric per dot part', () {
    expect(compareVersions('1.2.0', '1.1.0'), greaterThan(0));
    expect(compareVersions('1.1.0', '1.2.0'), lessThan(0));
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0), reason: 'not a string compare');
    expect(compareVersions('1.2.0', '1.2.0'), 0);
    expect(compareVersions('1.2', '1.2.0'), 0, reason: 'a missing part is 0');
    expect(compareVersions('2', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.1.0'), lessThan(0));
    expect(compareVersions('v1', '1.0.0'), lessThan(0), reason: 'a part that is not a number counts as 0');
  });
}
