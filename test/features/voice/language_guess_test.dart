import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/language_guess.dart';

void main() {
  // Hemistichs from the Ganjoor API with its own language tags (Arabic = languageId 2, Persian = null or 1),
  // balanced with the hard Persian cases: Arabic loanwords, phrases and Quranic words inside Persian lines.
  final fixture = jsonDecode(File('test/fixtures/voice/language_sample.json').readAsStringSync()) as Map;
  final items = [for (final e in fixture['items'] as List) (text: e['t'] as String, arabic: e['ar'] == 1)];

  test('the fixture holds both languages', () {
    expect(items.where((e) => e.arabic).length, greaterThan(100));
    expect(items.where((e) => !e.arabic).length, greaterThan(200));
  });

  test('no Persian hemistich is flagged as Arabic', () {
    final flagged = [
      for (final e in items)
        if (!e.arabic && looksArabic(e.text)) e.text,
    ];
    expect(flagged, isEmpty);
  });

  test('Arabic recall stays at its measured level', () {
    final arabic = items.where((e) => e.arabic).toList();
    final hit = arabic.where((e) => looksArabic(e.text)).length;
    final minRecall = (fixture['minRecall'] as num).toDouble();
    expect(hit / arabic.length, greaterThanOrEqualTo(minRecall), reason: '$hit of ${arabic.length}');
  });

  test('plain cases', () {
    expect(looksArabic('اَلا یا اَیُّهَا السّاقی اَدِرْ کَأساً و ناوِلْها'), isTrue);
    expect(looksArabic('که عشق آسان نمود اول ولی افتاد مشکل‌ها'), isFalse);
    expect(looksArabic(''), isFalse);
    expect(looksArabic('   '), isFalse);
  });
}
