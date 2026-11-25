import 'package:flutter_test/flutter_test.dart';

import '../../tool/podcast_auto_rules.dart';

const _cat = '/saadi/divan/ghazals';

Map<String, dynamic> _has(List<String> paths) => {
  for (final p in paths) p: ['g'],
};

void main() {
  final lines = {
    'sh1': 'اول دفتر به نام ایزد دانا',
    'sh2': 'ای نفس خرم باد صبا',
    'sh3': 'روی تو خوش می‌نماید آینهٔ ما',
    'sh4': 'ای نفس خرم باد بهار',
    'sh5': 'شب فراق',
  };
  Future<String?> poem(String title, List<String> targets, [List<String> current = const ['$_cat/sh9']]) => whyReview(
    catalog: 'poems',
    podcast: 'saadia',
    title: title,
    targets: targets,
    current: _has(current),
    storyNames: const {},
    firstLines: (_) async => lines,
  );
  Future<String?> story(String title, List<String> targets, {String podcast = 'khodemooni'}) => whyReview(
    catalog: 'shahnameh',
    podcast: podcast,
    title: title,
    targets: targets,
    current: const {},
    storyNames: const {'sohrab': 'رستم و سهراب', 'khaqan': 'خاقان چین', 'farud': 'فرود سیاوش'},
    firstLines: (_) async => const {},
  );

  group('one poem', () {
    test('merges when the title quotes its first line', () async {
      expect(await poem('قسمت ۳: روی تو خوش می نماید آینه ما', ['$_cat/sh3']), isNull);
    });
    test('waits when the title does not quote it', () async {
      expect(await poem('غزل 3', ['$_cat/sh3']), isNotNull);
    });
    test('waits when another poem of the section begins the same way', () async {
      expect(await poem('ای نفس خرم باد صبا', ['$_cat/sh2']), isNotNull);
    });
    test('waits when the first line is too short to tell', () async {
      expect(await poem('شب فراق', ['$_cat/sh5']), isNotNull);
    });
    test('waits when the podcast already has an episode on it', () async {
      expect(await poem('روی تو خوش می‌نماید آینهٔ ما', ['$_cat/sh3'], ['$_cat/sh3']), isNotNull);
    });
    test('waits when it is in a section the podcast has not read from', () async {
      expect(await poem('روی تو خوش می‌نماید', ['$_cat/sh3'], ['/hafez/ghazal/sh1']), isNotNull);
    });
  });

  group('a range', () {
    final t = ['$_cat/sh11', '$_cat/sh12'];
    test('merges when the title states it and it carries on', () async {
      expect(await poem('غزل‌ ۱۱ تا ۱۲', t, ['$_cat/sh10']), isNull);
    });
    test('waits when it does not carry on, or differs from the title', () async {
      expect(await poem('غزل 11 تا 12', t, ['$_cat/sh9']), isNotNull);
      expect(await poem('غزل 11 تا 13', t, ['$_cat/sh10']), isNotNull);
      expect(await poem('ابیات 11 تا 12', t, ['$_cat/sh10']), isNotNull);
    });
    test('waits for an archive of poems already read', () async {
      expect(await poem('غزل 11 تا 12', t, ['$_cat/sh10', '$_cat/sh11', '$_cat/sh12']), isNotNull);
    });
  });

  group('a Shahnameh story', () {
    test('merges when its full name, and no other, is in the title', () async {
      expect(await story('اپیزود۵۶- رستم و خاقان چین', ['khaqan']), isNull);
    });
    test('waits otherwise', () async {
      expect(await story('رستم و خاقان', ['khaqan']), isNotNull);
      expect(await story('خاقان چین، رستم و سهراب', ['khaqan']), isNotNull);
      expect(await story('خاقان چین', ['khaqan', 'farud']), isNotNull);
      expect(await story('خاقان چین', ['farud']), isNotNull);
      expect(await story('پایان خاقان چین', ['khaqan']), isNotNull);
      expect(await story('خاقان چین', ['khaqan'], podcast: 'shahpod'), isNotNull);
    });
  });
}
