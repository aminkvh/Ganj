// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-corpus/ganj_corpus/pauses.py.

import 'g2p.dart';
import 'pystr.dart';
import 'tokens.dart';

/// Pause tokens in the labels: a model that reads the words right can still stop in the wrong places and run words
/// together that should be kept apart. At reading time the tokens are placed by rule ([ruleTokens]), so where the
/// voice stops is decided, not guessed.
///
/// Tokens sit between words (" ⟨S⟩ ") or straight before the hemistich mark ("w⟨L⟩ + hemistich mark"); they are private-use code
/// points outside the style/metre range.
const String pauseShort = '\uE100';
const String pauseLong = '\uE101';

/// Style and metre tokens (all private-use code points U+E000..U+E0FF) that open a label.
bool _isPrefixChar(int c) => c >= 0xE000 && c <= 0xE0FF;

/// (prefix of style/metre tokens, [[words of each hemistich]]).
(String, List<List<String>>) splitLabel(String ph) {
  var k = 0;
  while (k < ph.length && _isPrefixChar(ph.codeUnitAt(k))) {
    k++;
  }
  return (ph.substring(0, k), [for (final part in ph.substring(k).split(tokHemi)) part.split(' ')]);
}

/// Put toks[i] ('' or a pause token) at the i-th word boundary of the label, counted across hemistichs.
String markPauses(String ph, List<String> toks) {
  final (prefix, lines) = splitLabel(ph);
  final total = lines.fold<int>(0, (a, w) => a + w.length);
  if (toks.length != total - 1) {
    throw ArgumentError('${toks.length} boundaries given for $total words');
  }
  var it = 0;
  final out = <String>[];
  for (var li = 0; li < lines.length; li++) {
    final words = lines[li];
    var s = words[0];
    for (final w in words.sublist(1)) {
      final t = toks[it++];
      s += (t.isNotEmpty ? ' $t ' : ' ') + w;
    }
    if (li < lines.length - 1) s += toks[it++];
    out.add(s);
  }
  return prefix + out.join(tokHemi);
}

String stripPauses(String ph) {
  for (final t in [pauseShort, pauseLong]) {
    ph = ph.replaceAll(' $t ', ' ').replaceAll(t, '');
  }
  return ph;
}

bool _blank(String l) => pyStrip(l).isEmpty;

/// Reading-time pauses: long at every hemistich break and after . ! ؟, short after ، ؛ : and nowhere else.
List<String> ruleTokens(List<String> lines) {
  lines = [
    for (final l in lines)
      if (!_blank(l)) l,
  ];
  final toks = <String>[];
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    final n = G2P.words(line).length;
    var marks = punctuationAfterWords(line);
    if (marks.length != n) marks = List.filled(n, '');
    for (var i = 0; i + 1 < marks.length; i++) {
      final m = marks[i];
      toks.add(m.split('').any(longMarks.contains) ? pauseLong : (m.isNotEmpty ? pauseShort : ''));
    }
    if (li < lines.length - 1) toks.add(pauseLong);
  }
  return toks;
}

/// A reading label with [ruleTokens]; when the label's words do not line up with the text's, only the hemistich breaks
/// get their long pause (a line must never run on into the next).
String ruleLabel(String ph, List<String> lines) {
  try {
    return markPauses(ph, ruleTokens(lines));
  } on ArgumentError {
    final (prefix, parts) = splitLabel(ph);
    return prefix + parts.map((words) => words.join(' ')).join(pauseLong + tokHemi);
  }
}

/// The label a line is read with: with [va], the «و» rule ([readVav]) on each hemistich whose words line up; with
/// [pauses] (a voice trained with the pause tokens), the reading-time pauses ([ruleLabel]).
String readingLabel(String ph, List<String> lines, {required bool prose, bool pauses = true, bool va = false}) {
  lines = [
    for (final l in lines)
      if (!_blank(l)) l,
  ];
  if (va) {
    final (prefix, parts) = splitLabel(ph);
    if (parts.length == lines.length) {
      ph = prefix + [for (var i = 0; i < lines.length; i++) readVav(lines[i], parts[i], prose).join(' ')].join(tokHemi);
    }
  }
  return pauses ? ruleLabel(ph, lines) : ph;
}
