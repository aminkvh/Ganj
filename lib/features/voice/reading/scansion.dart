// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-reading/ganj_reading/scansion.py.

import 'pystr.dart';

/// Aruz scansion of GE2PE phonemes against a poem's metre.
///
/// A hemistich whose phonemes scan in the poem's metre is very likely pronounced right (short vowels, ezafe, word
/// joins); one that does not points at a G2P error.
///
/// Weights: U light, - heavy. Short vowels are / e o (the ezafe is e followed by the marker 1); long vowels are a i u.
/// A syllable takes the one consonant before its vowel as onset. CV = U, CVC and CV̄ = -, CV̄C and CVCC = -U (overlong).
/// Licences honoured (the common ekhtiyarat): the last syllable of a hemistich is free; a word-initial glottal stop
/// (@) may drop and link the previous consonant (bešnav-in); an n after a long vowel may be silent (an, in, un); an
/// open syllable at a word end may be read long or short; a long vowel before another vowel may be short; the first
/// foot of ramal may be fa'ilatun for fa'ilatun.
const String _short = '/eo';
const String _markers = '1'; // GE2PE ezafe marker: follows the ezafe vowel, is not itself a sound
const String _long = 'aiu';
const String _vowels = '$_short$_long';
const String _consonants = 'bcdfghjklmnpqrstvxyzš@;';

const Map<String, List<String>> _feet = {
  'فاعلاتن': ['-U--'],
  'فعولن': ['U--'],
  'فعلاتن': ['UU--'],
  'مفاعلن': ['U-U-'],
  'مفاعیلن': ['U---'],
  'فاعلن': ['-U-'],
  'مفعول': ['--U'],
  'فعلن': ['UU-', '--'],
  'مفاعیل': ['U--U'],
  'مستفعلن': ['--U-'],
  'مفتعلن': ['-UU-'],
  'فعل': ['U-'],
  'فاعلات': ['-U-U'],
  'فعلات': ['UU-U'],
  'فع': ['-'],
  'متفاعلن': ['UU-U-'],
  'متفاعلاتن': ['UU-U--'],
  'مستفعلتن': ['--UU-'],
};
const String _footFailatun = 'فاعلاتن';
const String _footFa3latun = 'فعلاتن';
const int _maxElisionWords = 6;

/// One syllable: its weight and the weights it may be read with.
class Syllable {
  const Syllable(this.weight, this.options);
  final String weight;
  final Set<String> options;
}

/// The scansion patterns (strings of U and -) a metre's feet allow; empty for a metre that is not understood.
Set<String> metrePatterns(String metre) {
  final feet = pySplitWs(metre.split('(')[0]);
  if (feet.isEmpty || feet.any((f) => !_feet.containsKey(f))) return <String>{};
  final alts = [for (final f in feet) _feet[f]!];
  if (feet[0] == _footFailatun || feet[0] == _footFa3latun) {
    // the first foot of ramal/khafif may be either
    alts[0] = [..._feet[_footFailatun]!, ..._feet[_footFa3latun]!];
  }
  var acc = <String>[''];
  for (final a in alts) {
    acc = [
      for (final p in acc)
        for (final x in a) p + x,
    ];
  }
  return acc.toSet();
}

String _clean(String word) {
  final b = StringBuffer();
  for (final c in word.split('')) {
    if (_vowels.contains(c) || _consonants.contains(c)) b.write(c);
  }
  return b.toString();
}

/// Syllables of a phoneme string with word boundaries removed; [wordEnds] are indices of word-final phonemes.
List<Syllable> syllables(String seq, [List<int> wordEnds = const []]) {
  final endSet = wordEnds.toSet();
  final keep = [
    for (var i = 0; i < seq.length; i++)
      if (!_markers.contains(seq[i])) i,
  ];
  final ends = <int>{
    for (var k = 0; k < keep.length; k++)
      if (endSet.contains(keep[k]) ||
          (keep[k] + 1 < seq.length && _markers.contains(seq[keep[k] + 1]) && endSet.contains(keep[k] + 1)))
        k,
  };
  seq = keep.map((i) => seq[i]).join();
  final vs = [
    for (var i = 0; i < seq.length; i++)
      if (_vowels.contains(seq[i])) i,
  ];
  final out = <Syllable>[];
  for (var k = 0; k < vs.length; k++) {
    final v = vs[k];
    final hasNext = k + 1 < vs.length;
    final int nxtOnset;
    if (hasNext && !_vowels.contains(seq[vs[k + 1] - 1])) {
      nxtOnset = vs[k + 1] - 1;
    } else if (hasNext) {
      nxtOnset = vs[k + 1];
    } else {
      nxtOnset = seq.length;
    }
    final coda = pySlice(seq, v + 1, nxtOnset);
    final isLong = _long.contains(seq[v]);
    final String w;
    if (isLong) {
      w = coda.isEmpty ? '-' : '-U';
    } else {
      w = coda.isEmpty ? 'U' : (coda.length == 1 ? '-' : '-U');
    }
    final opts = <String>{w};
    if (isLong && coda.isEmpty && hasNext && (nxtOnset == vs[k + 1] || 'y@'.contains(seq[nxtOnset]))) {
      opts.add('U'); // a long vowel before another vowel (hiatus, often written with a glide y) may be short
    }
    if (isLong && coda == 'n') opts.add('-'); // silent nun after a long vowel
    final last = v + coda.length;
    if (coda.isEmpty && ends.contains(last)) {
      opts.addAll(const ['U', '-']); // open syllable at a word end: either length
    }
    out.add(Syllable(w, opts));
  }
  return out;
}

/// Phoneme strings for the line with each droppable word-initial @ kept or dropped (the string and the word ends).
Iterable<(String, List<int>)> _variants(List<String> words) sync* {
  var dropAt = [
    for (var i = 1; i < words.length; i++)
      if (words[i].startsWith('@') &&
          words[i - 1].isNotEmpty &&
          _consonants.contains(words[i - 1][words[i - 1].length - 1]))
        i,
  ];
  if (dropAt.length > _maxElisionWords) dropAt = dropAt.sublist(0, _maxElisionWords);
  final n = dropAt.length;
  for (var m = 0; m < (1 << n); m++) {
    final ws = List<String>.from(words);
    for (var j = 0; j < n; j++) {
      if ((m >> (n - 1 - j)) & 1 == 1) ws[dropAt[j]] = ws[dropAt[j]].substring(1);
    }
    final seq = StringBuffer();
    final ends = <int>[];
    var pos = 0;
    for (final w in ws) {
      seq.write(w);
      pos += w.length;
      if (w.isNotEmpty) ends.add(pos - 1);
    }
    yield (seq.toString(), ends);
  }
}

bool _matches(List<Syllable> syls, String pattern) {
  if (syls.isEmpty) return false;
  var cur = <int>{0};
  for (final s in syls.sublist(0, syls.length - 1)) {
    cur = {
      for (final p in cur)
        for (final o in s.options)
          if (p + o.length <= pattern.length && pattern.startsWith(o, p)) p + o.length,
    };
    if (cur.isEmpty) return false;
  }
  return cur.contains(pattern.length - 1); // the hemistich's last syllable is free
}

/// Whether the phonemes scan in the metre (any pattern of the metre, any @-drop variant).
bool scans(String phonemes, String metre) {
  final patterns = metrePatterns(metre);
  final words = [
    for (final w in phonemes.replaceAll(r'$', 'š').split(' '))
      if (_clean(w).isNotEmpty) _clean(w),
  ];
  if (patterns.isEmpty || words.isEmpty) return false;
  for (final (seq, ends) in _variants(words)) {
    final syls = syllables(seq, ends);
    if (patterns.any((p) => _matches(syls, p))) return true;
  }
  return false;
}
