import 'poet.dart';

class CatRef {
  const CatRef({required this.id, required this.title, required this.urlSlug, required this.fullUrl});

  final int id;
  final String title;
  final String urlSlug;
  final String fullUrl;

  factory CatRef.fromJson(Map<String, dynamic> j) => CatRef(
    id: j['id'] as int,
    title: (j['title'] as String?) ?? '',
    urlSlug: (j['urlSlug'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
  );
}

class PoemRef {
  const PoemRef({required this.id, required this.title, required this.urlSlug, required this.excerpt});

  final int id;
  final String title;
  final String urlSlug;
  final String excerpt;

  factory PoemRef.fromJson(Map<String, dynamic> j) => PoemRef(
    id: j['id'] as int,
    title: (j['title'] as String?) ?? '',
    urlSlug: (j['urlSlug'] as String?) ?? '',
    excerpt: (j['excerpt'] as String?) ?? '',
  );
}

class Cat {
  const Cat({
    required this.id,
    required this.title,
    required this.fullUrl,
    this.description,
    this.ancestors = const [],
    this.children = const [],
    this.poems = const [],
  });

  final int id;
  final String title;
  final String fullUrl;
  final String? description;
  final List<CatRef> ancestors;
  final List<CatRef> children;
  final List<PoemRef> poems;

  factory Cat.fromJson(Map<String, dynamic> j) => Cat(
    id: j['id'] as int,
    title: (j['title'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
    description: j['description'] as String?,
    ancestors: [for (final a in (j['ancestors'] as List? ?? const [])) CatRef.fromJson(a as Map<String, dynamic>)],
    children: [for (final c in (j['children'] as List? ?? const [])) CatRef.fromJson(c as Map<String, dynamic>)],
    poems: [for (final p in (j['poems'] as List? ?? const [])) PoemRef.fromJson(p as Map<String, dynamic>)],
  );
}

/// Shape of /poet/{id}, /cat/{id} and poem.category.
class PoetCat {
  const PoetCat({required this.poet, required this.cat});

  final Poet poet;
  final Cat cat;

  factory PoetCat.fromJson(Map<String, dynamic> j) => PoetCat(
    poet: Poet.fromJson(j['poet'] as Map<String, dynamic>),
    cat: Cat.fromJson(j['cat'] as Map<String, dynamic>),
  );
}
