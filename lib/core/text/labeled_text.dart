const _aiPrefix = 'هوش مصنوعی:';

/// Text from the API that may be AI-generated; Ganjoor marks those with a prefix.
class LabeledText {
  const LabeledText(this.text, {this.isAi = false});

  final String text;
  final bool isAi;

  static LabeledText? parse(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;
    if (t.startsWith(_aiPrefix)) {
      return LabeledText(t.substring(_aiPrefix.length).trim(), isAi: true);
    }
    return LabeledText(t);
  }
}

/// Ganjoor language ids (/api/translations/languages) shown as verse badges; 1 (fa) gets none.
const Map<int, String> verseLanguageNames = {2: 'عربی', 3: 'ترکی', 4: 'کردی', 5: 'مازندرانی', 6: 'گیلکی', 7: 'اصفهانی'};
