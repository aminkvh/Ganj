import '../poem/couplets.dart';

/// What to feed the machine translator for a beyt. Ganjoor's plain-Persian meaning (when it
/// has one) is modern prose and translates far better than a classical verse; the verse is
/// used only when there is no meaning.
class TranslationSource {
  const TranslationSource(this.text, {required this.fromMeaning});

  final String text;
  final bool fromMeaning;
}

TranslationSource translationSource(Couplet c) {
  final meaning = c.summary?.text.trim();
  return meaning != null && meaning.isNotEmpty
      ? TranslationSource(meaning, fromMeaning: true)
      : TranslationSource(c.text, fromMeaning: false);
}

/// The whole poem for Google Translate in the browser: one paragraph per beyt, meanings where
/// they exist, verses elsewhere.
String translationSourceForPoem(List<Couplet> couplets) => couplets.map((c) => translationSource(c).text).join('\n\n');
