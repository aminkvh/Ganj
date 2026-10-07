import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';

EnglishContent loadContent() => EnglishContent.fromJson(
  names: File('assets/seed/poet_names_en.json').readAsStringSync(),
  centuries: File('assets/seed/centuries.json').readAsStringSync(),
);

void main() {
  final en = loadContent();

  test('poets get their English names, by id or by their Persian name', () {
    expect(en.poetNickname(2), 'Hafez');
    expect(en.poetNickname(5), 'Rumi');
    expect(en.poetByPersian('حافظ'), 'Hafez');
    expect(en.poetByPersian('ناشناس'), isNull);
  });

  test('genre and section names are translated, poem numbers kept', () {
    expect(en.title('غزلیات'), 'Ghazals');
    expect(en.title('رباعیات'), 'Quatrains');
    expect(en.title('غزل شمارهٔ ۱'), 'Ghazal 1');
    expect(en.title('رباعی شمارهٔ ۱۲'), 'Quatrain 12');
    expect(en.title('بخش ۱۲ - آغاز کتاب'), 'Part 12 - آغاز کتاب');
    expect(en.title('گلشن راز'), 'گلشن راز'); // unknown names stay as they are
  });

  test('a full path reads in English where it can', () {
    expect(en.path('حافظ » غزلیات » غزل شمارهٔ ۱'), 'Hafez › Ghazals › Ghazal 1');
  });

  test('centuries are numbered, in the Islamic calendar', () {
    expect(en.century('قرن هشتم'), '8th century AH');
    expect(en.century('قرن سوم'), '3rd century AH');
    expect(en.century('قرن یازدهم'), '11th century AH');
    expect(en.century('قرن چهاردهم'), '14th century AH');
  });
}
