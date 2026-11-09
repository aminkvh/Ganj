// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/deess.py (scipy's FFT in stft/istft).
import 'dart:math' as math;
import 'dart:typed_data';

/// In-place radix-2 complex FFT of a fixed power-of-two size, with precomputed twiddles.
class Fft {
  Fft(this.n)
    : assert(n > 1 && (n & (n - 1)) == 0),
      _cos = Float64List(n ~/ 2),
      _sin = Float64List(n ~/ 2),
      _rev = Int32List(n) {
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / n);
      _sin[i] = -math.sin(2 * math.pi * i / n);
    }
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if ((i >> b) & 1 == 1) r |= 1 << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  final int n;
  final Float64List _cos, _sin;
  final Int32List _rev;

  /// Forward transform (e^-i...) of [re] + i[im], in place.
  void forward(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1, step = n ~/ len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step], wi = _sin[k * step];
          final a = i + k, b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }

  /// Inverse transform including the 1/n factor, in place (conjugate trick).
  void inverse(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      im[i] = -im[i];
    }
    forward(re, im);
    final s = 1.0 / n;
    for (var i = 0; i < n; i++) {
      re[i] *= s;
      im[i] = -im[i] * s;
    }
  }
}
