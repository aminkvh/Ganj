import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
