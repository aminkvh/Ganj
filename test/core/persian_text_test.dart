import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/labeled_text.dart';
import 'package:ganj/core/text/persian_normalize.dart';

void main() {
  group('normalizePersian', () {
    test('unifies Arabic letter variants', () {
      expect(normalizePersian('كتاب علي'), 'کتاب علی');
      expect(normalizePersian('خانۀ رحمة'), 'خانه رحمه');
      expect(normalizePersian('أمر إذن ٱلله مؤمن'), 'امر اذن الله مومن');
    });
    test('strips harakat and tatweel', () {
      expect(normalizePersian('اَلا یا اَیُّهَا السّاقی'), 'الا یا ایها الساقی');
      expect(normalizePersian('ســـلام'), 'سلام');
    });
    test('ZWNJ becomes space, whitespace collapses', () {
      expect(normalizePersian('مشکل‌ها   و  دل'), 'مشکل ها و دل');
    });
    test('Persian and Arabic digits become Latin', () {
      expect(normalizePersian('۱۲۳ ١٢٣'), '123 123');
    });
  });

  group('matchesQuery', () {
    test('matches across ZWNJ, diacritics and Arabic letters', () {
      const verse = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';
      expect(matchesQuery(verse, 'مشکلها'), isTrue);
      expect(matchesQuery(verse, 'اول ولي'), isTrue);
      expect(matchesQuery(verse, 'ساقی'), isFalse);
    });
  });

  test('localDigits', () {
    expect(localDigits(1403), '۱۴۰۳');
  });

  group('LabeledText.parse', () {
    test('strips AI prefix and flags it', () {
      final t = LabeledText.parse('هوش مصنوعی: مرا در تابوت چوبی قرار دهید')!;
      expect(t.isAi, isTrue);
      expect(t.text, 'مرا در تابوت چوبی قرار دهید');
    });
    test('human text is kept as-is', () {
      final t = LabeledText.parse('هان ای ساقی')!;
      expect(t.isAi, isFalse);
      expect(t.text, 'هان ای ساقی');
    });
    test('null and blank give null', () {
      expect(LabeledText.parse(null), isNull);
      expect(LabeledText.parse('  '), isNull);
    });
  });

  test('language names cover Arabic', () {
    expect(verseLanguageNames[2], 'عربی');
  });
}
