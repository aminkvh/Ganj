// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), helpers that give Dart strings the behaviour
// the Python reading code relies on (str.strip, str.split, unicodedata.normalize).

/// Characters Python's `str.strip()` / `str.split()` treat as whitespace.
bool isPyWhitespace(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    (c >= 0x1C && c <= 0x20) ||
    c == 0x85 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

/// Python `s.strip()`.
String pyStrip(String s) {
  var a = 0, b = s.length;
  while (a < b && isPyWhitespace(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && isPyWhitespace(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// Python `s.strip(chars)`.
String pyStripChars(String s, String chars) => pyRstripChars(pyLstripChars(s, chars), chars);

/// Python `s.lstrip(chars)`.
String pyLstripChars(String s, String chars) {
  var a = 0;
  while (a < s.length && chars.contains(s[a])) {
    a++;
  }
  return s.substring(a);
}

/// Python `s.rstrip(chars)`.
String pyRstripChars(String s, String chars) {
  var b = s.length;
  while (b > 0 && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(0, b);
}

/// Python `s.split()`: split on whitespace runs, no empty strings.
List<String> pySplitWs(String s) {
  final out = <String>[];
  var start = -1;
  for (var i = 0; i < s.length; i++) {
    if (isPyWhitespace(s.codeUnitAt(i))) {
      if (start >= 0) {
        out.add(s.substring(start, i));
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) out.add(s.substring(start));
  return out;
}

/// `s[a:b]` with Python's clamping (non-negative indices).
String pySlice(String s, int a, int b) {
  final x = a.clamp(0, s.length), y = b.clamp(0, s.length);
  return x >= y ? '' : s.substring(x, y);
}

// --- NFC for the Arabic block -------------------------------------------------------------------------------------
// Dart has no unicodedata. The reading text is Persian, so only canonical composition of the Arabic letters and the
// canonical ordering of Arabic marks are implemented (what NFC changes there); other scripts pass through unchanged.

const Map<int, List<int>> _decomp = {
  0x622: [0x627, 0x653],
  0x623: [0x627, 0x654],
  0x624: [0x648, 0x654],
  0x625: [0x627, 0x655],
  0x626: [0x64A, 0x654],
  0x6C0: [0x6D5, 0x654],
  0x6C2: [0x6C1, 0x654],
  0x6D3: [0x6D2, 0x654],
};

final Map<int, int> _comp = {for (final e in _decomp.entries) (e.value[0] << 16) | e.value[1]: e.key};

int _ccc(int c) {
  if (c >= 0x64B && c <= 0x652) return c - 0x64B + 27;
  if (c == 0x670) return 35;
  if (c == 0x618) return 30;
  if (c == 0x619) return 31;
  if (c == 0x61A) return 32;
  if (c == 0x655 || c == 0x656 || c == 0x65C || c == 0x65F) return 220;
  if ((c >= 0x610 && c <= 0x617) ||
      c == 0x653 ||
      c == 0x654 ||
      (c >= 0x657 && c <= 0x65B) ||
      c == 0x65D ||
      c == 0x65E) {
    return 230;
  }
  if (c == 0x6E3 || c == 0x6EA || c == 0x6ED) return 220;
  if ((c >= 0x6D6 && c <= 0x6DC) ||
      (c >= 0x6DF && c <= 0x6E2) ||
      c == 0x6E4 ||
      c == 0x6E7 ||
      c == 0x6E8 ||
      c == 0x6EB ||
      c == 0x6EC) {
    return 230;
  }
  return 0;
}

/// Python `unicodedata.normalize("NFC", s)` for Persian/Arabic text.
String nfc(String s) {
  var plain = true;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x610 && c <= 0x6ED) {
      plain = false;
      break;
    }
  }
  if (plain) return s;
  // decompose
  final cps = <int>[];
  for (final c in s.runes) {
    final d = _decomp[c];
    if (d != null) {
      cps.addAll(d);
    } else {
      cps.add(c);
    }
  }
  // canonical ordering: stable sort of each run of non-starters by combining class
  var i = 0;
  while (i < cps.length) {
    if (_ccc(cps[i]) == 0) {
      i++;
      continue;
    }
    var j = i;
    while (j < cps.length && _ccc(cps[j]) != 0) {
      j++;
    }
    final run = cps.sublist(i, j);
    final idx = List<int>.generate(run.length, (k) => k);
    idx.sort((a, b) {
      final d = _ccc(run[a]) - _ccc(run[b]);
      return d != 0 ? d : a - b;
    });
    for (var k = 0; k < run.length; k++) {
      cps[i + k] = run[idx[k]];
    }
    i = j;
  }
  // composition
  final out = <int>[];
  var starter = -1; // index in out of the last starter
  var lastCcc = 0;
  for (final c in cps) {
    final cc = _ccc(c);
    if (starter >= 0) {
      final blocked = out.length - 1 != starter && lastCcc >= cc;
      if (!blocked) {
        final comp = _comp[(out[starter] << 16) | c];
        if (comp != null) {
          out[starter] = comp;
          continue;
        }
      }
    }
    if (cc == 0) {
      starter = out.length;
      lastCcc = 0;
    } else {
      lastCcc = cc;
    }
    out.add(c);
  }
  return String.fromCharCodes(out);
}
