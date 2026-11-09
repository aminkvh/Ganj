// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/dehum.py (scipy.signal.sosfiltfilt).
import 'dart:typed_data';

/// Zero-phase filtering with second-order sections (run forward and back, so the slope is doubled
/// and there is no phase shift). Follows scipy.signal.sosfiltfilt: odd-extended edges
/// (padlen = 3 * (2 * sections + 1 - zero-tap count)) and steady-state initial conditions
/// scaled by the first sample of each pass.
Float64List sosfiltfilt(List<Float64List> sos, Float64List x) {
  final ns = sos.length;
  var zeroB2 = 0, zeroA2 = 0;
  for (final s in sos) {
    if (s[2] == 0) zeroB2++;
    if (s[5] == 0) zeroA2++;
  }
  final padlen = 3 * (2 * ns + 1 - (zeroB2 < zeroA2 ? zeroB2 : zeroA2));
  if (x.length <= padlen) throw ArgumentError('signal too short for sosfiltfilt');
  final n = x.length;
  final ext = Float64List(n + 2 * padlen);
  for (var i = 0; i < padlen; i++) {
    ext[i] = 2 * x[0] - x[padlen - i];
    ext[padlen + n + i] = 2 * x[n - 1] - x[n - 2 - i];
  }
  ext.setRange(padlen, padlen + n, x);

  final zi = _sosfiltZi(sos);
  _sosfilt(sos, ext, zi, ext[0]);
  _reverse(ext);
  _sosfilt(sos, ext, zi, ext[0]);
  _reverse(ext);
  return Float64List.sublistView(ext, padlen, padlen + n);
}

void _reverse(Float64List a) {
  for (var i = 0, j = a.length - 1; i < j; i++, j--) {
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
}

/// Steady-state state for a unit step, per section (scipy.signal.sosfilt_zi).
Float64List _sosfiltZi(List<Float64List> sos) {
  final zi = Float64List(sos.length * 2);
  var scale = 1.0;
  for (var s = 0; s < sos.length; s++) {
    final r = sos[s];
    final b0 = r[0], b1 = r[1], b2 = r[2], a1 = r[4], a2 = r[5];
    // (I - companion(a)^T) z = b[1:] - a[1:] * b0
    final m00 = 1 + a1, m01 = -1.0, m10 = a2, m11 = 1.0;
    final v0 = b1 - a1 * b0, v1 = b2 - a2 * b0;
    final det = m00 * m11 - m01 * m10;
    zi[2 * s] = scale * (v0 * m11 - m01 * v1) / det;
    zi[2 * s + 1] = scale * (m00 * v1 - m10 * v0) / det;
    scale *= (b0 + b1 + b2) / (1 + a1 + a2);
  }
  return zi;
}

/// In-place cascade of biquads (transposed direct form II), state = zi * x0.
void _sosfilt(List<Float64List> sos, Float64List y, Float64List zi, double x0) {
  for (var s = 0; s < sos.length; s++) {
    final r = sos[s];
    final b0 = r[0], b1 = r[1], b2 = r[2], a1 = r[4], a2 = r[5];
    var z0 = zi[2 * s] * x0, z1 = zi[2 * s + 1] * x0;
    for (var i = 0; i < y.length; i++) {
      final xi = y[i];
      final o = b0 * xi + z0;
      z0 = b1 * xi - a1 * o + z1;
      z1 = b2 * xi - a2 * o;
      y[i] = o;
    }
  }
}
