// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/dehum.py (scipy.signal.butter).
import 'dart:math' as math;
import 'dart:typed_data';

/// Butterworth high-pass as second-order sections, rows [b0 b1 b2 1 a1 a2], the way
/// scipy.signal.butter(order, cutoffHz, btype="highpass", fs=sr, output="sos") returns them:
/// analog prototype, low-pass to high-pass, bilinear transform with pre-warping, then
/// scipy's "nearest" pairing (poles closest to the unit circle go in the last section).
/// Even orders only.
List<Float64List> butterHighpassSos(int order, double cutoffHz, double sr) {
  if (order < 2 || order.isOdd) throw ArgumentError('even order >= 2 only');
  const fs2 = 4.0; // scipy designs at fs = 2, so the bilinear constant is 2 * fs
  final warped = fs2 * math.tan(math.pi * cutoffHz / sr);

  // Analog poles of the prototype (unit circle, left half-plane), moved by s -> warped / s;
  // the prototype gain is 1 (prod(-p) = 1), so the gain is the bilinear one,
  // prod(fs2 - z) / prod(fs2 - p) with all zeros at s = 0.
  final poles = <(double, double)>[]; // digital poles with positive imaginary part
  var prodDenRe = 1.0, prodDenIm = 0.0;
  for (var m = -order + 1; m < order; m += 2) {
    final ang = math.pi * m / (2 * order);
    final pr = -math.cos(ang), pi = -math.sin(ang);
    final d = pr * pr + pi * pi;
    final hr = warped * pr / d, hi = -warped * pi / d; // high-pass analog pole
    final cr = fs2 - hr, ci = -hi; // fs2 - p
    final ur = prodDenRe * cr - prodDenIm * ci;
    prodDenIm = prodDenRe * ci + prodDenIm * cr;
    prodDenRe = ur;
    if (hi > 0) {
      final ar = fs2 + hr, ai = hi; // (fs2 + p) / (fs2 - p)
      final q = cr * cr + ci * ci;
      poles.add(((ar * cr + ai * ci) / q, (ai * cr - ar * ci) / q));
    }
  }
  final gain = math.pow(fs2, order) / prodDenRe;

  poles.sort((a, b) {
    double dist((double, double) p) => (1 - math.sqrt(p.$1 * p.$1 + p.$2 * p.$2)).abs();
    return dist(a).compareTo(dist(b));
  });
  final n = poles.length;
  final sos = List<Float64List>.generate(n, (_) => Float64List(6));
  for (var i = 0; i < n; i++) {
    final p = poles[i];
    sos[n - 1 - i].setAll(0, [1, -2, 1, 1, -2 * p.$1, p.$1 * p.$1 + p.$2 * p.$2]);
  }
  for (var j = 0; j < 3; j++) {
    sos[0][j] *= gain;
  }
  return sos;
}
