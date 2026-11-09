/// A guess at whether a hemistich with no language tag (offline packs) is Arabic, so the voice can skip it.
///
/// Precision comes first: Persian verse is full of Arabic loanwords, phrases and Quranic quotations, and a Persian
/// hemistich must essentially never be skipped. So the guess says Arabic only when
/// - nothing in the line is Persian: no پ چ ژ گ, no Persian ZWNJ use (می‌، ‌ها، ‌است…), no ۀ, no common Persian
///   word or verb form;
/// - it has at least one piece of strong Arabic evidence (an Arabic-only word such as هذا، اذا، لقد، علیک, an
///   Arabic verb or pronoun ending, tanwin ٌ ٍ, a word-initial أ or إ, or two final case vowels);
/// - and its overall Arabic score (ال words, function words, ة, tanwin, case vowels, less the Persian-or-Arabic
///   words) reaches [_kThreshold].
///
/// Tuned on 31,295 hemistichs from the Ganjoor API (Hafez's ghazals, Saadi, Rumi, Sanai and ten Persian poets):
/// no Persian hemistich flagged, about 39% of Arabic ones caught (about 70% when the text is vocalized). See
/// test/fixtures/voice/language_sample.json and tool/language_guess_eval.dart.
bool looksArabic(String hemistich) {
  if (_persianMarks.hasMatch(hemistich)) return false;
  final words = _normalize(hemistich).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return false;
  for (final w in words) {
    if (_persianLetters.hasMatch(w) || _persianWords.contains(w) || _persianVerb(w)) return false;
  }
  if (_strong(hemistich, words) < 1) return false;
  return _score(hemistich, words) >= _kThreshold;
}

const _kThreshold = 2.0;

/// ۀ, ه with hamza above (Persian ezafe), and «خوا» (خواستن، خواب، خوار…), none of them Arabic spelling.
final _persianMarks = RegExp('\u06C0|\u0647\u0654|خوا');
final _persianLetters = RegExp('[پچژگ]');
final _diacritics = RegExp('[\u064B-\u065F\u0670\u0640]');
final _miPrefix = RegExp('(^|\\s)(ن?می)\u200c');
final _zwnjSuffix = RegExp('\u200c(ها|های|هایی|ای|ام|ات|اش|اند|ایم|اید|است|ست|تر|ترین|شان|تان|مان|ی)(?=\\s|\$)');
final _nonArabicBlock = RegExp('[^\u0600-\u06FF]+');

/// Strips diacritics, unifies the Arabic and Persian forms of letters, and turns a Persian use of ZWNJ into پ (so
/// it vetoes like a Persian letter). Other ZWNJs (فی‌الحشر) become spaces.
String _normalize(String s) {
  var t = s.replaceAll(_diacritics, '');
  t = t
      .replaceAll('\u064A', '\u06CC') // ي
      .replaceAll('\u0649', '\u06CC') // ى
      .replaceAll('\u0643', '\u06A9') // ك
      .replaceAll('\u0623', '\u0627') // أ
      .replaceAll('\u0625', '\u0627') // إ
      .replaceAll('\u0671', '\u0627') // ٱ
      .replaceAll('\u0624', '\u0648') // ؤ
      .replaceAll('\u0626', '\u06CC') // ئ
      .replaceAll('\u0629', '\u0647'); // ة
  t = t.replaceAllMapped(_miPrefix, (m) => '${m[1]}پ');
  t = t.replaceAll(_zwnjSuffix, 'پ');
  t = t.replaceAll('\u200c', ' ');
  return t.replaceAll(_nonArabicBlock, ' ');
}

Set<String> _set(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

/// Common Persian words that Arabic text does not use: any one of them means the line is Persian.
final _persianWords = _set('''
آتش آرام آسمان آفتاب آن آنچه آنکه از ازو است امید اند اندر اندرون اندرین اوست اکنون اگر ایم این اینجا با باد
باده باز باغ باید ببین بخت بدان بدو بدین بر برای برین بستان بسیار بلند بهار بهتر بهر بوی بگو بیا بیار بیش تا
تازه تخت ترا تن توست تویی تیغ جام جان جای جز جهان خانه خاک خداوند خدای خرد خرم خسرو خشم خشک خود خورشید خوش
خون خویش دارد دارم داند دانش درد درو درون درین دست دل دلت دلش دلم ده دهان دو دوست دوش دگر دیر دیو دیگر را
راست راه رخ رنج ره روان روز روزی روشن روی ز زار زان زانک زانکه زبان زر زلف زمانه زمین زن زیر زین سخت سخن
سرای سرو شاخ شاد شادی شاه شاید شب شد شمع شه شهر شوم شوی شیر شیرین صد صدهزار غم فرو لیک لیکن ماه مباد مرا
مردم مرغ مست مشو منم مه مهمان موی مکن می میان نام نان نزد نشان نماید نمی نه نهان نو نوش نیز نیست نیک هر هرکه
هزار هست هفت همان همه همی همیشه هنر وان ور ورا ورنه وز وزو ولیکن وین چرا چه چو چون کار کاو کاین کجا کجاست
کجایی کز کس کسی کمر کنار کنم کنند کنون کنی که کوی یاد یار یکی
''');

const _past =
    'کرد شد بود داشت داد آمد رفت گفت دید خورد نهاد ساخت سوخت یافت افتاد ماند رسید خواست دانست نشست آورد کشید '
    'بست شکست ریخت خاست نمود';
const _present =
    'کن شو باش دار ده آی آ رو گوی گو بین زن خور ساز سوز یاب افت مان رس خواه دان نشین آور کش بند شکن ریز خیز نما بخش';

String _alt(String words) => (_set(words).toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');

/// A Persian verb form: a prefix (ن، ب، می، نمی، بر، در، فرو) on a verb stem, or a past stem, with its endings.
final _verbPrefixed = RegExp('^(ن|ب|نمی|می|بر|در|فرو)(${_alt('$_past $_present')})(م|ی|د|یم|ید|ند|ست|ه|ن|ندی|ستی)?\$');
final _verbPast = RegExp('^(${_alt(_past)})(م|ی|یم|ید|ند|ه|ن|ست|ستی)?\$');

/// Arabic words these patterns would take for Persian verbs (بِدارٍ، بینَ، زِدْ، بینی، بیّنة).
final _verbExceptions = _set('بدار بین زد بینی بینه');

bool _persianVerb(String w) => !_verbExceptions.contains(w) && (_verbPrefixed.hasMatch(w) || _verbPast.hasMatch(w));

/// Words that are Arabic or Persian (به، او، در، کان…): they lower the score.
final _shared = _set('او ای به بی تو در سر کان کن کو یک');

/// Arabic function words, the common ones Persian also uses (یا، لا، ما، من…) apart.
final _arabicWords = _set('''
اذ اذا اری الا التی الذی الذین الی الینا الیهم الیک الیکم اما انا انت انتم انما انه انها انک انکم انی ایا ایها بل
بها بهم بک بکم ثم حتی حیث دع ذا ذلک علی علینا علیهم علیک علیکم عن عنا عند عندی عنه عنهم عنک عنی عینی فان فقد
فما فی فینا فیه فیها فیهم فیک فیکم قال قد قلبی لست لقد لم لما لن لنا له لها لهم لو لولا لک لکم لی لیس متی مع
مما منا منه منها منهم منک منکم نحن هذا هذه هو هکذا هی ولا کل کیف یقول
''');
final _weakArabicWords = _set('ام ان لا ما من هم کان یا');

/// Arabic words Persian verse hardly ever borrows alone.
final _strongWords = _set('''
اذا التی الذی الذین الینا الیهم الیک الیکم انا انت انتم انما انک انکم ایا ایها بها بهم بک بکم ثم حتی حیث ذلک
علینا علیهم علیک علیکم عنا عند عندی عنه عنهم عنک عنی فان فما فینا فیه فیها فیهم فیک فیکم لست لقد لم لما لن لنا
لها لهم لولا لکم لیس متی مما منا منه منها منهم منک منکم هذا هذه هکذا کیف یقول
''');

/// Arabic verb and pronoun endings (یفعلون، فعلوا، علینا، علیکم، علیهم) and و/ف on a function word (فقد، ولا…).
final _strongPatterns = [
  RegExp(r'^(ی|ت)\S{2,}ون$'),
  RegExp(r'^\S{3,}وا$'),
  RegExp(r'^\S{3,}نا$'),
  RegExp(r'^\S{2,}کم$'),
  RegExp(r'^\S{2,}هم$'),
  RegExp(r'^(ف|و)(قد|لا|ما|من|فی|علی|ان|لو|اذا|لم|لن|هو|هی|انا|انت)$'),
];

final _alWord = RegExp('^(و|ف|ب|ل|ک)?(ال|لل).');
const _alNotArabic = {'الا', 'اله', 'الهی', 'الله', 'والله', 'بالله', 'لله', 'تالله'};
final _tanwinStrong = RegExp('[\u064C\u064D]'); // ٌ ٍ
final _tanwinFath = RegExp('\u064B(?!\u0627)'); // ً not before ا (once اً is taken out)
final _tanwinAlef = RegExp('\u0627\u064B|\u064B\u0627'); // اً, common in Persian adverbs (دائماً)
final _initialHamza = RegExp('(^|\\s)[\u0623\u0625\u0671]');
final _caseVowel = RegExp('[\u064E\u064F]\u0651?(?=[\\s،؟!.:؛]|\$)'); // final fatha or damma

int _count(RegExp r, String s) => r.allMatches(s).length;

int _caseVowels(String raw) => _count(_caseVowel, raw);

int _strong(String raw, List<String> words) {
  var n = 0;
  for (final w in words) {
    if (_strongWords.contains(w)) n++;
    if (_strongPatterns.any((p) => p.hasMatch(w))) n++;
  }
  n += _count(_tanwinStrong, raw) + _count(_initialHamza, raw);
  final cv = _caseVowels(raw);
  if (cv >= 2) n += cv;
  return n;
}

double _score(String raw, List<String> words) {
  var s = 0.0;
  for (final w in words) {
    if (_shared.contains(w)) s -= 2;
    if (_alWord.hasMatch(w) && !_alNotArabic.contains(w)) s += 0.5;
    if (_arabicWords.contains(w) || _weakArabicWords.contains(w)) s += 1;
  }
  s += _count(RegExp('\u0629'), raw); // ة
  s += 1.5 * (_count(_tanwinStrong, raw) + _count(_tanwinFath, raw.replaceAll('\u0627\u064B', '\u0627')));
  s += 0.5 * _count(_tanwinAlef, raw);
  s += _count(_initialHamza, raw);
  s += _caseVowels(raw);
  return s;
}
