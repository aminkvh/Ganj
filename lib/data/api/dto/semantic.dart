/// Ganjoor's semantic ("by meaning") search: poems whose meaning matches a question,
/// with the verses that matched best.
class SemanticVerse {
  const SemanticVerse({required this.vOrder, required this.text});

  final int vOrder;
  final String text;

  factory SemanticVerse.fromJson(Map<String, dynamic> j) =>
      SemanticVerse(vOrder: (j['vOrder'] as int?) ?? 0, text: (j['text'] as String?) ?? '');
}

class SemanticHit {
  const SemanticHit({
    required this.poemId,
    required this.title,
    required this.fullTitle,
    required this.fullUrl,
    required this.verses,
    required this.score,
  });

  final int poemId;
  final String title;
  final String fullTitle;
  final String fullUrl;
  final List<SemanticVerse> verses;
  final double score;

  factory SemanticHit.fromJson(Map<String, dynamic> j) => SemanticHit(
    poemId: j['poemId'] as int,
    title: (j['title'] as String?) ?? '',
    fullTitle: (j['fullTitle'] as String?) ?? (j['title'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
    verses: [for (final v in (j['verses'] as List?) ?? const []) SemanticVerse.fromJson(v as Map<String, dynamic>)],
    score: ((j['score'] as num?) ?? 0).toDouble(),
  );
}

class SemanticResult {
  const SemanticResult({required this.results, this.detectedPoet, this.detectedCategory, this.logId});

  final List<SemanticHit> results;

  /// The poet / book Ganjoor guessed from the question («in which poem by Hafez…»), if any.
  final String? detectedPoet;
  final String? detectedCategory;

  /// Identifies this search when reporting which result was opened.
  final int? logId;

  factory SemanticResult.fromJson(Map<String, dynamic> j) => SemanticResult(
    results: [for (final r in (j['results'] as List?) ?? const []) SemanticHit.fromJson(r as Map<String, dynamic>)],
    detectedPoet: j['detectedPoetName'] as String?,
    detectedCategory: j['detectedCategoryName'] as String?,
    logId: j['logId'] as int?,
  );
}
