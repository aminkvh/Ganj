import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/net/api_client.dart' show kStaticBase;
import '../../core/net/http_cache.dart';
import '../../core/net/request_pool.dart';
import '../../core/text/labeled_text.dart';
import 'dto/cat.dart';
import 'dto/literary.dart';
import 'dto/people.dart';
import 'dto/poem.dart';
import 'dto/poet.dart';

/// Ganjoor's public data copy (github.com/ganjoor/ganjoor-data) read through jsDelivr: the
/// same poems and reference tables as api.ganjoor.net, as static files in PascalCase. Read
/// back as the API's DTOs, so screens don't care where data came from. The CDN can lag the
/// site by up to a week; what the copy lacks (recitations, excerpts, verse languages) is empty.
class GanjoorStatic {
  GanjoorStatic({required this._dio, required this._cache, RequestPool? pool}) : _pool = pool ?? RequestPool(4);

  final Dio _dio;
  final HttpCache _cache;
  final RequestPool _pool;

  static const _week = Duration(days: 7);
  static const _month = Duration(days: 30);

  /// Ids per index shard (manifest.json's IdIndexShardSize).
  static const shardSize = 2000;

  Future<Object?> _json(String path, Duration ttl) async {
    final url = '$kStaticBase/$path';
    final body = await _cache.fetch(
      url,
      ttl,
      () => _pool.run(() async {
        String body;
        try {
          body = (await _dio.get<String>(url)).data!;
        } on DioException catch (e) {
          // jsDelivr sometimes keeps a 403 («package size exceeded») for the compressed copy of
          // a file it serves fine uncompressed: ask once more for that one.
          if (e.response?.statusCode != 403) rethrow;
          body = (await _dio.get<String>(url, options: Options(headers: {'Accept-Encoding': 'identity'}))).data!;
        }
        jsonDecode(body); // never cache an error page
        return body;
      }),
    );
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> _map(String path, Duration ttl) async => await _json(path, ttl) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> _list(String path, Duration ttl) async => [
    for (final e in await _json(path, ttl) as List) e as Map<String, dynamic>,
  ];

  /// Site path ("/hafez/ghazal") of a poem or category id, from the id index.
  Future<String> _pathOf(String kind, int id) async {
    final url = (await _map('index/$kind-by-id/${id ~/ shardSize}.json', _week))['$id'];
    if (url is! String) throw StateError('$kind $id is not in the static copy');
    return url;
  }

  Future<Map<String, dynamic>> _catFile(String fullUrl) => _map('poets$fullUrl/_cat.json', _week);

  /// The raw poem file of [id].
  Future<Map<String, dynamic>> poemFile(int id) async => _map('poets${await _pathOf('poems', id)}.json', _week);

  /// The category files along [fullUrl] (root first) and the poet's file.
  Future<(List<Map<String, dynamic>>, Map<String, dynamic>)> _chain(String fullUrl) async {
    final prefixes = _prefixes(fullUrl);
    return await (
      Future.wait([for (final p in prefixes) _catFile(p)]),
      _map('poets${prefixes.first}/poet.json', _week),
    ).wait;
  }

  /// A category with its poet and ancestors.
  PoetCat _poetCat(List<Map<String, dynamic>> files, Map<String, dynamic> poet, {bool withContent = true}) => PoetCat(
    poet: staticPoet(poet, rootCatId: files.first['Id'] as int),
    cat: staticCat(files.last, ancestors: files.sublist(0, files.length - 1), withContent: withContent),
  );

  Future<PoetCat> cat(int id) async {
    final (files, poet) = await _chain(await _pathOf('cats', id));
    return _poetCat(files, poet);
  }

  Future<PoetCat> poet(int id) async {
    final url = (await _map('index/poets-by-id.json', _week))['$id'];
    if (url is! String) throw StateError('poet $id is not in the static copy');
    final (files, poet) = await _chain(url);
    return _poetCat(files, poet);
  }

  Future<Poem> poem(int id) async {
    final file = await poemFile(id);
    final fullUrl = file['FullUrl'] as String;
    final (files, poet) = await _chain(fullUrl.substring(0, fullUrl.lastIndexOf('/')));
    // The file names its main metre only sometimes; the metre table has them all.
    final metreId = _mainSection(file)?['MetreId'];
    var metres = const <int, String>{};
    if (metreId is int && (file['Metre'] as Map?)?['Id'] != metreId) {
      try {
        metres = await _metres();
      } catch (_) {
        // Without its metre, the poem still reads.
      }
    }
    return staticPoem(
      file,
      category: _poetCat(files, poet, withContent: false),
      siblings: (files.last['Poems'] as List?) ?? const [],
      metres: metres,
    );
  }

  Future<Map<int, String>> _metres() async => {
    for (final m in await _list('metres.json', _month)) m['Id'] as int: (m['Rhythm'] as String?) ?? '',
  };

  Future<List<GanjLocation>> locations() async => [
    for (final l in await _list('locations.json', _month)) staticLocation(l),
  ];

  Future<List<LiteraryDevice>> literaryDevices() async => [
    for (final d in await _list('literary-devices.json', _month)) staticDevice(d),
  ];

  /// The literary-device tags of a poem, from its own file; concept names from the concept table.
  Future<List<LiteraryTag>> literaryTags(int poemId) async {
    final tags = [for (final t in (await poemFile(poemId))['LiteraryTags'] as List? ?? const []) t as Map];
    if (tags.isEmpty) return const [];
    final concepts = {
      for (final c in await _list('literary-concepts.json', _month)) c['Id'] as int: (c['Name'] as String?) ?? '',
    };
    return [for (final t in tags) staticLiteraryTag(t, concepts)];
  }

  /// Place tags of the poems directly in [catId] (like the API, those marked to be left out of
  /// their category are).
  Future<List<PlaceTag>> catPlaceTags(int catId) async {
    final (cat, tags) = await (_catFile(await _pathOf('cats', catId)), _list('geotags.json', _month)).wait;
    final poems = {for (final p in (cat['Poems'] as List?) ?? const []) (p as Map)['Id'] as int};
    return [
      for (final t in tags)
        if (t['LocationId'] case final int loc)
          if (poems.contains(t['PoemId']) && t['IgnoreInCategory'] != true)
            PlaceTag(poemId: t['PoemId'] as int, coupletIndex: (t['CoupletIndex'] as int?) ?? 0, locationId: loc),
    ];
  }
}

/// "/a/b/c" → ["/a", "/a/b", "/a/b/c"].
List<String> _prefixes(String fullUrl) {
  final parts = fullUrl.split('/').where((s) => s.isNotEmpty).toList();
  return [for (var i = 1; i <= parts.length; i++) '/${parts.take(i).join('/')}'];
}

String _slug(String fullUrl) => fullUrl.split('/').last;

/// The copy's poet images are absolute on ganjoor.net; the API's are site paths.
String? _sitePath(String? url) {
  const site = 'https://ganjoor.net/api/';
  return url != null && url.startsWith(site) ? url.substring('https://ganjoor.net'.length) : url;
}

Poet staticPoet(Map<String, dynamic> j, {required int rootCatId}) => Poet(
  id: j['Id'] as int,
  name: (j['Name'] as String?) ?? '',
  nickname: (j['Nickname'] as String?) ?? (j['Name'] as String?) ?? '',
  fullUrl: (j['FullUrl'] as String?) ?? '',
  rootCatId: rootCatId,
  imageUrl: _sitePath(j['ImageUrl'] as String?),
  description: j['Description'] as String?,
  birthYear: _year(j['BirthYearInLHijri']),
  deathYear: _year(j['DeathYearInLHijri']),
  pinOrder: (j['PinOrder'] as int?) ?? 0,
  birthPlace: j['BirthPlace'] as String?,
);

int? _year(Object? v) => v is int && v > 0 ? v : null;

CatRef _catRef(Map j) {
  final url = (j['FullUrl'] as String?) ?? '';
  return CatRef(id: j['Id'] as int, title: (j['Title'] as String?) ?? '', urlSlug: _slug(url), fullUrl: url);
}

PoemRef _poemRef(Map j) => PoemRef(
  id: j['Id'] as int,
  title: (j['Title'] as String?) ?? '',
  urlSlug: _slug(j['FullUrl'] as String),
  excerpt: '',
);

/// A `_cat.json` file; [ancestors] are the files of the categories above it, root first.
Cat staticCat(Map<String, dynamic> j, {List<Map<String, dynamic>> ancestors = const [], bool withContent = true}) {
  final description = j['Description'] as String?;
  return Cat(
    id: j['Id'] as int,
    title: (j['Title'] as String?) ?? '',
    fullUrl: (j['FullUrl'] as String?) ?? '',
    description: description == null || description.isEmpty ? null : description,
    ancestors: [for (final a in ancestors) _catRef(a)],
    children: withContent ? [for (final c in (j['ChildCats'] as List?) ?? const []) _catRef(c as Map)] : const [],
    poems: withContent ? [for (final p in (j['Poems'] as List?) ?? const []) _poemRef(p as Map)] : const [],
  );
}

/// The copy names enums; the API numbers them (GanjoorService VersePosition).
const _positions = {
  'Right': VersePosition.right,
  'Left': VersePosition.left,
  'CenteredVerse1': VersePosition.centered1,
  'CenteredVerse2': VersePosition.centered2,
  'Single': VersePosition.single,
  'Comment': VersePosition.comment,
  'Paragraph': VersePosition.paragraph,
};

int _position(Object? p) => p is int ? p : _positions[p] ?? VersePosition.right;

/// The whole-poem section, as the API picks it.
Map<String, dynamic>? _mainSection(Map<String, dynamic> j) {
  final sections = [for (final s in (j['Sections'] as List?) ?? const []) s as Map<String, dynamic>];
  return sections.where((s) => s['SectionType'] == 'WholePoem' || s['SectionType'] == 0).firstOrNull ??
      sections.firstOrNull;
}

/// A poem file; [category] is its category (with poet and ancestors), [siblings] the poems
/// of that category in order (for the previous/next links), [metres] rhythms by metre id.
Poem staticPoem(
  Map<String, dynamic> j, {
  PoetCat? category,
  List<Object?> siblings = const [],
  Map<int, String> metres = const {},
}) {
  final id = j['Id'] as int;
  final main = _mainSection(j);
  final metre = j['Metre'] as Map<String, dynamic>?;
  final metreId = main?['MetreId'];
  final rhyme = main?['RhymeLetters'] as String?;
  final verses = [
    for (final v in (j['Verses'] as List?) ?? const [])
      if (v is Map<String, dynamic>)
        Verse(
          vOrder: v['VOrder'] as int,
          position: _position(v['Position']),
          text: (v['Text'] as String?) ?? '',
          coupletIndex: v['CoupletIndex'] as int?,
          languageId: v['LanguageId'] as int?,
          summary: LabeledText.parse(v['CoupletSummary'] as String?),
        ),
  ]..sort((a, b) => a.vOrder.compareTo(b.vOrder));
  final at = siblings.indexWhere((p) => p is Map && p['Id'] == id);
  PoemRef? sibling(int i) => at < 0 || i < 0 || i >= siblings.length ? null : _poemRef(siblings[i] as Map);
  return Poem(
    id: id,
    title: (j['Title'] as String?) ?? '',
    fullTitle: (j['FullTitle'] as String?) ?? '',
    fullUrl: (j['FullUrl'] as String?) ?? '',
    plainText: verses.map((v) => v.text).join('\n'),
    summary: LabeledText.parse(j['PoemSummary'] as String?),
    category: category,
    next: sibling(at + 1),
    previous: sibling(at - 1),
    verses: verses,
    // The poem's metre is its main section's.
    metre: metreId is! int ? null : (metre?['Id'] == metreId ? metre!['Rhythm'] as String? : metres[metreId]),
    rhyme: (rhyme == null || rhyme.isEmpty) ? null : rhyme,
  );
}

GanjLocation staticLocation(Map<String, dynamic> j) => GanjLocation(
  id: j['Id'] as int,
  name: j['Name'] as String,
  lat: (j['Latitude'] as num).toDouble(),
  lng: (j['Longitude'] as num).toDouble(),
);

LiteraryDevice staticDevice(Map<String, dynamic> j) => LiteraryDevice(
  id: j['Id'] as int,
  name: (j['Name'] as String?) ?? '',
  key: j['Key'] as String?,
  definition: j['Definition'] as String?,
  slots: {for (final s in (j['Slots'] as List?) ?? const []) (s as Map)['Id'] as int: (s['Name'] as String?) ?? ''},
);

/// A tag as the poem file has it; parts are already in order, concepts are ids into [concepts].
LiteraryTag staticLiteraryTag(Map j, Map<int, String> concepts) => LiteraryTag(
  coupletIndex: (j['CoupletIndex'] as int?) ?? 0,
  deviceId: j['DeviceId'] as int,
  uncertain: (j['Uncertain'] as bool?) ?? false,
  fromCorpus: ((j['SourceKey'] as String?) ?? '').startsWith('persian-literary-corpus'),
  parts: [
    for (final p in [
      ...(j['Parts'] as List?) ?? const [],
    ]..sort((a, b) => (((a as Map)['Order'] as int?) ?? 0).compareTo(((b as Map)['Order'] as int?) ?? 0)))
      if (p is Map)
        LiteraryPart(
          slotId: p['SlotId'] as int,
          misra: (p['Misra'] as int?) ?? 0,
          wordStart: p['WordStart'] as int?,
          wordEnd: p['WordEnd'] as int?,
          concept: concepts[p['ConceptId']],
          text: p['Text'] as String?,
        ),
  ],
);
