import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/core/text/html_text.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';

import '../support/fake_adapter.dart';

String ex(String name) => File('test/fixtures/extra/$name').readAsStringSync();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('htmlToText', () {
    test('strips tags and decodes entities', () {
      expect(
        htmlToText('<p>شمس&zwnj;الدین &laquo;حافظ&raquo; &amp; <a href="x">پیوند</a></p>'),
        'شمس‌الدین «حافظ» & پیوند',
      );
    });
    test('keeps paragraph and line breaks', () {
      expect(htmlToText('<p>یک<br />دو</p><p>سه</p>'), 'یک\nدو\nسه');
    });
    test('nbsp and repeated spaces collapse', () {
      expect(htmlToText('a&nbsp;&nbsp; b'), 'a b');
    });
  });

  group('extras API', () {
    late AppDb db;
    late GanjoorApi api;
    late FakeAdapter adapter;

    setUp(() {
      db = AppDb(NativeDatabase.memory());
      adapter = FakeAdapter({
        '/api/ganjoor/hafez/faal': ex('faal.json'),
        '/api/ganjoor/poem/random': ex('random.json'),
        '/api/ganjoor/rhythms': ex('rhythms.json'),
        '/api/ganjoor/poem/2130/images': ex('images_2130.json'),
        '/api/ganjoor/poem/2130/songs': ex('songs_2130.json'),
        '/api/ganjoor/poem/2130/comments': ex('comments_2130.json'),
        '/api/ganjoor/poem/2130/quoteds': ex('quoteds_2130.json'),
        '/api/ganjoor/section/2130/0/related': ex('related_2130.json'),
        '/api/ganjoor/poems/similar': ex('similar.json'),
        '/api/ganjoor/poem': '{"id":64590,"title":"غزل شمارهٔ ۱","fullUrl":"/ebnehesam/ghazalebn/sh1"}',
      });
      adapter.headers['/api/ganjoor/poems/similar'] = {
        'paging-headers': '{"totalCount":46,"pageSize":10,"currentPage":1,"totalPages":5,"hasNextPage":true}',
      };
      api = GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      );
    });
    tearDown(() => db.close());

    test('faal and random return full poems', () async {
      final f = await api.faal();
      expect(f.id, 2445);
      expect(f.verses, isNotEmpty);
      final r = await api.randomPoem(poetId: 2);
      expect(r.id, 2177);
      expect(adapter.requests.last.queryParameters['poetId'], '2');
    });

    test('rhythms', () async {
      final r = await api.rhythms();
      expect(r, hasLength(212));
      expect(r.first.rhythm, isNotEmpty);
    });

    test('images, songs, quoteds, related', () async {
      final images = await api.images(2130);
      expect(images.first.thumb, startsWith('https://i.ganjoor.net/'));
      expect(images.first.target, contains('museum.ganjoor.net'));
      final songs = await api.songs(2130);
      expect(songs.first.artist, 'ایرج بسطامی');
      expect(songs.first.url, startsWith('https://'));
      final quoteds = await api.quoteds(2130);
      expect(quoteds, hasLength(5));
      expect(quoteds.first.fullTitle, isNotEmpty);
      final related = await api.related(2130, 0);
      expect(related.first.poetName, 'ابن حسام خوسفی');
      expect(related.first.fullUrl, '/ebnehesam/ghazalebn/sh1');
      expect(related.first.excerpt, isNot(contains('<p>')));
    });

    test('comments: plain text, beyt index, replies', () async {
      final c = await api.comments(2130);
      expect(c, hasLength(6));
      expect(c.first.author, 'رسته');
      expect(c.first.text, isNot(contains('<')));
      expect(c.first.coupletIndex, -1);
      expect(c[1].replies, hasLength(1));
    });

    test('similar poems are paged', () async {
      final page = await api.similar(metre: 'مفاعیلن', rhyme: 'لها');
      expect(page.poems, hasLength(3));
      expect(page.total, 46);
      expect(page.hasNext, isTrue);
      expect(adapter.requests.last.queryParameters['rhyme'], 'لها');
    });

    test('poemIdForUrl resolves a site path', () async {
      expect(await api.poemIdForUrl('/ebnehesam/ghazalebn/sh1'), 64590);
      expect(adapter.requests.last.queryParameters['url'], '/ebnehesam/ghazalebn/sh1');
    });
  });
}
