// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-reading/ganj_reading/g2p.py.

import 'lexicon_data.dart';
import 'pystr.dart';
import 'scansion.dart';
import 'tokens.dart';

/// The neural grapheme-to-phoneme model (Homo-GE2PE), implemented by the app with ONNX.
abstract interface class G2pModel {
  /// Beam 5, best output for one text.
  String top1(String text);

  /// The [n] best outputs, best first.
  List<String> nbest(String text, int n);
}

/// A line the reading front-end cannot phonemize (no words, no usable model output).
class PhonemizeError implements Exception {
  PhonemizeError(this.message);
  final String message;

  @override
  String toString() => 'PhonemizeError: $message';
}

/// Homo-GE2PE front-end (MIT) with a word lexicon applied first.
///
/// Ganjoor's partial vowel marks are honoured as constraints: among the model's n best readings the one that agrees
/// with the written marks wins (harakat_agrees).

const String _tatweel = 'ـ';
const String _zwnj = '\u200C';
const String _zwj = '\u200D';

/// The harakat: U+064B..U+0670.
bool _isHarakat(int c) => c >= 0x64B && c <= 0x670;

/// The harakat except the small alef (U+064B..U+065F).
bool _isNotSmallAlef(int c) => c >= 0x64B && c <= 0x65F;

bool _hasHarakat(String s) => s.codeUnits.any(_isHarakat);

String _removeWhere(String s, bool Function(int) test) => String.fromCharCodes(s.codeUnits.where((c) => !test(c)));

bool _isPunct(int c) =>
    c == 0x060C ||
    c == 0x061B ||
    c == 0x061F ||
    c == 0x2E || // .
    c == 0x2C || // ,
    c == 0x3B || // ;
    c == 0x3A || // :
    c == 0x21 || // !
    c == 0x3F || // ?
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0xAB ||
    c == 0xBB ||
    c == 0x22 || // "
    c == 0x27 || // '
    (c >= 0x2010 && c <= 0x2015) ||
    c == 0x2D; // -

/// No-break, thin and other typographic spaces are word breaks (U+00A0 in the corpus text glued words together).
/// ZWNJ (U+200C, the Persian half-space) is NOT one of them: it joins the parts of one word (می\u200Cروم).
bool _isTypographicSpace(int c) =>
    c == 0xA0 || (c >= 0x2000 && c <= 0x200A) || c == 0x202F || c == 0x205F || c == 0x3000;

final RegExp _spaceRun = RegExp(r'[ \t]+');

/// NFC, Arabic yeh/kaf to Persian, heh with hamza to heh, no tatweel, punctuation and typographic spaces to a space.
String normalizeFa(String text) {
  var t = nfc(text);
  t = t.replaceAll('ي', 'ی').replaceAll('ى', 'ی').replaceAll('ك', 'ک').replaceAll('ۀ', 'ه').replaceAll(_tatweel, '');
  t = String.fromCharCodes(t.codeUnits.map((c) => (_isTypographicSpace(c) || _isPunct(c)) ? 0x20 : c));
  return pyStrip(t.replaceAll(_spaceRun, ' '));
}

String stripHarakat(String text) => _removeWhere(text, _isHarakat);

/// Which reading rules made a reading; saved readings are keyed on it so older rules' readings are never reused.
const kReadingRulesVersion = '1.2.0';

/// Candidates tried against the metre and the written vowel marks.
const int nbestCount = 8;

/// Words that never carry ezafe (from a 140-line hand audit: the model put one on ز in 11 of 15 cases).
const Set<String> noEzafe = {
  'درین',
  'ز',
  'زان',
  'زانک',
  'زانکه',
  'زین',
  'وان',
  'ور',
  'وز',
  'وین',
  'کآن',
  'کای',
  'کاین',
  'کز',
  'کو',
  'گرت',
};

/// A finite verb cannot be an ezafe dependent, so the word before one takes no ezafe. Closed list of light/copular
/// verbs; stems that are also common nouns (داد، دید، ساخت، گفت) are left out.
final RegExp finiteVerb = RegExp(
  '^(ن|نمی\u200C?|می\u200C?|ب)?(کرد|شد|بود|گشت|نمود|داشت|گردید|آمد|رفت|افتاد)(م|ی|یم|ید|ند)?\$'
  '|^(ن|نمی\u200C?|می\u200C?|ب)?(باش|شو|کن|گرد)(م|ی|د|یم|ید|ند)\$|^(است|نیست|هست)\$',
);

// Written vowel marks: fatha -> /, kasra -> e, damma (zamma) -> o. Sukun (U+0652) is NOT a vowel: it marks a letter
// with no vowel after it, checked by harakatAgrees; a final sukun means no ezafe.
const Map<String, String> _markVowel = {'َ': '/', 'ِ': 'e', 'ُ': 'o'};
const String _sukun = 'ْ';
const String _shortVowels = '/eo';
const String _hehHamza = 'ۀ', _hamzaAbove = 'ٔ', _kasra = 'ِ', _ezafe = '1';
const List<String> _vowelLetters = ['ه', 'ا', 'و', 'ی', 'ء', _hehHamza, _hamzaAbove, _kasra];
const List<String> _vowelEnd = ['a', 'e', 'i', 'o', 'u', '/'];

bool _endsWithAny(String s, List<String> suffixes) => suffixes.any(s.endsWith);

/// Add the ezafe (e after a consonant, ye after a vowel, then GE2PE's marker 1) unless it is already there.
///
/// Keeps the model's ezafe when a lexicon entry replaces a word, and pronounces a written ezafe (ۀ, هٔ, or a final
/// kasra). A final e on a word not written with a final ه is the model's bare ezafe, so it only gets its marker
/// (روزِ: ruze -> ruze1, not ruzeye1). On a word with a final ه the model's bare ezafe is ye: when the reading already
/// ends in e + ye, and that ye cannot be the word's own (no ی before the ه, or a second ye after it), it only gets
/// its marker (گوشهٔ: gušeye -> gušeye1, not gušeyeye1).
String withEzafe(String ph, bool ezafe, [String plain = '']) {
  if (!ezafe || ph.endsWith(_ezafe)) return ph;
  if (ph.endsWith('e') && plain.isNotEmpty && !plain.endsWith('ه')) return ph + _ezafe;
  if (plain.endsWith('ه') && ph.endsWith('ye')) {
    final stem = ph.substring(0, ph.length - 2);
    final beforeLast = plain.length >= 2 ? plain[plain.length - 2] : '';
    if (stem.endsWith('e') && (beforeLast != 'ی' || stem.endsWith('ye'))) return ph + _ezafe;
  }
  return ph + (_endsWithAny(ph, _vowelEnd) ? 'ye1' : 'e1');
}

/// Remove the ezafe the reading ends with (e1, or ye1 after a vowel).
String stripEzafe(String ph, [String word = '']) {
  if (ph.endsWith('ye1')) {
    // روی: ruye1 -> ruy (consonant y); ماهی: mahiye1 -> mahi; روزیِّ: ruziyye1 -> ruziyy (a doubled y takes e1)
    return (word.endsWith('ای') || word.endsWith('وی') || ph.endsWith('yye1'))
        ? ph.substring(0, ph.length - 2)
        : ph.substring(0, ph.length - 3);
  }
  return ph.endsWith('e1') ? ph.substring(0, ph.length - 2) : ph;
}

/// Tashdid / shadda (U+0651): the letter before it is doubled (gemination), e.g. shakkar -> š/kk/r; see [geminate].
const String _shadda = 'ّ';
const Map<String, String> _letterPhone = {
  'ب': 'b',
  'پ': 'p',
  'ت': 't',
  'ط': 't',
  'ث': 's',
  'س': 's',
  'ص': 's',
  'ج': 'j',
  'چ': 'c',
  'ح': 'h',
  'ه': 'h',
  'خ': 'x',
  'د': 'd',
  'ذ': 'z',
  'ز': 'z',
  'ض': 'z',
  'ظ': 'z',
  'ر': 'r',
  'ژ': ';',
  'ش': 'š',
  'غ': 'q',
  'ق': 'q',
  'ف': 'f',
  'ک': 'k',
  'گ': 'g',
  'ل': 'l',
  'م': 'm',
  'ن': 'n',
  'و': 'v',
  'ی': 'y',
  'ع': '@',
  'ء': '@',
};

const String _smallAlef = 'ٰ';

bool _finalSmallAlef(String word) {
  final w = _removeWhere(word, _isNotSmallAlef).replaceAll(_zwnj, '');
  return w.endsWith('ی$_smallAlef') || w.endsWith('ى$_smallAlef');
}

/// A final ی carrying the small alef (یٰ: کسریٰ, عُقبیٰ, مصطفیٰ) is read a.
String smallAlef(String word, String ph) {
  if (!_finalSmallAlef(word)) return ph;
  const tail = 'iye$_ezafe';
  if (ph.endsWith(tail)) return '${ph.substring(0, ph.length - tail.length)}aye$_ezafe';
  return ph.endsWith('i') ? '${ph.substring(0, ph.length - 1)}a' : ph;
}

const Map<String, String> _tanwin = {'ً': '/', 'ٌ': 'o', 'ٍ': 'e'}; // ً -an, ٌ -on, ٍ -en
const String _taMarbuta = 'ة';

/// The vowel of a tanwin on the word's last letter (ً written before a final alef counts: حتمًا), else null.
String? _tanwinVowel(String word) {
  final w = word.replaceAll(_zwnj, '');
  var i = w.length;
  while (i > 0 && _isHarakat(w.codeUnitAt(i - 1))) {
    i--;
  }
  var marks = w.substring(i);
  if (marks.isEmpty && w.endsWith('ا')) {
    var k = w.length - 1;
    while (k > 0 && _isHarakat(w.codeUnitAt(k - 1))) {
      k--;
    }
    marks = w.substring(k, w.length - 1);
  }
  for (final c in marks.split('')) {
    final v = _tanwin[c];
    if (v != null) return v;
  }
  return null;
}

/// A written tanwin is read with its n and no ezafe (فرضاً f/rz/n, قَلیلٌ q/lilon, خیرٍ xeyren); the alef that
/// carries a tanwin fath is not a long a.
String tanwin(String word, String ph) {
  final v = _tanwinVowel(word);
  if (v == null || v.isEmpty) return ph;
  var body = stripEzafe(ph, stripHarakat(word));
  if (v == '/' && body.endsWith('a')) body = body.substring(0, body.length - 1);
  if (body.endsWith('${v}n')) return body;
  return '${body.endsWith(v) ? body : body + v}n';
}

final RegExp _taMarbutaBeforeMark = RegExp('$_taMarbuta(?=[ً-ْ])');

/// ة as the model can read it: ت when a mark follows (رحمةٌ: r/hm/ton), else a final ه (لیلة: leyle). Passed as is,
/// the model read it k.
String _readTaMarbuta(String word) => word.replaceAll(_taMarbutaBeforeMark, 'ت').replaceAll(_taMarbuta, 'ه');

/// No more long a in the reading than letters that can write one (ا آ أ إ, the small alef, a final ی as in موسی, the
/// لله of الله): Persian writes a long a. «مهتر» read mehtar in all 27 training labels (meht/r or m/ht/r).
bool longAWritten(String word, String ph) {
  final base = pyRstripChars(_removeWhere(word, _isNotSmallAlef).replaceAll(_zwnj, ''), _smallAlef);
  var n = 0;
  for (final c in 'اآأإ$_smallAlef'.split('')) {
    n += c.allMatches(word).length;
  }
  if (base.endsWith('ی') || base.endsWith('ى')) n++;
  if (word.contains('لله')) n++;
  return 'a'.allMatches(stripEzafe(ph, base)).length <= n;
}

const String _yeAst = 'ی‌است';

/// Ruled 2026-11-09: a word written with ی‌است is read -ist (زبانی‌است z/banist, not z/bani/st), unless the line then
/// fails a metre it scans in. A one-letter stem keeps its ast (نی‌است, کی‌است).
List<String> contractAst(List<String> words, List<String> pw, String? metre) {
  String one(String word, String ph) {
    final plain = stripHarakat(word);
    if (plain.endsWith(_yeAst) && plain.length - _yeAst.length >= 2) {
      for (final tail in const ['i/st', 'i@/st']) {
        if (ph.endsWith(tail)) return '${ph.substring(0, ph.length - tail.length)}ist';
      }
    }
    return ph;
  }

  final out = [for (var i = 0; i < words.length && i < pw.length; i++) one(words[i], pw[i])];
  if (!_listEq(out, pw) &&
      metre != null &&
      metre.isNotEmpty &&
      scans(pw.join(' '), metre) &&
      !scans(out.join(' '), metre)) {
    return List<String>.from(pw);
  }
  return out;
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A final kasra or هٔ; Unicode writes a kasra before a shadda on the same letter (حقِّ = ح ق ِ ّ).
bool writtenEzafe(String word) =>
    word.endsWith('ه$_hamzaAbove') || word.endsWith(_kasra) || word.endsWith('$_kasra$_shadda');

/// The written short vowels (a final kasra is the ezafe) occur in order among the phonemes' vowels, each as a vowel
/// that reads it ([_markOptions]: مَی mey, کَرِیم k/rim), and every letter carrying a shadda appears doubled (شکّر →
/// š/kk/r).
bool harakatAgrees(String word, String ph) {
  final body = stripEzafe(ph);
  if (word.endsWith('$_kasra$_shadda')) {
    word = word.substring(0, word.length - 2) + _shadda; // حقِّ: the kasra is the ezafe
  }
  final lm = _letters(word);
  final vowels = [
    for (final c in body.split(''))
      if (_vowels.contains(c)) c,
  ];
  var pos = 0; // one pass over the vowels, as Python's shared iterator
  for (final (i, v) in _marked(lm)) {
    final options = _markOptions(lm, i, v);
    while (pos < vowels.length && !options.contains(vowels[pos])) {
      pos++;
    }
    if (pos >= vowels.length) return false;
    pos++;
  }
  final letters = [
    for (final c in word.split(''))
      if (!_hasHarakat(c) || c == _shadda) c,
  ];
  final doubled = [
    for (var i = 1; i < letters.length; i++)
      if (letters[i] == _shadda) _letterPhone[letters[i - 1]],
  ];
  final v = _tanwinVowel(word);
  return doubled.every((p) => p == null || body.contains(p * 2)) &&
      _sukunAgrees(word, ph) &&
      (!_finalSmallAlef(word) || body.endsWith('a')) &&
      (v == null || v.isEmpty || body.endsWith('${v}n'));
}

/// No short vowel right after the sound of a letter written with a sukun (مَرْدُم: m/rdom, not m/r/dom). The letter is
/// found at its occurrence counted among same-sounding letters, as in [geminate]; و ی ه ع are too ambiguous to place.
bool _sukunAgrees(String word, String ph) {
  final base = <String>[];
  final quiet = <int>[];
  for (final c in word.split('')) {
    if (c == _sukun) {
      if (base.isNotEmpty) {
        quiet.add(base.length - 1); // a sukun typed after a ZWNJ still belongs to the letter before it
      }
    } else if (!_hasHarakat(c) && c != _zwnj && c != _zwj) {
      base.add(c);
    }
  }
  for (final i in quiet) {
    final p = _letterPhone[base[i]];
    if (p == null || p.isEmpty || _noGeminate.contains(p)) continue;
    var k = 0;
    for (final x in base.sublist(0, i)) {
      if (_letterPhone[x] == p) k++;
    }
    final pos = [
      for (var j = 0; j < ph.length; j++)
        if (ph[j] == p) j,
    ];
    if (k >= pos.length) continue;
    final j = pos[k] + (pySlice(ph, pos[k] + 1, pos[k] + 2) == p ? 1 : 0); // a doubled consonant is one letter
    final next = pySlice(ph, j + 1, j + 2);
    if (next.isNotEmpty && _shortVowels.contains(next)) return false;
  }
  return true;
}

const Set<String> _noGeminate = {
  'v',
  'y',
  'h',
  '@',
}; // و ی ه ع/ء: often vowels or silent in writing, too ambiguous to place

// Reading the written marks (ruled 2026-11-11): each letter with its marks, the vowels that read a mark, and the repair
const String _alefs = 'اأإآ', _ye = 'ی', _he = 'ه';
const String _vowels = '${_shortVowels}aiu';
// مِی is mey (the kasra is written: never mi); کِی دِی نِی are read either way, فِی لِی هِی are Arabic i
const String _meyM = 'م';

/// Python's `x in s` for a string: true for the empty string too (the last letter has no letter after it, and Python
/// then counts '' as in ALEFS).
bool _pyIn(String x, String s) => s.contains(x);

/// One letter of a word as [_letters] gives it.
class _Letter {
  _Letter(this.c, this.start);
  final String c;
  String marks = '';
  final bool start; // starts a morpheme
  bool end = false; // ends a morpheme
}

/// [letter, its marks, starts a morpheme, ends a morpheme] for each letter of the word; a ZWNJ ends a morpheme.
/// Marks are the nonspacing marks (Unicode category Mn, as Python's unicodedata has them).
List<_Letter> _letters(String word) {
  final out = <_Letter>[];
  var start = true;
  for (final c in word.runes) {
    if (c == 0x200C) {
      if (out.isNotEmpty) out.last.end = true;
      start = true;
    } else if (c == 0x200D) {
      continue;
    } else if (isPyMn(c)) {
      if (out.isNotEmpty) out.last.marks += String.fromCharCode(c);
    } else {
      out.add(_Letter(String.fromCharCode(c), start));
      start = false;
    }
  }
  if (out.isNotEmpty) out.last.end = true;
  return out;
}

String? _markVowelOf(String marks) {
  for (final c in marks.split('')) {
    final v = _markVowel[c];
    if (v != null) return v;
  }
  return null;
}

/// (letter index, vowel) for each letter written with a short vowel; a kasra on the last letter is the ezafe.
List<(int, String)> _marked(List<_Letter> lm) {
  final out = <(int, String)>[
    for (var i = 0; i < lm.length; i++)
      if (_markVowelOf(lm[i].marks) case final v?) (i, v),
  ];
  if (out.isNotEmpty && out.last == (lm.length - 1, 'e')) out.removeLast();
  return out;
}

/// Letter i has no vowel mark, or only the ezafe's kasra on the last letter (مَیِ).
bool _bare(List<_Letter> lm, int i) {
  final v = _markVowelOf(lm[i].marks);
  return v == null || (v == 'e' && i == lm.length - 1);
}

/// Letter i + 1 is a bare ی/و ([letter]) followed by no ا and no final ی/و: the ey of هَیجا and حَیوان, the ow of دَولت
/// (not the consonant of بَیان، بِشَوی).
bool _semivowel(List<_Letter> lm, int i, String letter) {
  if (i + 1 >= lm.length || lm[i + 1].c != letter || !_bare(lm, i + 1)) return false;
  if (i + 2 >= lm.length || lm[i + 1].end) return true;
  final n = lm[i + 2];
  return !_pyIn(n.c, 'اآ') && !(_pyIn(n.c, _ye + _vav) && n.end);
}

/// مِی as a whole morpheme (مِی، مِی‌پرستی).
bool _mey(List<_Letter> lm, int i) => lm[i].start && lm[i].c == _meyM && _semivowel(lm, i, _ye) && lm[i + 1].end;

/// The vowels that read the mark [v] on letter [i] of _letters(word): fatha / (ey before a bare ی, the ow of a bare و
/// as o, a before ا or the final ی of لَدَی, the e of a final ه as in کَندَه), kasra e (the long i of a bare ی after it,
/// as in کَرِیم; مِی is ey), damma o (u before a bare و); a small alef on the letter writes a.
Set<String> _markOptions(List<_Letter> lm, int i, String v) {
  final after = i + 1 < lm.length ? lm[i + 1].c : '';
  final last = i + 1 < lm.length && lm[i + 1].end;
  final out = lm[i].marks.contains(_smallAlef) ? {v, 'a'} : {v};
  if (v == '/') {
    if (_pyIn(after, _alefs)) {
      out.add('a');
    } else if (_semivowel(lm, i, _ye)) {
      out.addAll(last ? const {'e', 'a'} : const {'e'});
    } else if (_semivowel(lm, i, _vav)) {
      out.add('o');
    } else if (after == _he && last) {
      out.add('e');
    }
  } else if (v == 'e' && after == _ye && _bare(lm, i + 1) && !_mey(lm, i)) {
    out.add('i');
  } else if (v == 'o' && after == _vav && _bare(lm, i + 1)) {
    out.add('u');
  }
  return out;
}

/// The index in [ph] of letter [i]'s consonant (the second of a doubled one), or null: the word's first letter is
/// ph[0] when it sounds as written (an alef as @); the others are found at their occurrence counted among
/// same-sounding letters, as in [geminate], and و ی ه ع/ء cannot be placed.
int? _place(List<_Letter> lm, int i, String ph) {
  int j;
  if (i == 0) {
    final p = _pyIn(lm[0].c, _alefs) ? '@' : _letterPhone[lm[0].c];
    if (p == null || p.isEmpty || !ph.startsWith(p)) return null;
    j = 0;
  } else {
    final p = _letterPhone[lm[i].c];
    if (p == null || p.isEmpty || _noGeminate.contains(p)) return null;
    var k = 0;
    for (final x in lm.sublist(0, i)) {
      if (_letterPhone[x.c] == p) k++;
    }
    final pos = [
      for (var n = 0; n < ph.length; n++)
        if (ph[n] == p) n,
    ];
    if (k >= pos.length) return null;
    j = pos[k];
  }
  return pySlice(ph, j + 1, j + 2) == ph[j] ? j + 1 : j;
}

/// [ph] with the vowel after letter [i] (its consonant at [j]) read as the mark [v].
String _readMark(List<_Letter> lm, int i, String v, String ph, int j, bool ezafe) {
  final nxt = pySlice(ph, j + 1, j + 2);
  final after = i + 1 < lm.length ? lm[i + 1].c : '';
  final last = i + 1 < lm.length && lm[i + 1].end;
  final head = ph.substring(0, j + 1), rest = pySlice(ph, j + 2, ph.length);
  if (nxt.isNotEmpty && _markOptions(lm, i, v).contains(nxt)) return ph;
  if (v == 'o' && after == _he && last && nxt == 'e') return ph; // سَعدُه: the Arabic -uh, not a vowel to swap
  if (nxt.isNotEmpty && _shortVowels.contains(nxt)) return head + v + rest;
  if (nxt == 'a' || nxt == 'i' || nxt == 'u') {
    if (nxt == 'i' && _semivowel(lm, i, _ye) && (_mey(lm, i) || (v == '/' && (!last || lm[i].start)))) {
      return head + (pySlice(ph, j + 2, j + 3) == 'y' ? 'e' : 'ey') + rest; // مِی mey, هَیجا heyja
    }
    if (nxt == 'u' && v == '/' && _semivowel(lm, i, _vav)) return '${head}o$rest'; // أَو: the ow of a bare و
    final written = switch (nxt) {
      'a' => _pyIn(after, _alefs) || lm[i].marks.contains(_smallAlef) || (after == _ye && last),
      'i' => after == _ye,
      _ => after == _vav,
    };
    return written ? ph : head + v + rest; // بِپْسَندی bepsandi -> beps/ndi
  }
  if (i < lm.length - 1 || !ezafe) return head + v + ph.substring(j + 1); // no vowel read after the letter
  return ph;
}

/// Ruled 2026-11-11 (training labels and test couplets went against their marks when no candidate read them): the
/// vowel after each marked letter becomes the mark (a short vowel swapped, a missing one added, a long vowel no letter
/// writes shortened), a sukun drops the vowel after its letter, مِی is mey and وَ is va. A letter that cannot be
/// placed ([_place]) is left, and a word that still does not agree keeps its reading. [lastVowel] false leaves the last
/// letter's mark to the next word («خَطُّ و خال», «گُلَ انْدَر»); the لله of Allah keeps its long a.
String followMarks(String word, String ph, {bool lastVowel = true}) {
  if (harakatAgrees(word, ph) || stripHarakat(word).contains('لله')) return ph;
  if (stripHarakat(word) == _vav && _markVowelOf(word) == '/') return 'v/';
  final body = stripEzafe(ph);
  final lm = _letters(word);
  final vowels = {for (final (i, v) in _marked(lm)) i: v};
  var out = body;
  for (var i = 0; i < lm.length; i++) {
    final quiet = lm[i].marks.contains(_sukun), v = vowels[i];
    if (!quiet && (v == null || (i == lm.length - 1 && !lastVowel))) continue;
    final j = _place(lm, i, out);
    if (j == null) continue;
    if (quiet) {
      final nxt = pySlice(out, j + 1, j + 2);
      if (nxt.isNotEmpty && _shortVowels.contains(nxt)) out = out.substring(0, j + 1) + pySlice(out, j + 2, out.length);
    } else {
      out = _readMark(lm, i, v!, out, j, body != ph);
    }
  }
  final updated = out + ph.substring(body.length);
  return harakatAgrees(word, updated) ? updated : ph;
}

List<String> _splitWords(String raw) => [
  for (final w in remapGe2pe(raw).split(' '))
    if (w.isNotEmpty) w,
];

/// A top answer worth looking past: the wrong word count (a looping or merging answer) or a long a its word does not
/// write ([longAWritten]).
bool needsNbest(String raw, List<String> words) {
  final pw = _splitWords(raw);
  if (pw.length != words.length) return true;
  for (var i = 0; i < pw.length; i++) {
    if (!longAWritten(words[i], pw[i])) return true;
  }
  return false;
}

/// The model sometimes slips into English-style letter pairs for one Persian sound (پیشه = pishe for piše). pair ->
/// (its one sound, the letters that write that sound, the letter pairs that rightly give the two sounds, as in
/// اصحاب = @/shab or روزها = ruzha).
const List<(String, String, String, String, String)> _letterPairs = [
  ('sh', 'š', 'ش', 'سصث', 'هح'),
  ('kh', 'x', 'خ', 'ک', 'هح'),
  ('gh', 'q', 'غق', 'گ', 'هح'),
  ('zh', ';', 'ژ', 'زذضظ', 'هح'),
];

/// Write a pair as its one sound when the word has that sound's letter and no two-letter source for the pair.
String fixLetterPairs(String plain, String ph) {
  final w = plain.replaceAll(_zwnj, '');
  for (final (pair, one, letters, first, second) in _letterPairs) {
    if (ph.contains(pair) &&
        letters.split('').any(w.contains) &&
        !first.split('').any((a) => second.split('').any((b) => w.contains(a + b)))) {
      ph = ph.replaceAll(pair, one);
    }
  }
  return ph;
}

bool _blockEq(List<String> seq, int a, int b, int k) {
  if (a + k > seq.length || b + k > seq.length) return false;
  for (var i = 0; i < k; i++) {
    if (seq[a + i] != seq[b + i]) return false;
  }
  return true;
}

/// The most times any k-long block of [seq] occurs back to back.
int _maxRun(List<String> seq, int k) {
  var best = 0;
  for (var i = 0; i < seq.length - k + 1; i++) {
    var r = 1;
    while (_blockEq(seq, i + r * k, i, k)) {
      r++;
    }
    if (r > best) best = r;
  }
  return best;
}

/// A looping seq2seq answer (صد گونه بجوشیدم twice, به که ماند ×5 for ×4): drop extra back-to-back copies of a block
/// the label repeats more times in a row than the text repeats any block of that length, while the label is longer than
/// the text. Returns the shortened label only if it then has the text's word count, else null (no guessing).
List<String>? deloop(List<String> pwIn, List<String> plain) {
  final pw = List<String>.from(pwIn);
  while (pw.length > plain.length) {
    (int, int)? cut;
    for (var k = 1; k < pw.length - plain.length + 1; k++) {
      final allowed = _maxRun(plain, k);
      for (var i = 0; i < pw.length - 2 * k + 1; i++) {
        var r = 1;
        while (_blockEq(pw, i + r * k, i, k)) {
          r++;
        }
        if (r > (allowed > 1 ? allowed : 1)) {
          cut = (i + (r - 1) * k, k); // the last copy of the run
          break;
        }
      }
      if (cut != null) break;
    }
    if (cut == null) return null;
    pw.removeRange(cut.$1, cut.$1 + cut.$2);
  }
  return pw.length == plain.length ? pw : null;
}

/// A shadda on ی, doubled like any other («ز مردیّ و زور» = m/rdiyy o zur): a final ی after the vowel i gets yy (with
/// its ezafe: ruziye1 -> ruziyye1); elsewhere the consonant y is doubled when no ی comes before it, since an earlier ی
/// may be the vowel i and the y could not be placed.
String _geminateY(List<String> letters, int i, String ph) {
  if (letters.sublist(i + 1).every((c) => c == _zwnj || c == _zwj)) {
    if (ph.endsWith('i')) return '${ph}yy';
    const tail = 'iye$_ezafe';
    if (ph.endsWith(tail)) return '${ph.substring(0, ph.length - 'ye$_ezafe'.length)}yye$_ezafe';
  }
  final before = letters.sublist(0, i - 1 < 0 ? 0 : i - 1);
  if (ph.contains('y') && !before.any((x) => _letterPhone[x] == 'y')) {
    final j = ph.indexOf('y');
    return '${ph.substring(0, j)}y${ph.substring(j)}';
  }
  return ph;
}

/// Double each shadda consonant that the phonemes leave single, at its occurrence counted among same-sounding letters.
String geminate(String word, String ph) {
  final letters = [
    for (final c in word.split(''))
      if (!_hasHarakat(c) || c == _shadda) c,
  ];
  var out = ph;
  for (var i = 0; i < letters.length; i++) {
    if (letters[i] != _shadda || i == 0) continue;
    final p = _letterPhone[letters[i - 1]];
    if (p == 'y' && !out.contains('yy')) {
      out = _geminateY(letters, i, out);
      continue;
    }
    if (p == null || p.isEmpty || _noGeminate.contains(p) || out.contains(p * 2)) continue;
    var k = 0; // earlier letters with the same sound
    for (final x in letters.sublist(0, i - 1)) {
      if (_letterPhone[x] == p) k++;
    }
    final pos = [
      for (var j = 0; j < out.length; j++)
        if (out[j] == p) j,
    ];
    if (k < pos.length) out = out.substring(0, pos[k]) + p + out.substring(pos[k]);
  }
  return out;
}

/// (The line's words, the same words as the model reads them: vowel marks dropped, ة readable). The written ezafe
/// mark (ۀ) is kept on the word through normalisation.
(List<String>, List<String>) modelWords(String text) {
  final words = G2P.words(text.replaceAll(_hehHamza, 'ه$_hamzaAbove'));
  return (words, [for (final w in words) stripHarakat(_readTaMarbuta(w))]);
}

/// The text's words prepared for the model.
class _Prepared {
  _Prepared(this.words, this.plain, this.joined, this.metred, this.guided);
  final List<String> words, plain;
  final String joined;
  final bool metred, guided;
}

class G2P {
  G2P(this.model, {Map<String, String>? lexicon}) : lexicon = lexicon ?? ganjLexicon;

  final G2pModel model;
  final Map<String, String> lexicon;

  /// Lines where the model's word count differed from the text's (lexicon skipped).
  int mismatches = 0;

  /// The words of a line: normalised, split on spaces, edge ZWNJ/ZWJ/LRM/RLM trimmed; a vowel mark typed as its own
  /// token belongs to the previous word.
  static List<String> words(String text) {
    final out = <String>[];
    for (var w in normalizeFa(text).split(' ')) {
      w = pyStripChars(
        w,
        '\u200C\u200D\u200E\u200F',
      ); // a trailing ZWNJ hid words from NO_EZAFE, the lexicon and the e-rule
      if (w.isEmpty) continue;
      if (out.isNotEmpty && stripHarakat(w).isEmpty) {
        out[out.length - 1] += w;
      } else {
        out.add(w);
      }
    }
    return out;
  }

  /// Lexicon entry unless the word's written vowel marks contradict it (وَ is va, not the entry's o).
  String? _lex(String word, String plain) {
    var e = lexicon[word];
    if (e == null || e.isEmpty) e = lexicon[plain];
    return (e != null && e.isNotEmpty && harakatAgrees(word, e)) ? e : null;
  }

  /// Homo-GE2PE is a sentence-level model. Called word by word it duplicates frequent words, so the whole line goes
  /// through the model once; the lexicon is applied by word position only when the model kept the text's word count.
  ///
  /// With the poem's metre, the model's n best outputs are tried best first and the first one that scans in the metre
  /// is used; if none scans, the top output is.
  String phonemizeLine(String text, [String? metre]) {
    final p = _prepare(text, metre);
    var raws = p.guided ? model.nbest(p.joined, nbestCount) : [model.top1(p.joined)];
    if (!p.guided && needsNbest(raws[0], p.words)) {
      raws = model.nbest(p.joined, nbestCount); // a looping, merging or unwritten-long-a answer: look further down
    }
    return _choose(text, p.words, p.plain, metre, p.metred, raws);
  }

  _Prepared _prepare(String text, String? metre) {
    final (words, plain) = modelWords(text);
    if (words.isEmpty) throw PhonemizeError('no words in ${_pyRepr(text)}');
    final metred = metre != null && metre.isNotEmpty && metrePatterns(metre).isNotEmpty;
    final guided = metred || words.any(_hasHarakat);
    return _Prepared(words, plain, plain.join(' '), metred, guided);
  }

  String _choose(String text, List<String> words, List<String> plain, String? metre, bool metred, List<String> raws) {
    List<String>? best;
    var bestAligned = false;
    List<int>? bestKey;
    for (final raw in raws) {
      var pw = _splitWords(raw);
      if (pw.isEmpty) continue;
      if (pw.length > words.length) pw = deloop(pw, plain) ?? pw;
      final aligned = pw.length == words.length;
      if (aligned) {
        final n = pw.length;
        pw = [for (var i = 0; i < n; i++) fixLetterPairs(plain[i], pw[i])];
        final lexed = [for (var i = 0; i < n; i++) _lex(words[i], plain[i])];
        // a lexicon reading's or a function word's final e is its own vowel (ز = ze, زانک = zanke), never a bare ezafe
        pw = [
          for (var i = 0; i < n; i++)
            withEzafe(
              lexed[i] ?? pw[i],
              pw[i].endsWith(_ezafe) || writtenEzafe(words[i]),
              (lexed[i] != null || noEzafe.contains(plain[i])) ? '' : plain[i],
            ),
        ];
        final last = n - 1; // the model often writes ezafe as a bare e; 1 is its own token
        pw = [
          for (var i = 0; i < n; i++)
            (i < last && !noEzafe.contains(plain[i]) && pw[i].endsWith('e') && !_endsWithAny(plain[i], _vowelLetters))
                ? pw[i] + _ezafe
                : pw[i],
        ];
        pw = [for (var i = 0; i < n; i++) noEzafe.contains(plain[i]) ? stripEzafe(pw[i], plain[i]) : pw[i]];
        // a written ezafe (final kasra, هٔ) outranks the finite-verb guess: «عقلِ کُندِ», «جهانِ هست»
        pw = [
          for (var i = 0; i < n; i++)
            (i < last && finiteVerb.hasMatch(plain[i + 1]) && !writtenEzafe(words[i]))
                ? stripEzafe(pw[i], plain[i])
                : pw[i],
        ];
        pw = [
          for (var i = 0; i < n; i++) words[i].endsWith(_sukun) ? stripEzafe(pw[i], plain[i]) : pw[i],
        ]; // دستْ: no ezafe
        pw = noEzafeBeforePause(text, words, plain, pw); // «به خواب، دو چشم»: xab
        pw[n - 1] = stripEzafe(pw[n - 1], plain[n - 1]); // a hemistich ends a phrase: no ezafe across the line break
        pw = contractAst(words, pw, metred ? metre : null);
      }
      // rank: aligned, scans the metre, agrees with the written vowel marks, then (when none aligns) the word count
      // closest to the text's — a refrain written 7 times for 4 loses to one written 5 times; ties keep the model's order
      final key = [
        aligned ? 1 : 0,
        (aligned && metred && scans(pw.join(' '), metre!)) ? 1 : 0,
        (aligned && _all(words, pw, harakatAgrees)) ? 1 : 0,
        (aligned && _all(words, pw, longAWritten)) ? 1 : 0,
        -(pw.length - words.length).abs(),
      ];
      if (bestKey == null || _keyGreater(key, bestKey)) {
        best = pw;
        bestAligned = aligned;
        bestKey = key;
      }
    }
    if (best == null) throw PhonemizeError('empty phonemes for ${_pyRepr(text)}');
    var pw = best;
    if (bestAligned) {
      // last resort, after ranking: a candidate that already doubles the shadda letter wins above
      pw = [
        for (var i = 0; i < pw.length; i++)
          tanwin(words[i], smallAlef(words[i], words[i].contains(_shadda) ? geminate(words[i], pw[i]) : pw[i])),
      ];
      // and one that reads the marks; a mark on the last letter before و or an alef runs into that word
      final last = [
        for (var i = 0; i < words.length; i++)
          i == words.length - 1 || !(plain[i + 1] == _vav || _alefs.split('').any((a) => plain[i + 1].startsWith(a))),
      ];
      pw = [for (var i = 0; i < pw.length; i++) followMarks(words[i], pw[i], lastVowel: last[i])];
    } else {
      mismatches++;
    }
    return pw.join(' ');
  }

  /// A unit's label: style/metre prefix, then the lines' phonemes joined with the hemistich mark.
  String phonemizeUnit(List<String> lines, String kind, [String? metre]) {
    lines = [
      for (final l in lines)
        if (pyStrip(l).isNotEmpty) l,
    ];
    if (lines.isEmpty) throw PhonemizeError('unit has no text');
    final prefix = kind == 'verse' ? tokVerse + metreToken(metre) : tokProse;
    return prefix + lines.map((l) => phonemizeLine(l, kind == 'verse' ? metre : null)).join(tokHemi);
  }
}

bool _all(List<String> a, List<String> b, bool Function(String, String) f) {
  for (var i = 0; i < a.length; i++) {
    if (!f(a[i], b[i])) return false;
  }
  return true;
}

bool _keyGreater(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

String _pyRepr(String s) => "'${s.replaceAll("'", "\\'")}'";

const String _shortMarks = '،,؛;:';
const String _longMarks = '.!?؟';
const String _vav = 'و';
const List<String> _vavMidVerse = [
  'o',
  'vo',
]; // the G2P's readings of a standalone و: the metre's -o (vo after a vowel)

/// The pause marks: short after ، , ؛ ; : and long after . ! ? ؟.
String get shortMarks => _shortMarks;
String get longMarks => _longMarks;

/// For each of G2P.words(line), the pause-bearing punctuation typed after it ('' if none); a mark typed apart
/// («شرع ، مرا») belongs to the word before it.
List<String> punctuationAfterWords(String line) {
  final out = <String>[];
  for (final tok in pySplitWs(line)) {
    final p = tok.split('').where((ch) => (_shortMarks + _longMarks).contains(ch)).join();
    final n = G2P.words(tok).length;
    if (n > 0) {
      out
        ..addAll(List.filled(n - 1, ''))
        ..add(p);
    } else if (out.isNotEmpty && p.isNotEmpty) {
      out[out.length - 1] += p;
    }
  }
  return out;
}

/// Ruled 2026-11-10 («تا کی ز قدیم و مُحدَث، اومیدم و بیم»): a word right before a typed pause mark ends a phrase and
/// takes no ezafe; a written kasra keeps it. Training labels had one there («به خواب، دو چشم» xabe1, «مَرد، اَحوَل»
/// m/rde1). A mark typed against the next word («گفت !هر») belongs to the word before it. Returns a new list; a line
/// whose marks do not line up with its words is left as it is.
List<String> noEzafeBeforePause(String line, List<String> words, List<String> plain, List<String> pw) {
  final spaced = line.split('').map((ch) => (_shortMarks + _longMarks).contains(ch) ? ' $ch ' : ch).join();
  final marks = punctuationAfterWords(spaced);
  if (marks.length != pw.length) return List<String>.from(pw);
  return [
    for (var i = 0; i < pw.length; i++)
      (marks[i].isNotEmpty && !writtenEzafe(words[i])) ? stripEzafe(pw[i], plain[i]) : pw[i],
  ];
}

/// A standalone «و» is read v/ (va) in prose, at the start of a line and after a pause mark, as Persian reads it
/// there; inside a line of verse it stays the metre's o. A label that does not line up with the text's words is left
/// as it is. Returns a new list.
List<String> readVav(String line, List<String> pw, bool prose) {
  final words = G2P.words(line);
  if (words.length != pw.length) return List<String>.from(pw);
  final marks = punctuationAfterWords(line);
  final afterMark = [
    false,
    ...(marks.length == words.length
        ? [for (var i = 0; i + 1 < marks.length; i++) marks[i].isNotEmpty]
        : List.filled(words.isNotEmpty ? words.length - 1 : 0, false)),
  ];
  return [
    for (var i = 0; i < words.length; i++)
      (words[i] == _vav && _vavMidVerse.contains(pw[i]) && (prose || i == 0 || afterMark[i])) ? 'v/' : pw[i],
  ];
}
