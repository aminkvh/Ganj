import 'dart:convert';

import 'models.dart';
import 'relation_kinds.dart';

/// The sixth element of an edge, when the snapshot has it.
List<int> _books(List e) => e.length > 5 ? [for (final b in e[5] as List) b as int] : const [];

/// Builds the world from the bundled JSON: [generated] by tool/shahnameh_snapshot.dart, the
/// rest curated by hand (assets/seed/shahnameh/).
ShWorld loadWorld({required String generated, required String ages, required String places, required String namesEn}) {
  final g = jsonDecode(generated) as Map<String, dynamic>;
  final en = {
    for (final e in (jsonDecode(namesEn) as Map<String, dynamic>).entries) int.parse(e.key): e.value as String,
  };

  final people = <int, ShPerson>{
    for (final p in g['people'] as List)
      (p as Map)['id'] as int: ShPerson(
        id: p['id'] as int,
        name: p['name'] as String,
        aliases: [for (final a in (p['aliases'] as List? ?? const [])) a as String],
        description: p['description'] as String?,
        importance: (p['importance'] as int?) ?? 0,
        gender: (p['gender'] as int?) ?? 0,
        tree: p['tree'] as String?,
        en: en[p['id']],
        aiDescription: (p['aiDescription'] as bool?) ?? false,
      ),
  };

  // Ties another book alone states (shared people have ties in Nizami's Khamse too) are not
  // this book's; ties no couplet attests are kept, as on ganjoor.net.
  final book = (g['masterCatId'] as int?) ?? 33;
  final edges = [
    for (final e in g['edges'] as List)
      if (people.containsKey((e as List)[0]) && people.containsKey(e[1]))
        if (_books(e) case final books when books.isEmpty || books.contains(book))
          ShEdge(
            e[0] as int,
            e[1] as int,
            relationKind(e[2] as String, e[3] as int),
            degree: e[4] as int?,
            books: books,
          ),
  ];

  final sections = <ShSection>[];
  for (final (order, s) in (g['sections'] as List).indexed) {
    final m = s as Map;
    sections.add(
      ShSection(
        order: order,
        catId: m['catId'] as int,
        title: m['title'] as String,
        slug: m['slug'] as String,
        poems: [
          for (final p in m['poems'] as List)
            ShPoemRef(id: (p as List)[0] as int, title: p[1] as String, slug: p[2] as String, section: order),
        ],
      ),
    );
  }

  Map<int, List<int>> orders(Object? m) => {
    for (final e in ((m as Map?) ?? const {}).entries)
      int.parse(e.key as String): [for (final o in e.value as List) o as int],
  };

  final a = jsonDecode(ages) as Map<String, dynamic>;
  final ageList = <ShAge>[];
  for (final (i, x) in (a['ages'] as List).indexed) {
    final m = x as Map;
    ageList.add(
      ShAge(
        index: i,
        id: m['id'] as String,
        fa: m['fa'] as String,
        en: m['en'] as String,
        from: m['from'] as int,
        to: m['to'] as int,
        reigns: [
          for (final r in (m['reigns'] as List? ?? const []))
            ShReign(
              king: (r as Map)['king'] as int?,
              fa: r['fa'] as String,
              en: r['en'] as String,
              from: r['from'] as int,
              to: r['to'] as int,
            ),
        ],
        stories: [
          for (final s in (m['stories'] as List? ?? const []))
            ShStory(
              id: (s as Map)['id'] as String,
              fa: s['fa'] as String,
              en: s['en'] as String,
              age: i,
              sections: [for (final o in s['sections'] as List) o as int]..sort(),
              people: [for (final p in (s['people'] as List? ?? const [])) p as int],
              places: [for (final p in (s['places'] as List? ?? const [])) p as String],
              summaryEn: s['summaryEn'] as String?,
            ),
        ],
      ),
    );
  }

  final pl = jsonDecode(places) as Map<String, dynamic>;
  return ShWorld(
    builtAt: g['builtAt'] as String,
    people: people,
    edges: edges,
    sections: sections,
    presence: orders(g['presence']),
    passing: orders(g['passing']),
    poemPeople: {
      for (final e in (g['poemPeople'] as Map).entries)
        int.parse(e.key as String): [for (final p in e.value as List) ((p as List)[0] as int, p[1] as int)],
    },
    summaries: {for (final e in (g['summaries'] as Map).entries) int.parse(e.key as String): e.value as String},
    ages: ageList,
    places: [for (final p in pl['places'] as List) _place(p as Map)],
    routes: [
      for (final r in (pl['routes'] as List? ?? const []))
        ShRoute(
          id: (r as Map)['id'] as String,
          fa: r['fa'] as String,
          en: r['en'] as String,
          story: r['story'] as String,
          places: [for (final p in r['places'] as List) p as String],
        ),
    ],
    ganjoorTags: [
      for (final t in (g['places'] as List? ?? const []))
        ShPlaceTag(
          locationId: (t as Map)['loc'] as int,
          name: t['name'] as String,
          lat: (t['lat'] as num).toDouble(),
          lng: (t['lng'] as num).toDouble(),
          poemId: t['poemId'] as int,
          couplet: (t['c'] as int?) ?? 0,
        ),
    ],
    treeRoots: [for (final r in (g['treeRoots'] as List? ?? const [])) r as int],
    aiSummaries: {for (final p in (g['aiSummaries'] as List? ?? const [])) p as int},
    aiTags: {
      for (final e in ((g['aiTags'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): {for (final p in e.value as List) p as int},
    },
  );
}

ShPlace _place(Map p) => ShPlace(
  id: p['id'] as String,
  fa: p['fa'] as String,
  en: p['en'] as String,
  lat: (p['lat'] as num).toDouble(),
  lng: (p['lng'] as num).toDouble(),
  region: (p['region'] as String?) ?? 'other',
  precision: PlacePrecision.values.byName((p['precision'] as String?) ?? 'exact'),
  noteFa: p['noteFa'] as String?,
  noteEn: p['noteEn'] as String?,
  ganjoorId: p['ganjoorId'] as int?,
  stories: [for (final s in (p['stories'] as List? ?? const [])) s as String],
);
