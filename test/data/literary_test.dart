import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/literary/literary_devices.dart';
import 'package:ganj/features/poem/couplets.dart';

import '../support/fake_adapter.dart';
import 'extras_test.dart' show ex;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late GanjoorApi api;
  late FakeAdapter adapter;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    adapter = FakeAdapter({
      '/api/ganjoor/literary/stats/overview': ex('literary_overview.json'),
      '/api/ganjoor/literary/devices': ex('literary_devices.json'),
      '/api/ganjoor/literary/poem/2130/tags': ex('literary_tags_2130.json'),
      '/api/ganjoor/wordsums/9': ex('wordsums_9.json'),
      '/api/ganjoor/wordcounts/9': ex('wordcounts_9.json'),
    });
    api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
  });
  tearDown(() => db.close());

  test('poets with literary tags', () async {
    expect(await api.literaryPoets(), containsAll([2, 7]));
    expect(adapter.requests.single.queryParameters['includePoets'], 'true');
  });

  test('devices of a beyt: words from the verse, concepts and free text otherwise', () async {
    final tags = await api.literaryTags(2130);
    final catalog = {for (final d in await api.literaryDevices()) d.id: d};
    final poem = Poem.fromJson(jsonDecode(File('test/fixtures/poem_2130.json').readAsStringSync()));
    final couplets = groupCouplets(poem.verses);

    expect(devicesOf(couplets[0], tags, catalog), isEmpty);
    final second = devicesOf(couplets[1], tags, catalog);
    expect(second.map((d) => d.name), ['استعاره', 'کنایه', 'ایهام']);
    // «مستعارٌمنه» points at the third word of the first misra.
    expect(second[0].roles, [('مستعارٌمنه', 'نافه‌ای'), ('مستعارٌله', 'حلقه خوشبوی گیسوی معشوق')]);
    expect(second[1].roles.last, ('معنای دوم', 'به رنج و محنت افتادن'));
    expect(second[2].roles.first, ('واژه', 'بویِ'));
    // A span of two words; then a word of the second misra.
    final third = devicesOf(couplets[2], tags, catalog);
    expect(third[0].roles.first.$2, 'منزلِ جانان');
    expect(third[1].roles.first.$2, 'جَرَس');
    expect(tags.every((t) => t.fromCorpus), isTrue);
  });

  test('a word range outside the verse falls back to the concept', () async {
    final poem = Poem.fromJson(jsonDecode(File('test/fixtures/poem_2130.json').readAsStringSync()));
    final couplets = groupCouplets(poem.verses);
    final raw = (jsonDecode(ex('literary_tags_2130.json')) as List).cast<Map<String, dynamic>>();
    raw.first['parts'][0]['wordStart'] = 40;
    raw.first['parts'][0]['wordEnd'] = 41;
    adapter.routes['/api/ganjoor/literary/poem/2130/tags'] = jsonEncode(raw);
    final tags = await api.literaryTags(2130);
    final catalog = {for (final d in await api.literaryDevices()) d.id: d};
    expect(devicesOf(couplets[1], tags, catalog).first.roles.first, ('مستعارٌمنه', 'نافه'));
  });

  test('word frequency: totals, and words by rank with paging and a term', () async {
    expect(await api.wordSums(9), (total: 81806, unique: 9500));
    final words = await api.wordCounts(9, term: 'عشق', page: 2, pageSize: 30);
    expect(words.first.word, 'که');
    expect(words.first.rank, 1);
    final q = adapter.requests.last.queryParameters;
    expect(q, {'term': 'عشق', 'PageNumber': '2', 'PageSize': '30'});
  });

  test('a device newer than the cached list: the list is fetched again, the tag kept', () async {
    // Cache a list that lacks «کنایه» (3), which ghazal 1 uses.
    final full = ex('literary_devices.json');
    final old = (jsonDecode(full) as List).where((d) => (d as Map)['id'] != 3).toList();
    adapter.routes['/api/ganjoor/literary/devices'] = jsonEncode(old);
    await api.literaryDevices();
    adapter.routes['/api/ganjoor/literary/devices'] = full;

    final container = ProviderContainer(overrides: [ganjoorApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final key = (poemId: 2130, poetId: 2);
    final sub = container.listen(poemLiteraryProvider(key), (_, _) {});
    addTearDown(sub.close);
    final data = await container.read(poemLiteraryProvider(key).future);
    expect(data.catalog[3]?.name, 'کنایه');
    expect(adapter.requests.where((u) => u.path == '/api/ganjoor/literary/devices'), hasLength(2));
  });

  test('a known device: the cached list is enough', () async {
    final container = ProviderContainer(overrides: [ganjoorApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final key = (poemId: 2130, poetId: 2);
    final sub = container.listen(poemLiteraryProvider(key), (_, _) {});
    addTearDown(sub.close);
    final data = await container.read(poemLiteraryProvider(key).future);
    expect(data.tags, hasLength(5));
    expect(adapter.requests.where((u) => u.path == '/api/ganjoor/literary/devices'), hasLength(1));
  });

  test('poets Ganjoor has not tagged: neither tags nor devices are asked for', () async {
    final container = ProviderContainer(overrides: [ganjoorApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final key = (poemId: 2130, poetId: 9999);
    final sub = container.listen(poemLiteraryProvider(key), (_, _) {});
    addTearDown(sub.close);
    expect((await container.read(poemLiteraryProvider(key).future)).tags, isEmpty);
    expect(adapter.requests.map((u) => u.path), ['/api/ganjoor/literary/stats/overview']);
  });
}
