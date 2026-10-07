import 'dart:convert';

import 'persian_normalize.dart';

/// English forms of Ganjoor's Persian content for the English interface: poet names (a
/// bundled table), centuries, and the common genre and section words in titles. Anything
/// unknown — book names, first lines, the poems themselves — stays in Persian.
class EnglishContent {
  EnglishContent._(this._names, this._idByPersian);

  /// [names]: `assets/seed/poet_names_en.json`; [centuries]: the bundled poet list, used
  /// to find a poet from the Persian name inside a title path.
  factory EnglishContent.fromJson({required String names, required String centuries}) {
    final n = <int, (String, String)>{
      for (final e in (jsonDecode(names) as Map<String, dynamic>).entries)
        int.parse(e.key): ((e.value as Map)['nickname'] as String, (e.value as Map)['name'] as String),
    };
    final byPersian = <String, int>{};
    for (final c in jsonDecode(centuries) as List) {
      for (final p in (c as Map)['poets'] as List) {
        final id = (p as Map)['id'] as int;
        for (final k in [p['nickname'], p['name']]) {
          if (k is String && k.isNotEmpty) byPersian[normalizePersian(k)] = id;
        }
      }
    }
    return EnglishContent._(n, byPersian);
  }

  final Map<int, (String nickname, String name)> _names;
  final Map<String, int> _idByPersian;

  String? poetNickname(int id) => _names[id]?.$1;
  String? poetName(int id) => _names[id]?.$2;

  String? poetByPersian(String fa) {
    final id = _idByPersian[normalizePersian(fa.trim())];
    return id == null ? null : poetNickname(id);
  }

  /// A category or poem title: «غزل شمارهٔ ۱» → "Ghazal 1", «غزلیات» → "Ghazals".
  String title(String fa) {
    final t = fa.trim();
    final whole = _genres[t];
    if (whole != null) return whole;
    final numbered = _numbered.firstMatch(t);
    if (numbered != null) {
      final word = numbered.group(1)!.trim();
      final en = word.isEmpty ? 'No.' : _genres[word];
      if (en != null) return '$en ${_latin(numbered.group(2)!)}${numbered.group(3)!}';
    }
    final part = _part.firstMatch(t);
    if (part != null) return 'Part ${_latin(part.group(1)!)}${part.group(2)!}';
    return poetByPersian(t) ?? fa;
  }

  /// «حافظ » غزلیات » غزل شمارهٔ ۱» → "Hafez › Ghazals › Ghazal 1".
  String path(String fa) => fa.split('»').map((s) => title(s.trim())).join(' › ');

  /// «قرن هشتم» → "8th century AH" (Ganjoor's centuries are in the Islamic calendar).
  String century(String fa) {
    final n = _ordinals[fa.replaceFirst('قرن', '').trim()];
    if (n == null) return fa;
    final suffix = (n % 100 >= 11 && n % 100 <= 13)
        ? 'th'
        : switch (n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$n$suffix century AH';
  }

  static String _latin(String s) =>
      s.replaceAllMapped(RegExp('[۰-۹]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x06F0 + 0x30));

  static final _numbered = RegExp(r'^(.*?)\s*شمارهٔ\s*([۰-۹0-9]+)(.*)$');
  static final _part = RegExp(r'^بخش\s*([۰-۹0-9]+)(.*)$');

  static const _ordinals = {
    'اول': 1,
    'دوم': 2,
    'سوم': 3,
    'چهارم': 4,
    'پنجم': 5,
    'ششم': 6,
    'هفتم': 7,
    'هشتم': 8,
    'نهم': 9,
    'دهم': 10,
    'یازدهم': 11,
    'دوازدهم': 12,
    'سیزدهم': 13,
    'چهاردهم': 14,
    'پانزدهم': 15,
  };

  static const _genres = {
    'غزلیات': 'Ghazals',
    'غزل': 'Ghazal',
    'رباعیات': 'Quatrains',
    'رباعی': 'Quatrain',
    'قصاید': 'Qasidas',
    'قصائد': 'Qasidas',
    'قصیده': 'Qasida',
    'قطعات': 'Fragments',
    'قطعه': 'Fragment',
    'مثنویات': 'Masnavis',
    'مثنوی': 'Masnavi',
    'مثنوی معنوی': 'Masnavi-ye Ma\'navi',
    'ترجیعات': 'Tarji-bands',
    'ترجیع‌بند': 'Tarji-band',
    'ترجیع بند': 'Tarji-band',
    'ترکیبات': 'Tarkib-bands',
    'ترکیب‌بند': 'Tarkib-band',
    'ترکیب بند': 'Tarkib-band',
    'مسمطات': 'Mosammats',
    'مسمط': 'Mosammat',
    'مخمسات': 'Mokhammases',
    'مخمس': 'Mokhammas',
    'دوبیتی‌ها': 'Do-beytis',
    'دوبیتی': 'Do-beyti',
    'تک‌بیت‌ها': 'Single couplets',
    'تک بیت‌ها': 'Single couplets',
    'تک‌بیت': 'Single couplet',
    'مفردات': 'Single verses',
    'ملمعات': 'Macaronic poems',
    'اشعار منتسب': 'Attributed poems',
    'اشعار پراکنده': 'Scattered poems',
    'اشعار عربی': 'Arabic poems',
    'سایر اشعار': 'Other poems',
    'دیگر اشعار': 'Other poems',
    'دیوان': 'Divan',
    'دیوان اشعار': 'Collected poems',
    'گزیدهٔ اشعار': 'Selected poems',
    'منتخب اشعار': 'Selected poems',
    'ساقی‌نامه': 'Saqi-nameh',
    'ساقی نامه': 'Saqi-nameh',
    'شاهنامه': 'Shahnameh',
    'گلستان': 'Golestan',
    'بوستان': 'Bustan',
    'دیوان شمس': 'Divan-e Shams',
    'منطق‌الطیر': 'The Conference of the Birds',
    'منطق الطیر': 'The Conference of the Birds',
    'خمسه': 'Khamseh',
    'لیلی و مجنون': 'Layla and Majnun',
    'خسرو و شیرین': 'Khosrow and Shirin',
    'هفت پیکر': 'Haft Peykar',
    'مخزن الاسرار': 'Makhzan al-Asrar',
    'اسکندرنامه': 'Eskandar-nameh',
    'رباعیات خیام': 'Rubaiyat of Khayyam',
    'دیباچه': 'Preface',
    'مقدمه': 'Introduction',
    'مقدّمه': 'Introduction',
    'خاتمه': 'Epilogue',
    'باب': 'Chapter',
    'حکایت': 'Story',
    'فصل': 'Section',
    'نامه': 'Letter',
  };
}

/// The English content table while the interface is in English; null in Persian. Set by
/// `GanjApp` (every screen rebuilds when the language changes).
EnglishContent? englishContent;

/// A poet's short name in the interface language.
String localPoet(int id, String fa) => englishContent?.poetNickname(id) ?? fa;

/// A poet's full name in the interface language.
String localPoetFull(int id, String fa) => englishContent?.poetName(id) ?? fa;

/// A category or poem title in the interface language (as far as it can be translated).
String localTitle(String fa) => englishContent?.title(fa) ?? fa;

/// A «poet » section » poem» path in the interface language.
String localPath(String fa) => englishContent?.path(fa) ?? fa;

String localCentury(String fa) => englishContent?.century(fa) ?? fa;
