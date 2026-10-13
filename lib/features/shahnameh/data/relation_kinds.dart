/// Kinds of ties between people, as ganjoor.net's people graph defines them (KIND_META in
/// /js/peoplegraph.js). An edge reads "person1 is [kind] of person2": منوچهر قاتلِ سلم.
library;

/// Ganjoor's ~20 kinds folded into four families, each with its own colour and line style;
/// the exact kind is always written out as a label.
enum RelationFamily { kin, conflict, service, alliance }

class RelationKind {
  const RelationKind({
    required this.key,
    required this.fa,
    required this.en,
    required this.family,
    this.faOf,
    this.enOf,
  });

  /// `R:0` … `A:99`.
  final String key;

  /// The role of person1, as a noun: «قاتل», "Killer".
  final String fa, en;

  /// The role of person1 towards person2, when the open person is person1: «قاتلِ», "Killer of".
  /// Null for kinds that read the same both ways.
  final String? faOf, enOf;

  final RelationFamily family;

  bool get directional => faOf != null;
  bool get isKin => family == RelationFamily.kin;
}

const _kinds = <String, RelationKind>{
  'R:0': RelationKind(
    key: 'R:0',
    fa: 'پدر/مادر',
    en: 'Parent',
    faOf: 'فرزند',
    enOf: 'Child',
    family: RelationFamily.kin,
  ),
  'R:1': RelationKind(key: 'R:1', fa: 'خواهر/برادر', en: 'Sibling', family: RelationFamily.kin),
  'R:2': RelationKind(key: 'R:2', fa: 'همسر', en: 'Spouse', family: RelationFamily.kin),
  'R:3': RelationKind(
    key: 'R:3',
    fa: 'نیا',
    en: 'Ancestor',
    faOf: 'نواده',
    enOf: 'Descendant',
    family: RelationFamily.kin,
  ),
  'A:0': RelationKind(
    key: 'A:0',
    fa: 'وزیر',
    en: 'Vizier',
    faOf: 'وزیرِ',
    enOf: 'Vizier to',
    family: RelationFamily.service,
  ),
  'A:1': RelationKind(
    key: 'A:1',
    fa: 'مشاور',
    en: 'Advisor',
    faOf: 'مشاورِ',
    enOf: 'Advisor to',
    family: RelationFamily.service,
  ),
  'A:2': RelationKind(
    key: 'A:2',
    fa: 'درباری',
    en: 'Courtier',
    faOf: 'درباریِ',
    enOf: 'Courtier of',
    family: RelationFamily.service,
  ),
  'A:3': RelationKind(
    key: 'A:3',
    fa: 'حامی',
    en: 'Patron',
    faOf: 'حامیِ',
    enOf: 'Patron of',
    family: RelationFamily.service,
  ),
  'A:4': RelationKind(key: 'A:4', fa: 'دوست/متحد', en: 'Friend/ally', family: RelationFamily.alliance),
  'A:5': RelationKind(key: 'A:5', fa: 'دشمن/رقیب', en: 'Enemy/rival', family: RelationFamily.conflict),
  'A:6': RelationKind(
    key: 'A:6',
    fa: 'خدمتکار',
    en: 'Servant',
    faOf: 'خدمتکارِ',
    enOf: 'Servant of',
    family: RelationFamily.service,
  ),
  'A:7': RelationKind(key: 'A:7', fa: 'همراه', en: 'Companion', family: RelationFamily.alliance),
  'A:8': RelationKind(
    key: 'A:8',
    fa: 'جانشین',
    en: 'Successor',
    faOf: 'جانشینِ',
    enOf: 'Successor to',
    family: RelationFamily.alliance,
  ),
  'A:9': RelationKind(
    key: 'A:9',
    fa: 'مدح‌گو',
    en: 'Panegyrist',
    faOf: 'مدح‌گوی',
    enOf: 'Praised',
    family: RelationFamily.service,
  ),
  'A:10': RelationKind(
    key: 'A:10',
    fa: 'هجوگو',
    en: 'Satirist',
    faOf: 'هجوگوی',
    enOf: 'Satirised',
    family: RelationFamily.conflict,
  ),
  'A:11': RelationKind(
    key: 'A:11',
    fa: 'سردار',
    en: 'Commander',
    faOf: 'سردارِ',
    enOf: 'Commander for',
    family: RelationFamily.service,
  ),
  'A:12': RelationKind(
    key: 'A:12',
    fa: 'پهلوان',
    en: 'Champion',
    faOf: 'پهلوانِ',
    enOf: 'Champion of',
    family: RelationFamily.service,
  ),
  'A:13': RelationKind(key: 'A:13', fa: 'هم‌عصر', en: 'Contemporary', family: RelationFamily.alliance),
  'A:14': RelationKind(
    key: 'A:14',
    fa: 'قاتل',
    en: 'Killer',
    faOf: 'قاتلِ',
    enOf: 'Killer of',
    family: RelationFamily.conflict,
  ),
  'A:15': RelationKind(
    key: 'A:15',
    fa: 'عاشق',
    en: 'Lover',
    faOf: 'عاشقِ',
    enOf: 'In love with',
    family: RelationFamily.alliance,
  ),
  'A:99': RelationKind(key: 'A:99', fa: 'سایر', en: 'Other tie', family: RelationFamily.alliance),
};

/// [cat] is `R` (kinship) or `A` (affiliation); kinds Ganjoor adds later read as «سایر».
RelationKind relationKind(String cat, int type) => _kinds['$cat:$type'] ?? _kinds['A:99']!;

/// Kinship nouns by the other person's gender (Ganjoor: 1 man, 2 woman, 0 unknown).
({String fa, String en}) kinNoun(RelationKind k, {required bool ofSide, required int gender}) {
  final male = gender == 1, female = gender == 2;
  String pick(String m, String f, String n) => male ? m : (female ? f : n);
  return switch ((k.key, ofSide)) {
    ('R:0', false) => (fa: pick('پدر', 'مادر', 'پدر/مادر'), en: pick('Father', 'Mother', 'Parent')),
    ('R:0', true) => (fa: pick('پسر', 'دختر', 'فرزند'), en: pick('Son', 'Daughter', 'Child')),
    ('R:1', _) => (fa: pick('برادر', 'خواهر', 'خواهر/برادر'), en: pick('Brother', 'Sister', 'Sibling')),
    ('R:2', _) => (fa: 'همسر', en: pick('Husband', 'Wife', 'Spouse')),
    (_, true) => (fa: k.faOf ?? k.fa, en: k.enOf ?? k.en),
    _ => (fa: k.fa, en: k.en),
  };
}
