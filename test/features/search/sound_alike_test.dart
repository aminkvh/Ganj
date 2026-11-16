import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/features/search/search_service.dart';

import '../../data/packs/pack_importer_test.dart' show hafezPack;
import '../../support/gdb_builder.dart';

/// Ganjoor's search that only knows the spellings in [found]; records every term asked.
class TermAdapter implements HttpClientAdapter {
  TermAdapter(this.found);

  final Map<String, String> found;
  final terms = <String>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (offline) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    final term = o.uri.queryParameters['term'] ?? '';
    terms.add(term);
    return ResponseBody.fromString(
      found[term] ?? '[]',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        'paging-headers': ['{"totalCount":${found.containsKey(term) ? 20 : 0},"hasNextPage":false}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('sound-alike spellings', () {
    test('the word first, then one letter away, then two', () {
      final v = soundAlikeSpellings('سواب');
      expect(v.first, 'سواب');
      expect(v, containsAll(['ثواب', 'صواب']));
      expect(soundAlikeSpellings('زره'), containsAll(['ذره', 'ضره', 'ظره', 'زرح']));
      expect(soundAlikeSpellings('غفس').indexOf('قفس'), lessThan(soundAlikeSpellings('غفس').indexOf('قفث')));
    });

    test('a word with no such letters has only itself; long words stay bounded', () {
      expect(soundAlikeSpellings('گل'), ['گل']);
      expect(soundAlikeSpellings('سصثزذضظتطهحقغ'), hasLength(16));
    });
  });

  late Directory dir;
  late AppDb db;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ganj_sound_');
    db = AppDb(NativeDatabase.memory());
    await importGdb(db, buildHafezGdb(dir), hafezPack);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  SearchService serviceWith(TermAdapter a) => SearchService(
    db,
    GanjoorApi(
      dio: createDio(adapter: a),
      cache: HttpCache(db),
    ),
  );

  test('typed as is it matches nothing: installed poems match with sound-alike letters', () async {
    final a = TermAdapter({})..offline = true;
    final page = await serviceWith(a).search('ساغی');
    expect(page.soundAlike, isTrue);
    expect(page.offline, isTrue);
    expect(page.hits.map((h) => h.poemId), contains(2130));
  });

  test('online, other spellings are tried one by one until one finds something; later pages keep it', () async {
    final saghi = File('test/fixtures/search_saghi.json').readAsStringSync();
    final a = TermAdapter({'ساقی': saghi});
    final s = serviceWith(a);
    final page = await s.search('ساغی', poetId: 7); // poet 7: no installed poems, online only
    expect(page.soundAlike, isTrue);
    expect(page.onlineTerm, 'ساقی');
    expect(page.hits, isNotEmpty);
    expect(a.terms.first, 'ساغی', reason: 'as typed first');
    expect(a.terms, hasLength(lessThanOrEqualTo(5)));

    a.terms.clear();
    await s.search('ساغی', poetId: 7, page: 2, soundAlike: true, onlineTerm: page.onlineTerm);
    expect(a.terms, ['ساقی']);
  });

  test('a match as typed never tries other spellings', () async {
    final saghi = File('test/fixtures/search_saghi.json').readAsStringSync();
    final a = TermAdapter({'ساقی': saghi});
    final page = await serviceWith(a).search('ساقی');
    expect(page.soundAlike, isFalse);
    expect(a.terms, ['ساقی']);
  });

  test('nothing either way: an empty page, not sound-alike', () async {
    final a = TermAdapter({});
    final page = await serviceWith(a).search('ژژژژ');
    expect(page.hits, isEmpty);
    expect(page.soundAlike, isFalse);
    expect(jsonEncode(a.terms), '["ژژژژ"]', reason: 'no sound-alike letters, nothing else to try');
  });
}
