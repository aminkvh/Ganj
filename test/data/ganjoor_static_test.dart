import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/literary.dart';
import 'package:ganj/data/api/dto/people.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/api/ganjoor_static.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/local_poetry.dart';
import 'package:ganj/data/repo/poetry_repository.dart';
import 'package:ganj/features/literary/literary_devices.dart';
import 'package:ganj/features/poem/couplets.dart';

import '../support/fake_adapter.dart';
import '../support/static_fixtures.dart';
import 'extras_test.dart' show ex;

/// Like jsDelivr at times: a 403 for the compressed copy of a file, the file itself for an
/// uncompressed request.
class _GzipRefusing extends FakeAdapter {
  _GzipRefusing(super.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (o.headers['Accept-Encoding'] != 'identity') {
      requests.add(o.uri);
      return Future.value(ResponseBody.fromString('Package size exceeded the configured limit of 50 MB.', 403));
    }
    return super.fetch(o, requestStream, cancelFuture);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDb db;
  late FakeAdapter cdn;
  late FakeAdapter server;
  late GanjoorStatic copy;

  GanjoorApi api({bool withCopy = true}) => GanjoorApi(
    dio: createDio(adapter: server),
    cache: HttpCache(db),
    staticCopy: withCopy ? copy : null,
  );

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    cdn = FakeAdapter(staticRoutes());
    server = FakeAdapter({
      ...fixtureRoutes(),
      '/api/locations': '[{"id":1,"name":"شیراز","latitude":29.5,"longitude":52.5}]',
      '/api/ganjoor/literary/devices': ex('literary_devices.json'),
      '/api/ganjoor/literary/poem/2130/tags': ex('literary_tags_2130.json'),
      '/api/ganjoor/cat/39/geotag': File('test/fixtures/shahnameh/geotag_39.json').readAsStringSync(),
    });
    copy = GanjoorStatic(
      dio: createDio(adapter: cdn),
      cache: HttpCache(db),
    );
  });
  tearDown(() => db.close());

  Iterable<String> cdnPaths() => cdn.requests.map((u) => u.path.substring(staticPrefix.length));

  group('poems from the static copy', () {
    test('a ghazal: verses, meanings, metre, rhyme, summary, category and neighbours', () async {
      final p = await copy.poem(2130);
      expect(p.title, 'غزل شمارهٔ ۱');
      expect(p.fullTitle, 'حافظ » غزلیات » غزل شمارهٔ ۱');
      expect(p.fullUrl, '/hafez/ghazal/sh1');
      expect(p.verses, hasLength(14));
      expect(p.verses.map((v) => v.position).take(2), [VersePosition.right, VersePosition.left]);
      expect(p.verses.map((v) => v.coupletIndex).take(4), [0, 0, 1, 1], reason: 'couplets count from 0, like the API');
      expect(p.verses.first.summary?.text, startsWith('ای ساقی!'));
      expect(p.verses[1].summary, isNull);
      expect(p.summary?.text, startsWith('در این شعر حافظ'));
      expect(p.metre, 'مفاعیلن مفاعیلن مفاعیلن مفاعیلن (هزج مثمن سالم)');
      expect(p.rhyme, 'لها');
      expect(p.recitations, isEmpty);
      expect(p.previous, isNull);
      expect((p.next?.id, p.next?.title, p.next?.urlSlug), (2131, 'غزل شمارهٔ ۲', 'sh2'));
      final c = p.category!;
      expect((c.poet.id, c.poet.name, c.poet.nickname, c.poet.rootCatId), (2, 'حافظ شیرازی', 'حافظ', 9));
      expect(c.poet.imageUrl, '/api/ganjoor/poet/image/hafez.gif', reason: 'a site path, as the API gives it');
      expect((c.poet.birthYear, c.poet.deathYear), (726, 792));
      expect((c.cat.id, c.cat.title, c.cat.fullUrl), (24, 'غزلیات', '/hafez/ghazal'));
      expect([for (final a in c.cat.ancestors) (a.id, a.title, a.urlSlug)], [(9, 'حافظ', 'hafez')]);
      // The metre was in the file: the metre table isn't needed.
      expect(cdnPaths(), isNot(contains('/metres.json')));
    });

    test('reads the same couplets as the API copy of the poem', () async {
      final fromCopy = groupCouplets((await copy.poem(2130)).verses);
      final fromApi = groupCouplets(poem2130().verses);
      expect(fromCopy.map((c) => c.index), fromApi.map((c) => c.index));
      expect(fromCopy.map((c) => c.verses.length), fromApi.map((c) => c.verses.length));
    });

    test('prose and verse: paragraphs keep their position; the metre comes from the metre table', () async {
      final p = await copy.poem(41294);
      expect(p.verses.first.position, VersePosition.paragraph);
      expect(p.verses.map((v) => v.position).toSet(), {
        VersePosition.paragraph,
        VersePosition.right,
        VersePosition.left,
      });
      expect(p.metre, 'مفتعلن مفتعلن فاعلن (سریع مطوی مکشوف)');
      expect(p.category!.cat.ancestors.map((a) => a.id), hasLength(2));
      expect(p.next?.id, 41295);
    });

    test('a tarjiband: centered refrain verses', () async {
      final p = await copy.poem(74031);
      expect(p.verses.map((v) => v.position), containsAll([VersePosition.centered1, VersePosition.centered2]));
      expect(p.metre, 'مفعول مفاعلن فعولن (هزج مسدس اخرب مقبوض محذوف)');
    });

    test('a Shahnameh section: breadcrumb through the book, both neighbours', () async {
      final p = await copy.poem(1354);
      expect([for (final a in p.category!.cat.ancestors) a.id], [32, 33]);
      expect(p.category!.cat.id, 39);
      expect(p.category!.poet.id, 4);
      expect((p.previous?.id, p.next?.id), (1353, 1355));
      expect(p.metre, contains('متقارب'));
    });

    test('cached like the API: a second read asks nothing', () async {
      await copy.poem(2130);
      final n = cdn.requests.length;
      await copy.poem(2130);
      expect(cdn.requests, hasLength(n));
    });

    test('a category and a poet', () async {
      final c = await copy.cat(24);
      expect(c.cat.poems.map((p) => p.id), [2130, 2131, 2132]);
      expect(c.cat.poems.first.urlSlug, 'sh1');
      expect(c.cat.ancestors.single.id, 9);
      final poet = await copy.poet(2);
      expect((poet.cat.id, poet.poet.rootCatId), (9, 9));
      expect(poet.cat.children.first.title, 'غزلیات');
      expect(poet.cat.children.first.urlSlug, 'ghazal');
      expect(poet.cat.description, isNotEmpty);
      expect(poet.cat.ancestors, isEmpty);
    });

    test('an id the copy lacks fails', () async {
      await expectLater(copy.poem(5), throwsA(anything));
    });

    test('jsDelivr refusing the compressed copy: the file is asked for uncompressed', () async {
      cdn = _GzipRefusing(staticRoutes());
      copy = GanjoorStatic(
        dio: createDio(adapter: cdn),
        cache: HttpCache(db),
      );
      expect((await copy.locations()).first.name, 'شیراز');
    });
  });

  group('the repository falls back to the copy when Ganjoor fails', () {
    PoetryRepository repo({LocalPoetry? local}) =>
        PoetryRepository(api(withCopy: false), staticCopy: copy, local: local);

    test('server error: the poem comes from the copy', () async {
      server.status['/api/ganjoor/poem/2130'] = 503;
      final p = await repo().poem(2130);
      expect(p.title, 'غزل شمارهٔ ۱');
      expect(p.verses, hasLength(14));
    });

    test('server answering: the copy is not asked', () async {
      final p = await repo().poem(2130);
      expect(p.recitations, isNotEmpty);
      expect(cdn.requests, isEmpty);
    });

    test('no such poem on Ganjoor: the copy is not asked', () async {
      server.status['/api/ganjoor/poem/2130'] = 404;
      await expectLater(repo().poem(2130), throwsA(isA<DioException>()));
      expect(cdn.requests, isEmpty);
    });

    test('offline: the API error stands, as before', () async {
      server.offline = true;
      cdn.offline = true;
      await expectLater(
        repo().poem(2130),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError)),
      );
    });

    test('categories and poets too', () async {
      server.status['/api/ganjoor/cat/24'] = 500;
      server.status['/api/ganjoor/poet/2'] = 502;
      expect((await repo().cat(24)).cat.poems, hasLength(3));
      expect((await repo().poet(2)).cat.id, 9);
    });
  });

  group('reference tables from the copy, the API as fallback', () {
    test('locations come from the copy', () async {
      final l = await api().locations();
      expect(l.map((x) => x.id), containsAll([1, 124, 8670]));
      expect(l.firstWhere((x) => x.id == 124).name, 'بیت‌المقدس');
      expect(server.requests, isEmpty);
    });

    test('the copy failing: the API answers', () async {
      cdn.status['$staticPrefix/locations.json'] = 403;
      final l = await api().locations();
      expect(l.single.name, 'شیراز');
      expect(server.requests.single.path, '/api/locations');
    });

    test('no copy: the API, as before', () async {
      await api(withCopy: false).locations();
      expect(cdn.requests, isEmpty);
    });

    test('literary devices from the copy; a refresh asks Ganjoor', () async {
      final a = api();
      final devices = {for (final d in await a.literaryDevices()) d.id: d};
      expect(devices[1]?.name, 'تشبیه');
      expect(devices[1]?.key, 'tashbih');
      expect(devices[1]?.slots[1], 'مشبّه');
      expect(server.requests, isEmpty);
      await a.literaryDevices(refresh: true);
      expect(server.requests.single.path, '/api/ganjoor/literary/devices');
    });

    test('a poem\'s literary tags from its file read like the API\'s', () async {
      final a = api();
      final tags = await a.literaryTags(2130);
      final catalog = {for (final d in await a.literaryDevices()) d.id: d};
      final couplets = groupCouplets(poem2130().verses);
      final second = devicesOf(couplets[1], tags, catalog);
      expect(second.map((d) => d.name), ['استعاره', 'کنایه', 'ایهام']);
      expect(second[0].roles, [('مستعارٌمنه', 'نافه‌ای'), ('مستعارٌله', 'حلقه خوشبوی گیسوی معشوق')]);
      expect(second[1].roles.last, ('معنای دوم', 'به رنج و محنت افتادن'));
      expect(tags.every((t) => t.fromCorpus), isTrue);
      expect(server.requests, isEmpty);

      // Same result as the API's own answer.
      final live = await api(withCopy: false).literaryTags(2130);
      String show(List<LiteraryTag> l) => jsonEncode([
        for (final t in l)
          [
            t.coupletIndex,
            t.deviceId,
            t.uncertain,
            t.fromCorpus,
            [for (final p in t.parts) '${p.slotId} ${p.misra} ${p.wordStart} ${p.wordEnd} ${p.concept} ${p.text}'],
          ],
      ]);
      expect(show(tags), show(live));
    });

    test('a poem without literary tags has none', () async {
      expect(await api().literaryTags(1354), isEmpty);
    });

    test('place tags of a Shahnameh section: the API\'s, from one small file', () async {
      final fromCopy = await api().catPlaceTags(39);
      final fromApi = await api(withCopy: false).catPlaceTags(39);
      String key(PlaceTag t) => '${t.poemId}/${t.coupletIndex}/${t.locationId}';
      expect(fromCopy.map(key).toSet(), fromApi.map(key).toSet());
      expect(server.requests.where((u) => u.path.contains('/geotag')), hasLength(1), reason: 'only the API-only read');
    });

    test('place tags left out of their category stay out', () async {
      final geo = (jsonDecode(cdn.routes['$staticPrefix/geotags.json']!) as List).cast<Map<String, dynamic>>();
      geo.add({'PoemId': 1355, 'CoupletIndex': 3, 'LocationId': 1, 'IgnoreInCategory': true});
      cdn.routes['$staticPrefix/geotags.json'] = jsonEncode(geo);
      final tags = await api().catPlaceTags(39);
      expect(tags.where((t) => t.poemId == 1355), isEmpty);
      expect(tags.where((t) => t.poemId == 1354).map((t) => t.locationId), [8670, 124]);
    });
  });
}

Poem poem2130() =>
    Poem.fromJson(jsonDecode(File('test/fixtures/poem_2130.json').readAsStringSync()) as Map<String, dynamic>);
