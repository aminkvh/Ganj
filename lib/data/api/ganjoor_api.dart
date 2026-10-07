import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../core/net/api_client.dart' show kSemanticBase;
import '../../core/net/http_cache.dart';
import '../../core/net/request_pool.dart';
import 'dto/book.dart';
import 'dto/cat.dart';
import 'dto/extras.dart';
import 'dto/poem.dart';
import 'dto/poet.dart';
import 'dto/recitation.dart';
import 'dto/semantic.dart';
import '../packs/pack_catalog.dart';

/// Typed, cached access to api.ganjoor.net. Never use /api/ganjoor/page (≈513 KB).
class GanjoorApi {
  GanjoorApi({required this._dio, required this._cache, RequestPool? pool}) : _pool = pool ?? RequestPool(4);

  final Dio _dio;
  final HttpCache _cache;
  final RequestPool _pool;

  static const _day = Duration(days: 1);
  static const _week = Duration(days: 7);
  static const _month = Duration(days: 30);

  /// verseDetails must be true or `verses` comes back null.
  static const poemFlags = {
    'catInfo': 'true',
    'catPoems': 'false',
    'rhymes': 'true',
    'recitations': 'true',
    'images': 'false',
    'songs': 'false',
    'comments': 'false',
    'verseDetails': 'true',
    'navigation': 'true',
    'relatedpoems': 'false',
  };

  Future<List<Century>> centuries() async {
    final list = jsonDecode(await _get('/api/ganjoor/centuries', const {}, _day)) as List;
    return [for (final c in list) Century.fromJson(c as Map<String, dynamic>)];
  }

  Future<PoetCat> poet(int id) async =>
      PoetCat.fromJson(_map(await _get('/api/ganjoor/poet/$id', const {'catPoems': 'true'}, _week)));

  Future<PoetCat> cat(int id) async => PoetCat.fromJson(
    _map(await _get('/api/ganjoor/cat/$id', const {'poems': 'true', 'mainSections': 'false'}, _week)),
  );

  Future<Poem> poem(int id) async => Poem.fromJson(_map(await _get('/api/ganjoor/poem/$id', poemFlags, _week)));

  /// Verse timings for a recitation; XML fallback when the JSON endpoint fails.
  Future<List<SyncPoint>> recitationSync(int id) async {
    try {
      return parseSyncJson(await _get('/api/audio/verses/$id', const {}, _month));
    } catch (_) {
      return parseSyncXml(await _get('/api/audio/file/$id.xml', const {}, _month));
    }
  }

  /// Top recitation of each poem directly in [catId] (not recursive).
  Future<List<Recitation>> catTopRecitations(int catId) async => [
    for (final r in jsonDecode(await _get('/api/audio/cattop1/$catId', const {}, _week)) as List)
      Recitation.fromJson(r as Map<String, dynamic>),
  ];

  /// Ganjoor's official list of downloadable per-poet packs.
  Future<List<PackInfo>> packCatalog() async => parsePackCatalog(await _get(kPackCatalogUrl, const {}, _day));

  /// Online poem search (not cached: results and the paging header change with the index).
  Future<({List<Map<String, dynamic>> poems, int total, bool hasNext})> searchPoems(
    String term, {
    int? poetId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _pool.run(
      () => _dio.get<String>(
        '/api/ganjoor/poems/search',
        queryParameters: {
          'term': term,
          'poetId': '${poetId ?? 0}',
          'catId': '0',
          'PageNumber': '$page',
          'PageSize': '$pageSize',
        },
      ),
    );
    final list = [for (final p in jsonDecode(r.data!) as List) p as Map<String, dynamic>];
    final paging = jsonDecode(r.headers.value('paging-headers') ?? '{}') as Map<String, dynamic>;
    return (
      poems: list,
      total: (paging['totalCount'] as int?) ?? list.length,
      hasNext: (paging['hasNextPage'] as bool?) ?? false,
    );
  }

  // ---- M4 extras: each panel is one lean, lazily-fetched endpoint. ----

  /// Uncached GET (random results, paged lists whose header we need).
  /// Ganjoor's semantic search service (the site's «جستجوی معنایی» button). Online only:
  /// the question is embedded on Ganjoor's server. [global] turns off the poet/book guess.
  Future<SemanticResult> semanticSearch(String query, {bool global = false, int topK = 20}) async {
    final r = await _pool.run(
      () => _dio.post<String>(
        '$kSemanticBase/api/ganjoor/search/semantic',
        data: {'query': query, 'topK': topK, 'disableScopeDetection': global},
        options: Options(contentType: Headers.jsonContentType, receiveTimeout: const Duration(seconds: 45)),
      ),
    );
    return SemanticResult.fromJson(_map(r.data!));
  }

  /// Tells Ganjoor which result was opened, as its own site does, so it can tune the search.
  /// Fire-and-forget: carries only the search's id, the poem and its rank.
  Future<void> semanticClick({required int logId, required int poemId, required int rank}) async {
    try {
      await _dio.post<String>(
        '$kSemanticBase/api/ganjoor/search/semantic/click',
        data: {'logId': logId, 'poemId': poemId, 'rank': rank},
        options: Options(contentType: Headers.jsonContentType),
      );
    } catch (_) {}
  }

  Future<Response<String>> _fresh(String path, Map<String, String> query) =>
      _pool.run(() => _dio.get<String>(path, queryParameters: query));

  static const _leanFlags = {
    'catInfo': 'false',
    'catPoems': 'false',
    'rhymes': 'false',
    'recitations': 'false',
    'images': 'false',
    'songs': 'false',
    'comments': 'false',
    'verseDetails': 'false',
    'navigation': 'false',
    'relatedpoems': 'false',
  };

  Future<Poem> faal() async => Poem.fromJson(_map((await _fresh('/api/ganjoor/hafez/faal', const {})).data!));

  Future<Poem> randomPoem({int? poetId}) async =>
      Poem.fromJson(_map((await _fresh('/api/ganjoor/poem/random', {'poetId': '${poetId ?? 0}'})).data!));

  /// The home-page bookshelf («قفسهٔ کتاب‌ها»).
  Future<List<Book>> bookCatalog() async => [
    for (final b in jsonDecode(await _get('/api/ganjoor/book-catalog', const {}, _week)) as List)
      Book.fromJson(b as Map<String, dynamic>),
  ];

  Future<List<Rhythm>> rhythms() async => [
    for (final r in jsonDecode(await _get('/api/ganjoor/rhythms', const {}, _week)) as List)
      Rhythm.fromJson(r as Map<String, dynamic>),
  ];

  Future<List<T>> _list<T>(
    String path,
    Map<String, String> q,
    Duration ttl,
    T Function(Map<String, dynamic>) f,
  ) async => [for (final e in jsonDecode(await _get(path, q, ttl)) as List) f(e as Map<String, dynamic>)];

  Future<List<PoemImage>> images(int poemId) =>
      _list('/api/ganjoor/poem/$poemId/images', const {}, _week, PoemImage.fromJson);

  Future<List<Song>> songs(int poemId) =>
      _list('/api/ganjoor/poem/$poemId/songs', const {'approved': 'true', 'trackType': '-1'}, _week, Song.fromJson);

  Future<List<Comment>> comments(int poemId) =>
      _list('/api/ganjoor/poem/$poemId/comments', const {}, _day, Comment.fromJson);

  Future<List<Quoted>> quoteds(int poemId) =>
      _list('/api/ganjoor/poem/$poemId/quoteds', const {}, _week, Quoted.fromJson);

  Future<List<Related>> related(int poemId, int sectionIndex) => _list(
    '/api/ganjoor/section/$poemId/$sectionIndex/related',
    const {'skip': '0', 'itemsCount': '20'},
    _week,
    Related.fromJson,
  );

  Future<({List<PoemHit> poems, int total, bool hasNext})> similar({
    required String metre,
    String? rhyme,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _fresh('/api/ganjoor/poems/similar', {
      'metre': metre,
      if (rhyme != null && rhyme.isNotEmpty) 'rhyme': rhyme,
      'PageNumber': '$page',
      'PageSize': '$pageSize',
    });
    final list = [for (final p in jsonDecode(r.data!) as List) PoemHit.fromJson(p as Map<String, dynamic>)];
    final paging = jsonDecode(r.headers.value('paging-headers') ?? '{}') as Map<String, dynamic>;
    return (
      poems: list,
      total: (paging['totalCount'] as int?) ?? list.length,
      hasNext: (paging['hasNextPage'] as bool?) ?? false,
    );
  }

  /// Site path (e.g. "/hafez/ghazal/sh1") → poem id, for links that carry only a url.
  Future<int> poemIdForUrl(String url) async =>
      _map(await _get('/api/ganjoor/poem', {'url': url, ..._leanFlags}, _week))['id'] as int;

  Future<String> _get(String path, Map<String, String> query, Duration ttl) {
    final key = Uri(path: path, queryParameters: query.isEmpty ? null : SplayTreeMap.of(query)).toString();
    return _cache.fetch(
      key,
      ttl,
      () => _pool.run(() async {
        final xml = path.endsWith('.xml');
        final r = await _dio.get<String>(
          path,
          queryParameters: query,
          // i.ganjoor.net answers 406 to a JSON-only Accept for non-JSON files.
          options: xml ? Options(headers: {'Accept': '*/*'}) : null,
        );
        final body = r.data!;
        // Validate before caching so a captive-portal page or truncated body is never stored.
        if (xml) {
          // A captive-portal page is HTML: require well-formed XML whose root isn't <html>.
          if (XmlDocument.parse(body).rootElement.name.local.toLowerCase() == 'html') {
            throw const FormatException('not XML');
          }
        } else {
          jsonDecode(body);
        }
        return body;
      }),
    );
  }
}

Map<String, dynamic> _map(String body) => jsonDecode(body) as Map<String, dynamic>;
