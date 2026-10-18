/// Ganjoor's people («نامبردگان») endpoints: kinship and ties with their evidence couplets,
/// the poems tagged with a person, and place tags.
class Evidence {
  const Evidence({required this.poemId, required this.coupletIndex, required this.text, this.book});

  factory Evidence.fromJson(Map<String, dynamic> j) => Evidence(
    poemId: j['poemId'] as int,
    coupletIndex: (j['coupletIndex'] as int?) ?? 0,
    text: (j['coupletText'] as String?) ?? '',
    book: j['masterCatId'] as int?,
  );

  final int poemId, coupletIndex;
  final String text;

  /// The book (master category id) the couplet is from.
  final int? book;
}

/// One kinship edge (`cat` R) or tie (`cat` A) seen from the person asked about.
class RelationRow {
  const RelationRow({
    required this.id,
    required this.otherId,
    required this.otherName,
    required this.cat,
    required this.type,
    required this.subjectIsPerson1,
    required this.evidenceCount,
    this.degree,
    this.note,
    this.evidence = const [],
    this.books = const [],
  });

  factory RelationRow.fromJson(Map<String, dynamic> j, {required String cat}) => RelationRow(
    id: j['id'] as int,
    otherId: j['otherPersonId'] as int,
    otherName: (j['otherPersonName'] as String?) ?? '',
    cat: cat,
    type: ((cat == 'R' ? j['relationType'] : j['affiliationType']) as int?) ?? 99,
    subjectIsPerson1: (j['subjectIsPerson1'] as bool?) ?? false,
    evidenceCount: (j['evidenceCount'] as int?) ?? 0,
    degree: j['degreeHint'] as int?,
    note: j['note'] as String?,
    evidence: [for (final e in (j['evidence'] as List? ?? const [])) Evidence.fromJson(e as Map<String, dynamic>)],
    books: [for (final b in (j['evidenceBooks'] as List? ?? const [])) (b as Map)['masterCatId'] as int],
  );

  final int id, otherId;
  final String otherName;
  final String cat;
  final int type;

  /// The person asked about is person1 of the edge ("is [kind] of other").
  final bool subjectIsPerson1;
  final int evidenceCount;
  final int? degree;
  final String? note;
  final List<Evidence> evidence;

  /// Books with a couplet attesting the tie.
  final List<int> books;
}

class PersonRelations {
  const PersonRelations(this.rows);

  factory PersonRelations.fromJson(Map<String, dynamic> j) => PersonRelations([
    for (final r in (j['relations'] as List? ?? const [])) RelationRow.fromJson(r as Map<String, dynamic>, cat: 'R'),
    for (final r in (j['affiliations'] as List? ?? const [])) RelationRow.fromJson(r as Map<String, dynamic>, cat: 'A'),
  ]);

  final List<RelationRow> rows;

  /// The row for the tie with [otherId] of [cat]/[type], if Ganjoor has it.
  RelationRow? find(int otherId, String cat, int type) {
    for (final r in rows) {
      if (r.otherId == otherId && r.cat == cat && r.type == type) return r;
    }
    return null;
  }
}

/// A couplet tagged with a person.
class TaggedPoem {
  const TaggedPoem({
    required this.poemId,
    required this.title,
    required this.fullTitle,
    required this.fullUrl,
    required this.coupletIndex,
    required this.mention,
    this.coupletText,
    this.ai = false,
  });

  factory TaggedPoem.fromJson(Map<String, dynamic> j) {
    final poem = (j['poem'] as Map<String, dynamic>?) ?? const {};
    return TaggedPoem(
      poemId: j['poemId'] as int,
      title: (poem['title'] as String?) ?? '',
      fullTitle: (poem['fullTitle'] as String?) ?? '',
      fullUrl: (poem['fullUrl'] as String?) ?? '',
      coupletIndex: (j['coupletIndex'] as int?) ?? 0,
      mention: (j['personMention'] as int?) ?? 0,
      coupletText: j['coupletText'] as String?,
      ai: ((j['note'] as String?) ?? '').startsWith('پیشنهاد هوش مصنوعی'),
    );
  }

  final int poemId;
  final String title, fullTitle, fullUrl;
  final int coupletIndex;

  /// 0 in the story, 1 only in passing.
  final int mention;
  final String? coupletText;

  /// Ganjoor's AI suggested this tag (a volunteer then approved it).
  final bool ai;
}

/// One tag on a poem's couplet: a person (in the story or in passing) or a place.
class PoemTag {
  const PoemTag({required this.coupletIndex, this.personId, this.mention = 0, this.locationId, this.ai = false});

  factory PoemTag.fromJson(Map<String, dynamic> j) => PoemTag(
    coupletIndex: (j['coupletIndex'] as int?) ?? 0,
    personId: j['personId'] as int?,
    mention: (j['personMention'] as int?) ?? 0,
    locationId: j['locationId'] as int?,
    ai: ((j['note'] as String?) ?? '').startsWith('پیشنهاد هوش مصنوعی'),
  );

  final int coupletIndex;
  final int? personId;

  /// 0 in the story, 1 only in passing.
  final int mention;
  final int? locationId;

  /// Ganjoor's AI suggested it (a volunteer then approved it).
  final bool ai;
}

class PlaceTag {
  const PlaceTag({required this.poemId, required this.coupletIndex, required this.locationId});

  final int poemId, coupletIndex, locationId;
}

class GanjLocation {
  const GanjLocation({required this.id, required this.name, required this.lat, required this.lng});

  factory GanjLocation.fromJson(Map<String, dynamic> j) => GanjLocation(
    id: j['id'] as int,
    name: j['name'] as String,
    lat: (j['latitude'] as num).toDouble(),
    lng: (j['longitude'] as num).toDouble(),
  );

  final int id;
  final String name;
  final double lat, lng;
}
