// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/dehum.py and deess.py.
import 'dart:typed_data';

import 'butterworth.dart';
import 'deess.dart';
import 'filtfilt.dart';
import 'pause_trim.dart';

/// Zero-phase Butterworth high-pass (run forward and back, so the slope is doubled and no phase
/// shift). A humming prompt's hum comes back from the vocoder as lines near 48 and 56 Hz; the
/// voices' pitch stays above about 80 Hz.
Float32List highpass(Float32List y, {int sr = 24000, double cutoffHz = 70, int order = 8}) {
  final x = Float64List(y.length);
  for (var i = 0; i < y.length; i++) {
    x[i] = y[i];
  }
  final out = sosfiltfilt(butterHighpassSos(order, cutoffHz, sr.toDouble()), x);
  return Float32List.fromList(out);
}

/// The post-synthesis clean-up: de-ess(high-pass(y)).
Float32List cleanVoice(Float32List y, {int sr = 24000, double highpassHz = 70, double deessDb = 6}) => deess(
  highpass(y, sr: sr, cutoffHz: highpassHz),
  sr: sr,
  depthDb: deessDb,
);

/// The whole clean-up after sherpa (voice/phonepost.py): y * gain in float32, clamp to [-1, 1], high-pass, de-ess,
/// pause trim keeping [nBreaks] hemistich breaks, clamp.
Float32List finishLine(
  Float32List raw,
  int sr, {
  required double gain,
  required int nBreaks,
  double highpassHz = 70,
  double deessDb = 6,
  double pauseCapS = 0.30,
}) {
  final g = Float32List.fromList([gain])[0];
  final y = Float32List(raw.length);
  for (var i = 0; i < raw.length; i++) {
    y[i] = (raw[i] * g).clamp(-1.0, 1.0);
  }
  return trimPauses(
    cleanVoice(y, sr: sr, highpassHz: highpassHz, deessDb: deessDb),
    sr,
    nBreaks: nBreaks,
    capS: pauseCapS,
  );
}
