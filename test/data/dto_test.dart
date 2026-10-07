import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/cat.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/dto/poet.dart';

import '../support/fixtures.dart';

void main() {
  test('centuries: pinned group first, absolute image urls', () {
    final cs = [for (final c in jsonDecode(fx('centuries')) as List) Century.fromJson(c as Map<String, dynamic>)];
    expect(cs, hasLength(13));
    expect(cs.first.id, 0);
    expect(cs.first.poets, hasLength(10));
    final hafez = cs.first.poets.firstWhere((p) => p.id == 2);
    expect(hafez.rootCatId, 9);
    expect(hafez.imageAbsoluteUrl, 'https://api.ganjoor.net/api/ganjoor/poet/image/hafez.gif');
    expect(cs[1].name, 'قرن سوم');
  });

  test('poet page: root category with children and poems', () {
    final pc = PoetCat.fromJson(jsonDecode(fx('poet_2')) as Map<String, dynamic>);
    expect(pc.poet.name, 'حافظ شیرازی');
    expect(pc.cat.id, 9);
    expect(pc.cat.ancestors, isEmpty);
    expect(pc.cat.children, hasLength(5));
    expect(pc.cat.children.first.title, 'غزلیات');
    expect(pc.cat.children.first.fullUrl, '/hafez/ghazal');
    expect(pc.cat.poems, hasLength(3));
  });

  test('category: ancestors and poem refs with excerpts', () {
    final pc = PoetCat.fromJson(jsonDecode(fx('cat_24')) as Map<String, dynamic>);
    expect(pc.cat.title, 'غزلیات');
    expect(pc.cat.ancestors.single.id, 9);
    expect(pc.cat.poems.first.id, 2130);
    expect(pc.cat.poems.first.excerpt, startsWith('اَلا یا'));
  });

  test('poem 2130: verses, Arabic badge, metre, rhyme, navigation', () {
    final p = poem2130();
    expect(p.title, 'غزل شمارهٔ ۱');
    expect(p.siteUrl, 'https://ganjoor.net/hafez/ghazal/sh1');
    expect(p.verses, hasLength(14));
    expect(p.verses.first.vOrder, 1);
    expect(p.verses.first.languageName, 'عربی');
    expect(p.verses.first.summary!.isAi, isFalse);
    expect(p.verses[1].position, VersePosition.left);
    expect(p.metre, 'مفاعیلن مفاعیلن مفاعیلن مفاعیلن (هزج مثمن سالم)');
    expect(p.rhyme, 'لها');
    expect(p.next!.id, 2131);
    expect(p.previous, isNull);
    expect(p.category!.poet.id, 2);
    expect(p.category!.cat.id, 24);
  });

  test('poem 77000: paragraph line, AI summaries, empty rhyme is null', () {
    final p = poem77000();
    expect(p.verses.last.position, VersePosition.paragraph);
    expect(p.verses.last.coupletIndex, 6);
    expect(p.verses.first.summary!.isAi, isTrue);
    expect(p.summary!.isAi, isTrue);
    expect(p.rhyme, isNull);
    expect(p.previous!.id, 71237);
  });
}
