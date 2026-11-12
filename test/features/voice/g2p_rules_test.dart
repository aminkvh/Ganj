// The reading rules of Ganj voice 1.2.0: one test for each test added to packages/ganj-reading/tests/test_g2p.py in
// Ganj voice 89d4add, with the same inputs and expected strings.

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/reading/g2p.dart';

/// The Python tests' FakeModel: a line's output from a table (a list is the n best, best first), '' if absent.
class _TableModel implements G2pModel {
  _TableModel(this.table);
  final Map<String, Object> table;

  @override
  String top1(String text) {
    final v = table[text] ?? '';
    return v is List<String> ? v.first : v as String;
  }

  @override
  List<String> nbest(String text, int n) {
    final v = table[text] ?? '';
    return v is List<String> ? List<String>.from(v) : [v as String];
  }
}

/// A G2P over [table] with no lexicon, or with the shipped one ([shipped]).
G2P _g2p(Map<String, Object> table, {bool shipped = false}) =>
    shipped ? G2P(_TableModel(table)) : G2P(_TableModel(table), lexicon: const {});

const _hazaj = 'مفاعیلن مفاعیلن فعولن (هزج مسدس محذوف یا وزن دوبیتی)';
const _mojtass = 'مفاعلن فعلاتن مفاعلن فعلن (مجتث مثمن مخبون محذوف)';

void main() {
  test('the shipped lexicon reads bebod as was', () {
    // Ruled 2026-11-09: «ببد شاه یک ماه در نیمروز» is bebod; every fine-tune wrote beb/d
    expect(_g2p({'ببد شاه': r'beb/d $ah'}, shipped: true).phonemizeLine('ببد شاه'), 'bebod šah');
  });

  test('a word written with ye-ast is read ist', () {
    // Ruled 2026-11-09: «که هر خاری به تسبیحش زبانی‌است» is z/banist; the models wrote z/bani/st
    expect(_g2p({'زبانی‌است': 'z/bani/st'}).phonemizeLine('زبانی‌است'), 'z/banist');
    expect(_g2p({'تسبیح‌خوانی‌است': 't/sbihxani@/st'}).phonemizeLine('تسبیح‌خوانی‌است'), 't/sbihxanist');
  });

  test('ye-ast after a one-letter stem keeps its ast', () {
    // نی‌است, کی‌است: ney / key + ast; nist would be "is not"
    expect(_g2p({'نی‌است': 'ni/st'}).phonemizeLine('نی‌است'), 'ni/st');
    expect(_g2p({'کی‌است': 'key/st'}).phonemizeLine('کی‌است'), 'key/st');
    expect(contractAst(['نی‌است'], ['ni/st'], null), ['ni/st']);
  });

  test('ye-ast is read ist in a metre and keeps its ast where only that scans', () {
    var line = 'که هر خاری به تسبیحش زبانی‌است';
    var g = _g2p({
      line: [r'ke h/r xari be t/sbih/$ z/bani/st'],
    });
    expect(g.phonemizeLine(line, _hazaj), 'ke h/r xari be t/sbih/š z/banist');
    line = 'زبانی‌است به مرا که می زرا به کما';
    g = _g2p({
      line: ['z/bani/st be mara ke mi z/ra be k/ma'],
    });
    expect(g.phonemizeLine(line, _mojtass), 'z/bani/st be mara ke mi z/ra be k/ma');
  });

  test('the shipped lexicon reads the marked mohdas as mohdas', () {
    // «تا کی ز قدیم و مُحدَث»: mohd/s, for the metre; the model wrote moh/dd/s
    expect(
      _g2p({'جهان چه محدث': 'j/han ce moh/dd/s'}, shipped: true).phonemizeLine('جهان چه مُحدَث'),
      'j/han ce mohd/s',
    );
    // only the marked spelling: an unmarked محدث stays the model's (mohaddes, the hadith narrator)
    expect(
      _g2p({'جهان چه محدث': 'j/han ce moh/ddes'}, shipped: true).phonemizeLine('جهان چه محدث'),
      'j/han ce moh/ddes',
    );
  });

  test('no ezafe right before a typed pause mark', () {
    // a word before ، ؛ : ! ؟ ends a phrase, so it takes no ezafe
    expect(_g2p({'به خواب دو چشم': 'be xabe1 do c/šm'}).phonemizeLine('به خواب، دو چشم'), 'be xab do c/šm');
    expect(
      _g2p({'نوشت این مرد آزادی': 'nevešt @in m/rde1 @azadi'}).phonemizeLine('نوشت این مرد: آزادی'),
      'nevešt @in m/rd @azadi',
    );
    expect(_g2p({'حیف استاد': 'heyfe1 @ostad'}).phonemizeLine('حیف! اُستاد'), 'heyf @ostad');
    expect(_g2p({'کار این کار': 'kare1 @in kar'}).phonemizeLine('کار ، این کار'), 'kar @in kar'); // typed apart
    expect(_g2p({'خواب دو چشم': 'xabe1 do c/šm'}).phonemizeLine('خواب،دو چشم'), 'xab do c/šm'); // typed together
    expect(_g2p({'ماه روزه': 'mahe1 ruze'}).phonemizeLine('ماه روزه'), 'mahe1 ruze'); // no mark: the ezafe stays
  });

  test('a mark typed at the start of the next word belongs to the word before it', () {
    expect(_g2p({'گفت هر کس': 'gofte1 h/r k/s'}).phonemizeLine('گفت !هر کس'), 'goft h/r k/s');
    expect(_g2p({'گفت هر کس': 'gofte1 hore1 k/s'}).phonemizeLine('گفت !هر کس'), 'goft hore1 k/s');
  });

  test('a written kasra keeps its ezafe before a pause mark', () {
    expect(_g2p({'دل من': 'dele1 m/n'}).phonemizeLine('دلِ، من'), 'dele1 m/n');
  });

  test('the marked mohdas before a comma is read without ezafe', () {
    // 145660-c1: the lexicon keeps the model's ezafe; the pause mark then drops it
    const line = 'تا کی ز قدیم و مُحدَث، اومیدم و بیم';
    final g = _g2p({'تا کی ز قدیم و محدث اومیدم و بیم': 'ta key ze q/dim o mohd/se1 @umid/m o bim'}, shipped: true);
    expect(g.phonemizeLine(line), 'ta key ze q/dim o mohd/s @umid/m o bim');
  });

  test('harakatAgrees agrees with the diphthongs and long vowels the marks write', () {
    expect(harakatAgrees('مَی', 'mey') && harakatAgrees('هَیجا', 'heyja') && harakatAgrees('حَیوان', 'heyvan'), isTrue);
    expect(harakatAgrees('دَولت', 'dol/t'), isTrue); // the ow of a bare و is o
    expect(harakatAgrees('کَندَه', 'k/nde'), isTrue); // fatha before a final ه: its e
    expect(harakatAgrees('کَرِیم', 'k/rim') && harakatAgrees('نُور', 'nur') && harakatAgrees('لَدَی', 'l/da'), isTrue);
    expect(!harakatAgrees('بَیان', 'beyan') && harakatAgrees('بَیان', 'b/yan'), isTrue); // ی before ا is a consonant
    expect(!harakatAgrees('مِی', 'mi') && harakatAgrees('مِی', 'mey'), isTrue); // the kasra is written
  });

  test('follow marks swaps the vowel after a marked letter', () {
    // Ruled 2026-11-11: when no candidate reads the marks, the chosen one is made to
    expect(followMarks('انگِشت', '@/ngošt'), '@/ngešt');
    expect(followMarks('گُرسَنه', 'gorsene'), 'gors/ne');
    expect(followMarks('بُد', 'b/d'), 'bod');
    expect(followMarks('مَلِکِ', 'molke1'), 'm/leke1'); // the ezafe stays
    expect(followMarks('شَنگُل', 'š/ng/l'), 'š/ngol');
    expect(followMarks('شَمیرانُ', 'š/miran'), 'š/mirano'); // a missing vowel is added
    expect(followMarks('دَور', 'dur'), 'dor');
  });

  test('follow marks drops the vowel after a sukun and shortens an unwritten long vowel', () {
    expect(followMarks('خِفتانْشْ', 'x/ftan/š'), 'xeftanš');
    expect(followMarks('نتْوان', 'n/t/van'), 'n/tvan');
    expect(followMarks('بِپْسَندی', 'bepsandi'), 'beps/ndi');
    expect(followMarks('بِرَفت', 'beraft'), 'ber/ft');
    expect(followMarks('مُلْکاً', 'm/lek/n'), 'molk/n'); // with its tanwin
  });

  test('follow marks reads mey and va', () {
    expect(followMarks('مِی', 'mi'), 'mey');
    expect(followMarks('مِی‌پرستی', 'mip/r/sti'), 'meyp/r/sti');
    expect(followMarks('وَ', 'o'), 'v/');
  });

  test('follow marks leaves Arabic long vowels and what it cannot place', () {
    expect(followMarks('لَدَی', 'l/da'), 'l/da'); // the final ی read a
    expect(followMarks('إِلَی', '@ela'), '@ela');
    expect(followMarks('فِی', 'fi'), 'fi');
    expect(followMarks('کِی', 'ki'), 'ki');
    expect(followMarks('کَندَه', 'k/nde'), 'k/nde');
    expect(followMarks('بِشَوی', 'bešuy'), 'bešuy'); // و ی inside a word cannot be placed
  });

  test('follow marks reads a final mark unless it runs into the next word', () {
    expect(followMarks('جَرَّبَ', 'jorrbo'), 'j/rr/b/'); // an Arabic case ending
    expect(followMarks('خَطُّ', 'x/tt', lastVowel: false), 'x/tt'); // «خَطُّ و خال»: the و's o
    expect(followMarks('گُلَ', 'gol', lastVowel: false), 'gol'); // «گُلَ انْدَر»: run into the alef
  });

  test('a line whose candidates all misread a mark follows the mark', () {
    final g = _g2p({'فروزنده اخگر چون انگشت کرد': r'foruz/nde @/xg/r con @/ngo$t k/rd'});
    expect(g.phonemizeLine('فروزنده اخگر چون انگِشت کرد'), 'foruz/nde @/xg/r con @/ngešt k/rd');
    expect(_g2p({'گرسنه خفتد': 'gorsene xoft/d'}).phonemizeLine('گُرسَنه خفتَد'), 'gors/ne xoft/d');
  });

  test('a final mark before vav or an alef is left to the next word', () {
    expect(_g2p({'خط و خال': 'x/tt o xal'}).phonemizeLine('خَطُّ و خال'), 'x/tt o xal');
    expect(_g2p({'گل از دست': 'gol @/z d/st'}).phonemizeLine('گُلَ ازْ دست'), 'gol @/z d/st');
  });
}
