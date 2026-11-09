// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/deess.py.
import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Sibilant de-essing for model outputs: the voices' س and ش whistle, 5-11 dB louder than the
/// human recordings in 5-9 kHz. In frames whose energy is mostly above [_hissFromHz] (a
/// fricative), 4.5 kHz up to a top that follows the frame's spectral centre (7 kHz for a ش-like
/// frame, 9.5 kHz for a س-like one, raised-cosine edges) is turned down by [depthDb] (times
/// [_shinDepth] for ش); vowels, voiced consonants and everything below 4.5 kHz are left as they
/// are. Attenuation only.
Float32List deess(Float32List y, {int sr = 24000, required double depthDb}) {
  if (depthDb <= 0) return Float32List.fromList(y);
  final n = y.length;
  final bins = _nfft ~/ 2 + 1;

  // stft: boundary='zeros' (nfft/2 each side), padded to whole segments, hann, scaling 1/sum(win).
  var len = n + _nfft;
  len += (-(len - _nfft) % _hop) % _nfft;
  final padded = Float64List(len);
  for (var i = 0; i < n; i++) {
    padded[_nfft ~/ 2 + i] = y[i];
  }
  final frames = (len - _nfft) ~/ _hop + 1;
  final win = Float64List(_nfft);
  var winSum = 0.0;
  for (var i = 0; i < _nfft; i++) {
    win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _nfft);
    winSum += win[i];
  }
  final fft = Fft(_nfft);
  final zr = Float64List(frames * bins), zi = Float64List(frames * bins); // frame-major
  final re = Float64List(_nfft), im = Float64List(_nfft);
  for (var t = 0; t < frames; t++) {
    for (var i = 0; i < _nfft; i++) {
      re[i] = padded[t * _hop + i] * win[i];
      im[i] = 0;
    }
    fft.forward(re, im);
    for (var k = 0; k < bins; k++) {
      zr[t * bins + k] = re[k] / winSum;
      zi[t * bins + k] = im[k] / winSum;
    }
  }

  final freq = Float64List(bins);
  for (var k = 0; k < bins; k++) {
    freq[k] = k * sr / _nfft;
  }
  final rise = Float64List(bins);
  for (var k = 0; k < bins; k++) {
    rise[k] = _ramp((freq[k] - _riseHz.$1) / (_riseHz.$2 - _riseHz.$1));
  }

  // Per-frame centre, hiss share.
  final centre = Float64List(frames), share = Float64List(frames);
  for (var t = 0; t < frames; t++) {
    var num = 0.0, den = 0.0, hi = 0.0, all = 0.0;
    for (var k = 0; k < bins; k++) {
      final p = zr[t * bins + k] * zr[t * bins + k] + zi[t * bins + k] * zi[t * bins + k];
      if (freq[k] >= 2000 && freq[k] <= 11000) {
        num += freq[k] * p;
        den += p;
      }
      if (freq[k] > _hissFromHz) hi += p;
      all += p;
    }
    centre[t] = num / (den + 1e-20);
    share[t] = hi / (all + 1e-20);
  }
  final m = Float64List(frames);
  for (var t = 0; t < frames; t++) {
    m[t] = ((share[t] - _hissShare.$1) / (_hissShare.$2 - _hissShare.$1)).clamp(0.0, 1.0);
  }
  // np.convolve(m, ones(3)/3, mode="same"): zero-padded moving average.
  final hiss = Float64List(frames);
  for (var t = 0; t < frames; t++) {
    var s = m[t];
    if (t > 0) s += m[t - 1];
    if (t < frames - 1) s += m[t + 1];
    hiss[t] = s / _smoothFrames;
  }

  // Apply the cut, then istft (weighted overlap-add over the summed squared window).
  final out = Float64List(len), norm = Float64List(len);
  for (var t = 0; t < frames; t++) {
    final top = _interp(centre[t], _centreHz, _topHz);
    final depth = _interp(centre[t], _centreHz, (_shinDepth, 1.0));
    for (var k = 0; k < bins; k++) {
      final w = rise[k] * (1.0 - _ramp((freq[k] - top) / _fadeHz)) * depth * hiss[t];
      final g = math.pow(10, -depthDb * w / 20).toDouble();
      re[k] = zr[t * bins + k] * g;
      im[k] = zi[t * bins + k] * g;
    }
    for (var k = 1; k < _nfft ~/ 2; k++) {
      re[_nfft - k] = re[k];
      im[_nfft - k] = -im[k];
    }
    im[0] = 0;
    im[_nfft ~/ 2] = 0;
    fft.inverse(re, im);
    for (var i = 0; i < _nfft; i++) {
      out[t * _hop + i] += re[i] * winSum * win[i];
      norm[t * _hop + i] += win[i] * win[i];
    }
  }
  final z = Float32List(n);
  for (var i = 0; i < n; i++) {
    final j = _nfft ~/ 2 + i;
    z[i] = out[j] / (norm[j] > 1e-10 ? norm[j] : 1.0);
  }
  return z;
}

const _nfft = 512, _hop = 128; // 21 ms windows every 5.3 ms at 24 kHz
const _riseHz = (4500.0, 5500.0); // the cut fades in between these
const _centreHz = (5000.0, 6200.0); // a frame's 2-11 kHz centre
const _topHz = (7000.0, 9500.0); // -> where the full cut ends
const _fadeHz = 1000.0; // and fades out over this
const _shinDepth = 0.6; // share of depthDb a ش-like frame gets (س-like: all of it)
const _hissFromHz = 2500.0;
const _hissShare = (0.4, 0.6); // share of energy above _hissFromHz: no cut below, full cut above
const _smoothFrames = 3;

/// 0 -> 1 raised cosine over x in [0, 1].
double _ramp(double x) => 0.5 - 0.5 * math.cos(math.pi * x.clamp(0.0, 1.0));

/// np.interp with two points, clamped at the ends.
double _interp(double x, (double, double) xs, (double, double) ys) {
  if (x <= xs.$1) return ys.$1;
  if (x >= xs.$2) return ys.$2;
  return ys.$1 + (ys.$2 - ys.$1) * (x - xs.$1) / (xs.$2 - xs.$1);
}
