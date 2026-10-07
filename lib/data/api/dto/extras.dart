import '../../../core/text/html_text.dart';

/// Manuscript page image (links to museum.ganjoor.net).
class PoemImage {
  const PoemImage({required this.thumb, required this.target, required this.alt});

  final String thumb;
  final String target;
  final String alt;

  factory PoemImage.fromJson(Map<String, dynamic> j) => PoemImage(
    thumb: (j['thumbnailImageUrl'] as String?) ?? '',
    target: (j['targetPageUrl'] as String?) ?? '',
    alt: (j['altText'] as String?) ?? '',
  );
}

/// A sung version of the poem on an external service (BeepTunes, Spotify, Golha…).
class Song {
  const Song({
    required this.artist,
    required this.track,
    required this.album,
    required this.url,
    required this.trackType,
  });

  final String artist;
  final String track;
  final String album;
  final String url;
  final int trackType;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
    artist: (j['artistName'] as String?) ?? '',
    track: (j['trackName'] as String?) ?? '',
    album: (j['albumName'] as String?) ?? '',
    url: (j['trackUrl'] as String?) ?? '',
    trackType: (j['trackType'] as int?) ?? 0,
  );
}

/// A reader's note on the poem (حاشیه); read-only here.
class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.date,
    required this.text,
    required this.coupletIndex,
    required this.replies,
  });

  final int id;
  final String author;
  final DateTime? date;
  final String text;

  /// -1 when about the whole poem.
  final int coupletIndex;
  final List<Comment> replies;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: j['id'] as int,
    author: (j['authorName'] as String?) ?? '',
    date: DateTime.tryParse((j['commentDate'] as String?) ?? ''),
    text: htmlToText((j['htmlComment'] as String?) ?? ''),
    coupletIndex: (j['coupletIndex'] as int?) ?? -1,
    replies: [for (final r in (j['replies'] as List? ?? const [])) Comment.fromJson(r as Map<String, dynamic>)],
  );
}

/// A couplet of this poem quoted in (or quoting) another poem.
class Quoted {
  const Quoted({
    required this.poetName,
    required this.fullTitle,
    required this.fullUrl,
    required this.relatedPoemId,
    required this.verse1,
    required this.verse2,
    required this.relatedVerse1,
    required this.relatedVerse2,
  });

  final String poetName;
  final String fullTitle;
  final String fullUrl;
  final int? relatedPoemId;
  final String verse1;
  final String verse2;
  final String relatedVerse1;
  final String relatedVerse2;

  factory Quoted.fromJson(Map<String, dynamic> j) => Quoted(
    poetName: (j['cachedRelatedPoemPoetName'] as String?) ?? '',
    fullTitle: (j['cachedRelatedPoemFullTitle'] as String?) ?? '',
    fullUrl: (j['cachedRelatedPoemFullUrl'] as String?) ?? '',
    relatedPoemId: j['relatedPoemId'] as int?,
    verse1: (j['coupletVerse1'] as String?) ?? '',
    verse2: (j['coupletVerse2'] as String?) ?? '',
    relatedVerse1: (j['relatedCoupletVerse1'] as String?) ?? '',
    relatedVerse2: (j['relatedCoupletVerse2'] as String?) ?? '',
  );
}

/// A poem with the same metre and rhyme by another poet (Ganjoor "related").
class Related {
  const Related({
    required this.poetName,
    required this.poetImageUrl,
    required this.fullTitle,
    required this.fullUrl,
    required this.excerpt,
  });

  final String poetName;
  final String poetImageUrl;
  final String fullTitle;
  final String fullUrl;
  final String excerpt;

  factory Related.fromJson(Map<String, dynamic> j) => Related(
    poetName: (j['poetName'] as String?) ?? '',
    poetImageUrl: (j['poetImageUrl'] as String?) ?? '',
    fullTitle: (j['fullTitle'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
    excerpt: htmlToText((j['htmlExcerpt'] as String?) ?? ''),
  );
}

class Rhythm {
  const Rhythm({required this.id, required this.rhythm, required this.verseCount});

  final int id;
  final String rhythm;
  final int verseCount;

  factory Rhythm.fromJson(Map<String, dynamic> j) =>
      Rhythm(id: j['id'] as int, rhythm: (j['rhythm'] as String?) ?? '', verseCount: (j['verseCount'] as int?) ?? 0);
}

/// A poem in a similar-poems listing.
class PoemHit {
  const PoemHit({required this.id, required this.title, required this.fullTitle, required this.excerpt});

  final int id;
  final String title;
  final String fullTitle;
  final String excerpt;

  factory PoemHit.fromJson(Map<String, dynamic> j) => PoemHit(
    id: j['id'] as int,
    title: (j['title'] as String?) ?? '',
    fullTitle: (j['fullTitle'] as String?) ?? '',
    excerpt: ((j['plainText'] as String?) ?? '')
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
  );
}
