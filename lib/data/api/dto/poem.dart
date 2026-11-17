import '../../../core/text/labeled_text.dart';
import 'cat.dart';
import 'extras.dart';
import 'recitation.dart';

/// GanjoorService VersePosition enum.
abstract final class VersePosition {
  static const right = 0;
  static const left = 1;
  static const centered1 = 2;
  static const centered2 = 3;
  static const single = 4;
  static const comment = 5;
  static const paragraph = -1;
}

class Verse {
  const Verse({
    required this.vOrder,
    required this.position,
    required this.text,
    this.coupletIndex,
    this.languageId,
    this.summary,
  });

  final int vOrder;
  final int? coupletIndex;
  final int position;
  final String text;
  final int? languageId;
  final LabeledText? summary;

  String? get languageName => verseLanguageNames[languageId];

  factory Verse.fromJson(Map<String, dynamic> j) => Verse(
    vOrder: j['vOrder'] as int,
    coupletIndex: j['coupletIndex'] as int?,
    position: (j['versePosition'] as int?) ?? VersePosition.right,
    text: (j['text'] as String?) ?? '',
    languageId: j['languageId'] as int?,
    summary: LabeledText.parse(j['coupletSummary'] as String?),
  );
}

/// What the poem page's extra panels hold, as far as the poem's own answer from Ganjoor tells.
/// A null part is unknown (not in the answer); the page then asks for it when it needs it.
class PoemExtrasInfo {
  const PoemExtrasInfo({this.hasRelated, this.hasQuoted, this.images, this.songs});

  /// Poems in the same metre and rhyme («استقبال‌ها»): Ganjoor sends the first six with the poem.
  final bool? hasRelated;

  /// Couplets quoted in other poems: Ganjoor sends the first six with the poem.
  final bool? hasQuoted;

  final List<PoemImage>? images;
  final List<Song>? songs;

  factory PoemExtrasInfo.fromJson(Map<String, dynamic> j, Map<String, dynamic>? mainSection) {
    final related = mainSection?['top6RelatedSections'];
    final quoted = j['top6QuotedPoems'];
    final images = j['images'], songs = j['songs'];
    return PoemExtrasInfo(
      hasRelated: related is List ? related.isNotEmpty : null,
      hasQuoted: quoted is List ? quoted.isNotEmpty : null,
      images: images is List ? [for (final i in images) PoemImage.fromJson(i as Map<String, dynamic>)] : null,
      songs: songs is List
          ? [
              for (final s in songs.cast<Map<String, dynamic>>())
                if (s['approved'] != false && s['rejected'] != true) Song.fromJson(s),
            ]
          : null,
    );
  }
}

class Poem {
  const Poem({
    required this.id,
    required this.title,
    required this.fullTitle,
    required this.fullUrl,
    required this.plainText,
    required this.verses,
    this.recitations = const [],
    this.summary,
    this.category,
    this.next,
    this.previous,
    this.metre,
    this.rhyme,
    this.extras,
  });

  final int id;
  final String title;
  final String fullTitle;
  final String fullUrl;
  final String plainText;
  final List<Verse> verses;
  final List<Recitation> recitations;
  final LabeledText? summary;
  final PoetCat? category;
  final PoemRef? next;
  final PoemRef? previous;
  final String? metre;
  final String? rhyme;

  /// Null when the poem didn't come from Ganjoor's server (a downloaded pack, the static copy):
  /// the page then shows no extra panels, which couldn't load anyway.
  final PoemExtrasInfo? extras;

  String get siteUrl => 'https://ganjoor.net$fullUrl';

  Poem copyWith({List<Recitation>? recitations}) => Poem(
    id: id,
    title: title,
    fullTitle: fullTitle,
    fullUrl: fullUrl,
    plainText: plainText,
    verses: verses,
    recitations: recitations ?? this.recitations,
    summary: summary,
    category: category,
    next: next,
    previous: previous,
    metre: metre,
    rhyme: rhyme,
    extras: extras,
  );

  factory Poem.fromJson(Map<String, dynamic> j) {
    final sections = [for (final s in (j['sections'] as List? ?? const [])) s as Map<String, dynamic>];
    Map<String, dynamic>? main;
    for (final s in sections) {
      if (s['sectionType'] == 0) {
        main = s;
        break;
      }
    }
    main ??= sections.isEmpty ? null : sections.first;
    final rhyme = main?['rhymeLetters'] as String?;
    final category = j['category'] as Map<String, dynamic>?;
    return Poem(
      id: j['id'] as int,
      title: (j['title'] as String?) ?? '',
      fullTitle: (j['fullTitle'] as String?) ?? '',
      fullUrl: (j['fullUrl'] as String?) ?? '',
      plainText: (j['plainText'] as String?) ?? '',
      summary: LabeledText.parse(j['poemSummary'] as String?),
      // Some poems come with a partial category; read it only when both parts are present.
      category: category != null && category['poet'] is Map && category['cat'] is Map
          ? PoetCat.fromJson(category)
          : null,
      next: _ref(j['next']),
      previous: _ref(j['previous']),
      verses: [for (final v in (j['verses'] as List? ?? const [])) Verse.fromJson(v as Map<String, dynamic>)]
        ..sort((a, b) => a.vOrder.compareTo(b.vOrder)),
      recitations: [
        for (final r in (j['recitations'] as List? ?? const [])) Recitation.fromJson(r as Map<String, dynamic>),
      ]..sort((a, b) => a.audioOrder.compareTo(b.audioOrder)),
      metre: (main?['ganjoorMetre'] as Map<String, dynamic>?)?['rhythm'] as String?,
      rhyme: (rhyme == null || rhyme.isEmpty) ? null : rhyme,
      extras: PoemExtrasInfo.fromJson(j, main),
    );
  }
}

PoemRef? _ref(Object? o) => o is Map<String, dynamic> ? PoemRef.fromJson(o) : null;
