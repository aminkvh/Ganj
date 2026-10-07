const _entities = {
  '&zwnj;': '‌',
  '&zwj;': '‍',
  '&rlm;': '‏',
  '&lrm;': '‎',
  '&shy;': '­',
  '&laquo;': '«',
  '&raquo;': '»',
  '&nbsp;': ' ',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&lt;': '<',
  '&gt;': '>',
  '&hellip;': '…',
  '&ndash;': '–',
  '&mdash;': '—',
};

/// Plain text from Ganjoor's small HTML fragments (comments, excerpts, bios).
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  for (final e in _entities.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  // Numeric entities, decimal and hex; invalid code points are dropped instead of throwing.
  s = s.replaceAllMapped(RegExp(r'&#([xX][0-9a-fA-F]+|\d+);'), (m) {
    final raw = m[1]!;
    final hex = raw.startsWith('x') || raw.startsWith('X');
    final code = hex ? int.tryParse(raw.substring(1), radix: 16) : int.tryParse(raw);
    return code != null && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : '';
  });
  s = s.replaceAll('&amp;', '&');
  return s.split('\n').map((l) => l.replaceAll(RegExp('[ \t ]+'), ' ').trim()).where((l) => l.isNotEmpty).join('\n');
}
