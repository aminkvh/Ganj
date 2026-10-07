/// A book on Ganjoor's home-page shelf: a section (category) of a poet's works.
class Book {
  const Book({required this.id, required this.name, required this.fullUrl, required this.poetName, this.poetId = 0});

  /// The category id: the book opens as `/cat/{id}`.
  final int id;
  final String name;
  final String fullUrl;
  final String poetName;
  final int poetId;

  factory Book.fromJson(Map<String, dynamic> j) => Book(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
    poetName: (j['poetName'] as String?) ?? '',
    poetId: (j['poetId'] as int?) ?? 0,
  );
}
