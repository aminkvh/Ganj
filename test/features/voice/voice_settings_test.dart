import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/engine/voice_settings.dart';

void main() {
  test('reads the "after" section the voice side writes', () {
    final index = jsonDecode(File('test/fixtures/voice/cleanup/index.json').readAsStringSync()) as Map<String, dynamic>;
    final s = VoiceSettings.fromJson({'after': index['after']});
    expect(s.gain, 0.6571);
    expect(s.highpassHz, 70);
    expect(s.highpassOrder, 8);
    expect(s.deessDb, 6);
    expect(s.pauseCapS, 0.3);
  });

  test('sherpa values override the defaults; strings work; missing keys keep them', () {
    final s = VoiceSettings.fromJson({
      'sherpa': {
        'num_steps': 4,
        'guidance_scale': 1.5,
        'extra': {'min_words_in_sentence': '100000'},
      },
    });
    expect(s.numSteps, 4);
    expect(s.guidanceScale, 1.5);
    expect(s.minWordsInSentence, 100000);
    expect(s.silenceScale, 1.0);
    expect(s.speed, 1.004);
  });

  test("the voice side's final phone.json: every value read, descriptions ignored", () {
    final s = VoiceSettings.load('test/fixtures/voice/phone.json');
    expect(s.numSteps, 8);
    expect(s.guidanceScale, 2.0);
    expect(s.tShift, 0.5);
    expect(s.featScale, 0.1);
    expect(s.targetRms, 0.1);
    expect(s.speed, 1.004);
    expect(s.silenceScale, 1.0);
    expect(s.minWordsInSentence, 100000);
    expect(s.gain, 0.6482);
    expect(s.clamp, 1.0);
    expect(s.highpassHz, 70);
    expect(s.highpassOrder, 8);
    expect(s.deessDb, 6);
    expect(s.pauseCapS, 0.3);
  });

  test('no phone.json: the defaults', () {
    final s = VoiceSettings.load('does/not/exist.json');
    expect(s.numSteps, 8);
    expect(s.gain, 0.6482); // the final prompt's
  });
}
