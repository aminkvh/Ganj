/// Normalizes Persian/Arabic-script text for matching. Shared by the poet
/// filter, find-in-poem and (M3) full-text indexing — change with care.
String normalizePersian(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (_isHaraka(r) || r == 0x0640) continue; // harakat, tatweel
    switch (r) {
      case 0x064A: // ي
      case 0x0649: // ى
        b.writeCharCode(0x06CC); // ی
      case 0x0643: // ك
        b.writeCharCode(0x06A9); // ک
      case 0x06C0: // ۀ
      case 0x0629: // ة
        b.writeCharCode(0x0647); // ه
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        b.writeCharCode(0x0627); // ا
      case 0x0624: // ؤ
        b.writeCharCode(0x0648); // و
      case 0x200C: // ZWNJ
        b.writeCharCode(0x20);
      default:
        if (r >= 0x06F0 && r <= 0x06F9) {
          b.writeCharCode(0x30 + r - 0x06F0);
        } else if (r >= 0x0660 && r <= 0x0669) {
          b.writeCharCode(0x30 + r - 0x0660);
        } else {
          b.writeCharCode(r);
        }
    }
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _isHaraka(int r) => (r >= 0x064B && r <= 0x065F) || r == 0x0670;

/// True when [query] occurs in [text] after normalization, also comparing
/// with spaces removed so «مشکلها» finds «مشکل‌ها».
bool matchesQuery(String text, String query) {
  final q = normalizePersian(query);
  if (q.isEmpty) return false;
  final t = normalizePersian(text);
  return t.contains(q) || t.replaceAll(' ', '').contains(q.replaceAll(' ', ''));
}

/// Numbers follow the interface language: Persian digits in the Persian UI, Latin in
/// English. Set by `GanjApp` whenever the language changes (every screen rebuilds then).
bool latinNumbers = false;

String localDigits(Object n) => latinNumbers
    ? n.toString()
    : n.toString().replaceAllMapped(RegExp('[0-9]'), (m) => String.fromCharCode(0x06F0 + m[0]!.codeUnitAt(0) - 0x30));

/// A decimal number: «۱٫۵» in Persian, "1.5" in English.
String localDecimal(Object n) => latinNumbers ? '$n' : localDigits(n).replaceAll('.', '٫');

/// Normalization for the full-text index and its queries: like [normalizePersian], but a
/// half-space (ZWNJ) is dropped instead of becoming a space, so a word written with or
/// without its half-space is the same text.
String normalizeForIndex(String input) => normalizePersian(input.replaceAll('\u200c', ''));
