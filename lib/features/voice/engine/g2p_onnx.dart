import 'dart:convert';
import 'dart:typed_data';

import '../reading/g2p.dart';
import 'ort.dart';

/// The voice's letters-to-phonemes model (a 2+2-layer ByT5, Homo-GE2PE fine-tune) run through ONNX Runtime.
///
/// The encoder and a cache-less decoder (log-softmax of the last position) are exported from the voice's `g2p/`
/// folder. [generate] reproduces transformers' beam search for this model exactly (length penalty 1.0, early stopping
/// off, max length 512): every model call recorded from the Python front-end comes out identical.
class OnnxG2pModel implements G2pModel {
  OnnxG2pModel(Ort ort, Uint8List encoder, Uint8List decoder, {int threads = 2})
    : _enc = ort.session(encoder, threads: threads),
      _dec = ort.session(decoder, threads: threads);

  final OrtSession _enc;
  final OrtSession _dec;

  static const _eos = 1;
  static const _neg = -1.0e9;
  static const _maxLength = 512;

  @override
  String top1(String text) => generate(text, numBeams: 5, numReturn: 1).first;

  @override
  List<String> nbest(String text, int n) => generate(text, numBeams: n, numReturn: n);

  /// Beam search as transformers 5 `_beam_search` does it (greedy top-2k candidates per step, finished hypotheses
  /// scored by summed log-probability over generated length, the early-stop heuristic of `early_stopping=False`).
  List<String> generate(String text, {required int numBeams, required int numReturn}) {
    final bytes = utf8.encode(text);
    final ids = Int64List.fromList([for (final b in bytes) b + 3]);
    final enc = _enc
        .run(
          [
            OrtInput.int64('ids', ids, [1, ids.length]),
          ],
          ['enc'],
        )
        .first;
    final s = enc.shape[1], h = enc.shape[2];
    final encB = Float32List(numBeams * s * h);
    for (var b = 0; b < numBeams; b++) {
      encB.setAll(b * s * h, enc.data);
    }
    final k = 2 * numBeams;
    var runSeq = List.generate(numBeams, (_) => <int>[0]);
    var runSc = List<double>.filled(numBeams, _neg)..[0] = 0;
    var finSeq = List<List<int>?>.filled(numBeams, null);
    var finSc = List<double>.filled(numBeams, _neg);
    var finDone = List<bool>.filled(numBeams, false);
    var improving = true;
    var cur = 1;
    while (true) {
      final len = runSeq.first.length;
      final dec = Int64List(numBeams * len);
      for (var b = 0; b < numBeams; b++) {
        dec.setAll(b * len, runSeq[b]);
      }
      final lp = _dec
          .run(
            [
              OrtInput.int64('dec_ids', dec, [numBeams, len]),
              OrtInput.float32('enc', encB, [numBeams, s, h]),
            ],
            ['logp'],
          )
          .first;
      final v = lp.shape[1];
      // Accumulated log-probabilities in float32, as torch keeps them.
      final acc = Float32List(numBeams * v);
      for (var b = 0; b < numBeams; b++) {
        final base = Float32List.fromList([runSc[b]])[0];
        for (var t = 0; t < v; t++) {
          acc[b * v + t] = lp.data[b * v + t] + base;
        }
      }
      final top = _topK(acc, k);
      final tlp = [for (final i in top) acc[i].toDouble()];
      final tseq = [
        for (final i in top) <int>[...runSeq[i ~/ v], i % v],
      ];
      final hit = [for (final i in top) i % v == _eos || cur + 1 >= _maxLength];
      // The next running beams: the best k candidates that did not finish.
      final rlp = Float32List.fromList([for (var j = 0; j < k; j++) tlp[j] + (hit[j] ? _neg : 0)]);
      final nxt = _topK(rlp, numBeams);
      final newRunSeq = [for (final j in nxt) tseq[j]];
      final newRunSc = [for (final j in nxt) rlp[j].toDouble()];
      // Finished hypotheses: only the top numBeams candidates may finish.
      final fsc = Float32List(k);
      for (var j = 0; j < k; j++) {
        final just = hit[j] && j < numBeams;
        fsc[j] = (tlp[j] / (cur + 1 - 1)) + (improving ? 0 : _neg) + (just ? 0 : _neg);
      }
      final mSc = Float32List.fromList([...finSc, ...fsc]);
      final mSeq = [...finSeq, ...tseq];
      final mDone = [...finDone, for (var j = 0; j < k; j++) hit[j] && j < numBeams];
      final keep = _topK(mSc, numBeams);
      finSc = [for (final i in keep) mSc[i].toDouble()];
      finSeq = [for (final i in keep) mSeq[i]];
      finDone = [for (final i in keep) mDone[i]];
      runSeq = newRunSeq;
      runSc = newRunSc;
      cur++;
      final bestRun = Float32List.fromList([runSc[0] / (cur - 1)])[0];
      final worst = finSc.reduce((a, b) => a < b ? a : b);
      improving = improving && finDone.any((d) => bestRun > (d ? worst : _neg));
      if (!improving || hit.every((x) => x)) break;
    }
    return [for (final sq in finSeq.take(numReturn)) _decode(sq)];
  }

  /// Indices of the [k] largest values, largest first; ties keep the lower index (stable).
  static List<int> _topK(Float32List x, int k) {
    final idx = List<int>.generate(x.length, (i) => i);
    idx.sort((a, b) {
      final c = x[b].compareTo(x[a]);
      return c != 0 ? c : a.compareTo(b);
    });
    return idx.sublist(0, k);
  }

  static String _decode(List<int>? seq) {
    if (seq == null) return '';
    final bytes = [
      for (final t in seq.skip(1))
        if (t >= 3 && t < 259) t - 3,
    ];
    return utf8.decode(bytes, allowMalformed: true).replaceAll('�', '').trim();
  }

  void dispose() {
    _enc.dispose();
    _dec.dispose();
  }
}
