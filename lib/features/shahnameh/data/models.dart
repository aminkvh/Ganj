import 'relation_kinds.dart';

/// Pure-Dart model of «جهان شاهنامه»: Ganjoor's people and tags (bundled snapshot) plus Ganj's
/// own ages, stories and places. Sections are addressed by their story order (0–59).
class ShPerson {
  const ShPerson({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.description,
    this.importance = 0,
    this.gender = 0,
    this.tree,
    this.en,
    this.aiDescription = false,
  });

  final int id;
  final String name;
  final List<String> aliases;
  final String? description;

  /// Ganjoor's 0–2 (2 = the great figures).
  final int importance;

  /// 1 man, 2 woman, 0 unknown.
  final int gender;

  /// Caption when this person heads one of Ganjoor's family trees.
  final String? tree;

  /// English transliteration (main characters only; written by AI for Ganj).
  final String? en;

  /// The description is one Ganjoor's AI wrote.
  final bool aiDescription;
}

/// "a is [kind] of b".
class ShEdge {
  const ShEdge(this.a, this.b, this.kind, {this.degree});

  final int a, b;
  final RelationKind kind;

  /// Generations between ancestor and descendant, when Ganjoor knows it.
  final int? degree;

  int other(int id) => id == a ? b : a;
}

class ShPoemRef {
  const ShPoemRef({required this.id, required this.title, required this.slug, required this.section});

  final int id;
  final String title, slug;
  final int section;
}

class ShSection {
  const ShSection({
    required this.order,
    required this.catId,
    required this.title,
    required this.slug,
    required this.poems,
  });

  final int order, catId;
  final String title, slug;
  final List<ShPoemRef> poems;
}

class ShStory {
  const ShStory({
    required this.id,
    required this.fa,
    required this.en,
    required this.age,
    required this.sections,
    this.people = const [],
    this.places = const [],
    this.summaryEn,
  });

  final String id, fa, en;

  /// Index into [ShWorld.ages].
  final int age;

  /// Story orders, ascending.
  final List<int> sections;
  final List<int> people;
  final List<String> places;
  final String? summaryEn;

  int get from => sections.first;
  int get to => sections.last;
}

class ShReign {
  const ShReign({this.king, required this.fa, required this.en, required this.from, required this.to});

  /// Null where Ganjoor's people don't single the king out.
  final int? king;
  final String fa, en;
  final int from, to;
}

class ShAge {
  const ShAge({
    required this.index,
    required this.id,
    required this.fa,
    required this.en,
    required this.from,
    required this.to,
    this.reigns = const [],
    this.stories = const [],
  });

  final int index;
  final String id, fa, en;
  final int from, to;
  final List<ShReign> reigns;
  final List<ShStory> stories;

  bool contains(int section) => section >= from && section <= to;
}

enum PlacePrecision { exact, approx, mythic }

/// A couplet that names a place, from Ganjoor's tags.
class ShPlaceTag {
  const ShPlaceTag({
    required this.locationId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.poemId,
    required this.couplet,
  });

  final int locationId;
  final String name;
  final double lat, lng;
  final int poemId, couplet;
}

class ShPlace {
  const ShPlace({
    required this.id,
    required this.fa,
    required this.en,
    required this.lat,
    required this.lng,
    required this.region,
    this.precision = PlacePrecision.exact,
    this.noteFa,
    this.noteEn,
    this.ganjoorId,
    this.stories = const [],
    this.fromGanjoor = false,
    this.tags = const [],
  });

  final String id, fa, en;
  final double lat, lng;

  /// A key of [kRegions].
  final String region;
  final PlacePrecision precision;
  final String? noteFa, noteEn;

  /// Ganjoor's location id, when Ganjoor knows this place.
  final int? ganjoorId;
  final List<String> stories;

  /// Only Ganjoor knows it (not curated).
  final bool fromGanjoor;
  final List<ShPlaceTag> tags;

  ShPlace copyWith({List<ShPlaceTag>? tags}) => ShPlace(
    id: id,
    fa: fa,
    en: en,
    lat: lat,
    lng: lng,
    region: region,
    precision: precision,
    noteFa: noteFa,
    noteEn: noteEn,
    ganjoorId: ganjoorId,
    stories: stories,
    fromGanjoor: fromGanjoor,
    tags: tags ?? this.tags,
  );
}

/// The lands of the Shahnameh.
const kRegions = <String, ({String fa, String en})>{
  'iran': (fa: 'ایران', en: 'Iran'),
  'turan': (fa: 'توران', en: 'Turan'),
  'rum': (fa: 'روم', en: 'Rum'),
  'hind': (fa: 'هند', en: 'Hind'),
  'chin': (fa: 'چین', en: 'Chin'),
  'mazandaran': (fa: 'مازندران', en: 'Mazandaran'),
  'sistan': (fa: 'سیستان و زابل', en: 'Sistan & Zabol'),
  'hamavaran': (fa: 'هاماوران', en: 'Hamavaran'),
  'arab': (fa: 'تازیان', en: 'Arabia'),
  'kabul': (fa: 'کابلستان', en: 'Kabulistan'),
  'other': (fa: 'دیگر', en: 'Elsewhere'),
};

/// An ordered journey, e.g. the seven labours.
class ShRoute {
  const ShRoute({required this.id, required this.fa, required this.en, required this.story, required this.places});

  final String id, fa, en, story;
  final List<String> places;
}

class ShWorld {
  ShWorld({
    required this.builtAt,
    required this.people,
    required this.edges,
    required this.sections,
    required this.presence,
    required this.passing,
    required this.poemPeople,
    required this.summaries,
    required this.ages,
    required this.places,
    required this.routes,
    required this.ganjoorTags,
    required this.treeRoots,
    this.aiSummaries = const {},
    this.aiTags = const {},
  }) {
    for (final e in edges) {
      _edgesOf.putIfAbsent(e.a, () => []).add(e);
      _edgesOf.putIfAbsent(e.b, () => []).add(e);
    }
    for (final s in sections) {
      for (final p in s.poems) {
        _sectionOfPoem[p.id] = s;
      }
    }
  }

  final String builtAt;
  final Map<int, ShPerson> people;
  final List<ShEdge> edges;
  final List<ShSection> sections;

  /// Person → story orders where they take part / are only mentioned in passing.
  final Map<int, List<int>> presence, passing;

  /// Poem → (person, mention): mention 0 in the story, 1 in passing.
  final Map<int, List<(int, int)>> poemPeople;

  /// Poem → first sentence of Ganjoor's summary.
  final Map<int, String> summaries;
  final List<ShAge> ages;
  final List<ShPlace> places;
  final List<ShRoute> routes;
  final List<ShPlaceTag> ganjoorTags;
  final List<int> treeRoots;

  /// Poems whose Ganjoor summary is AI-written.
  final Set<int> aiSummaries;

  /// Poem → people whose tag there Ganjoor's AI suggested (a volunteer then approved).
  final Map<int, Set<int>> aiTags;

  bool isAiTag(int poemId, int person) => aiTags[poemId]?.contains(person) ?? false;

  /// Where a person appears comes (at least partly) from AI-suggested tags.
  bool hasAiTags(int person) => _aiTagged.contains(person);
  late final Set<int> _aiTagged = {for (final s in aiTags.values) ...s};

  final _edgesOf = <int, List<ShEdge>>{};
  final _sectionOfPoem = <int, ShSection>{};

  List<ShEdge> edgesOf(int id) => _edgesOf[id] ?? const [];

  ShSection? sectionOfPoem(int poemId) => _sectionOfPoem[poemId];

  ShAge ageOfSection(int order) => ages.firstWhere((a) => a.contains(order), orElse: () => ages.last);

  /// First story order where the person appears (in the story, else in passing).
  int? firstSection(int person) => presence[person]?.first ?? passing[person]?.first;

  late final List<ShStory> stories = [for (final a in ages) ...a.stories];

  ShStory? storyById(String id) {
    for (final s in stories) {
      if (s.id == id) return s;
    }
    return null;
  }

  ShPlace? placeById(String id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  String displayName(int id, {required bool english}) {
    final p = people[id];
    if (p == null) return '';
    return english ? (p.en ?? p.name) : p.name;
  }
}
