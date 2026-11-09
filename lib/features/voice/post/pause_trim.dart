// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author): voice/levelstops.py, eval/prosody.py
// (silent_frames) and voice/pausetrim.py (shorten_runs), as handed over with fixtures on 2026-11-07.

import 'dart:math' as math;
import 'dart:typed_data';

const double _frameS = 0.01;

/// A silent run inside the line: its first frame and the frame after its last (10 ms frames).
typedef Stop = ({int from, int to});

extension StopLength on Stop {
  int get frames => to - from;
}

/// What the trim found and did, for tests and logs.
class TrimPlan {
  const TrimPlan(this.frameDb, this.threshold, this.stops, this.breaks, this.cut);

  final Float64List frameDb;
  final double threshold;
  final List<Stop> stops;

  /// Indices into [stops]: the hemistich breaks, which keep their length.
  final Set<int> breaks;

  /// The stops cut to the cap (a stop at most cap + 10 ms is listed but the audio is left as it is).
  final List<Stop> cut;
}

/// Per frame (round(0.01 * sr) samples, not overlapping, a partial last frame dropped): 10 log10(mean(y²) + 1e-12),
/// in float64.
Float64List frameDb(Float32List y, int sr) {
  final n = (_frameS * sr).round();
  final k = y.length ~/ n;
  final out = Float64List(k);
  for (var f = 0; f < k; f++) {
    var s = 0.0;
    for (var i = f * n; i < (f + 1) * n; i++) {
      final v = y[i].toDouble();
      s += v * v;
    }
    out[f] = 10 * math.log(s / n + 1e-12) / math.ln10;
  }
  return out;
}

/// numpy.percentile with its default linear interpolation.
double percentile(List<double> x, double q) {
  final s = [...x]..sort();
  if (s.isEmpty) return double.nan;
  final pos = (s.length - 1) * (q / 100);
  final lo = pos.floor();
  final hi = math.min(lo + 1, s.length - 1);
  final g = pos - lo;
  // numpy's _lerp: a + (b - a) * t, switched to b - (b - a) * (1 - t) for t >= 0.5.
  final d = s[hi] - s[lo];
  return g >= 0.5 ? s[hi] - d * (1 - g) : s[lo] + d * g;
}

/// The trim's plan for [y]: frames silent strictly below max(p95 - 35 dB, p10 + 6 dB); stops are the silent runs
/// between the first and last sound; the [nBreaks] longest (in whole frames, the earlier of equals) are the breaks;
/// every other stop strictly longer than the cap in frames is cut.
TrimPlan planTrim(Float32List y, int sr, {required int nBreaks, double capS = 0.30}) {
  final db = frameDb(y, sr);
  if (db.isEmpty) return TrimPlan(db, double.nan, const [], const {}, const []);
  final threshold = math.max(percentile(db, 95) - 35, percentile(db, 10) + 6);
  final silent = [for (final d in db) d < threshold];
  final first = silent.indexOf(false);
  final stops = <Stop>[];
  if (first >= 0) {
    final last = silent.lastIndexOf(false);
    int? start;
    for (var k = first; k <= last; k++) {
      if (silent[k] && start == null) {
        start = k;
      } else if (!silent[k] && start != null) {
        stops.add((from: start, to: k));
        start = null;
      }
    }
  }
  final byLength = [for (var i = 0; i < stops.length; i++) i]
    ..sort((a, b) {
      final c = stops[b].frames.compareTo(stops[a].frames);
      return c != 0 ? c : a.compareTo(b); // Python's sorted(reverse=True) is stable: ties keep their order
    });
  final breaks = byLength.take(math.max(nBreaks, 0)).toSet();
  final capFrames = (capS / _frameS).round();
  final cut = [
    for (var i = 0; i < stops.length; i++)
      if (!breaks.contains(i) && stops[i].frames > capFrames) stops[i],
  ];
  return TrimPlan(db, threshold, stops, breaks, cut);
}

/// [y] with every stop but the hemistich breaks cut to [capS], then clamped to [-1, 1].
Float32List trimPauses(Float32List y, int sr, {required int nBreaks, double capS = 0.30}) {
  final plan = planTrim(y, sr, nBreaks: nBreaks, capS: capS);
  final runs = [for (final s in plan.cut) (start: s.from * _frameS, end: s.to * _frameS)];
  final out = runs.isEmpty ? y : shortenRuns(y, sr, runs, cap: capS);
  final clamped = Float32List(out.length);
  for (var i = 0; i < out.length; i++) {
    clamped[i] = out[i].clamp(-1.0, 1.0);
  }
  return clamped;
}

/// [y] with each (start s, end s) silent run longer than [cap] cut to [cap] from its middle, crossfaded over [fade]
/// s. Exactly ganj_voice.pausetrim.shorten_runs (the crossfade is computed in float64 and rounded to float32 once).
Float32List shortenRuns(
  Float32List y,
  int sr,
  List<({double start, double end})> runs, {
  double cap = 0.30,
  double fade = 0.01,
}) {
  final nFade = math.max((fade * sr).toInt(), 1);
  final keep = _pyRound(cap * sr);
  final sorted = [...runs]
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.end.compareTo(b.end);
    });
  final out = <double>[];
  var pos = 0;
  int clampIdx(int i) => i < 0 ? 0 : (i > y.length ? y.length : i);
  for (final r in sorted) {
    final a = _pyRound(r.start * sr), b = _pyRound(r.end * sr);
    if (b - a <= keep + nFade) continue;
    final cut0 = a + keep ~/ 2;
    final cut1 = b - (keep - keep ~/ 2) - nFade;
    final h0 = clampIdx(pos), h1 = math.max(h0, clampIdx(cut0));
    final t0 = clampIdx(cut1), t1 = math.max(t0, clampIdx(cut1 + nFade));
    final headLen = h1 - h0, tailLen = t1 - t0;
    if (headLen >= nFade && tailLen == nFade) {
      for (var i = h0; i < h1 - nFade; i++) {
        out.add(y[i]);
      }
      // numpy.linspace(1, 0, n): i * step + start, the last value set to stop exactly.
      final step = -1.0 / (nFade - 1);
      for (var i = 0; i < nFade; i++) {
        final w = nFade == 1 ? 1.0 : (i == nFade - 1 ? 0.0 : i * step + 1.0);
        out.add(y[h1 - nFade + i] * w + y[t0 + i] * (1 - w));
      }
      pos = cut1 + nFade;
    } else {
      for (var i = h0; i < h1; i++) {
        out.add(y[i]);
      }
      pos = cut1;
    }
  }
  for (var i = clampIdx(pos); i < y.length; i++) {
    out.add(y[i]);
  }
  return Float32List.fromList(out);
}

/// Python's round() for floats: half to even.
int _pyRound(double x) {
  final f = x.floorToDouble();
  final d = x - f;
  final i = f.toInt();
  if (d > 0.5) return i + 1;
  if (d < 0.5) return i;
  return i.isEven ? i : i + 1;
}
