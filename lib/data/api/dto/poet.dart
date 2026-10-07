import '../../../core/net/api_client.dart' show kApiBase;

class Poet {
  const Poet({
    required this.id,
    required this.name,
    required this.nickname,
    required this.fullUrl,
    required this.rootCatId,
    this.imageUrl,
    this.description,
    this.birthYear,
    this.deathYear,
    this.pinOrder = 0,
    this.birthPlace,
    this.birthLatitude,
    this.birthLongitude,
  });

  final int id;
  final String name;
  final String nickname;
  final String fullUrl;
  final int rootCatId;
  final String? imageUrl;
  final String? description;
  final int? birthYear;
  final int? deathYear;
  final int pinOrder;

  /// Where the poet was born; coordinates are null when Ganjoor doesn't know them.
  final String? birthPlace;
  final double? birthLatitude;
  final double? birthLongitude;

  String? get imageAbsoluteUrl {
    final u = imageUrl;
    if (u == null || u.isEmpty) return null;
    return u.startsWith('http') ? u : '$kApiBase$u';
  }

  factory Poet.fromJson(Map<String, dynamic> j) => Poet(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    nickname: (j['nickname'] as String?) ?? (j['name'] as String?) ?? '',
    fullUrl: (j['fullUrl'] as String?) ?? '',
    rootCatId: (j['rootCatId'] as int?) ?? 0,
    imageUrl: j['imageUrl'] as String?,
    description: j['description'] as String?,
    birthYear: _year(j['birthYearInLHijri']),
    deathYear: _year(j['deathYearInLHijri']),
    pinOrder: (j['pinOrder'] as int?) ?? 0,
    birthPlace: j['birthPlace'] as String?,
    birthLatitude: _coord(j['birthPlaceLatitude']),
    birthLongitude: _coord(j['birthPlaceLongitude']),
  );
}

int? _year(Object? v) => v is int && v > 0 ? v : null;

/// 0 means "unknown" in Ganjoor's data (no poet was born at 0°, 0°).
double? _coord(Object? v) => v is num && v != 0 ? v.toDouble() : null;

class Century {
  const Century({required this.id, required this.name, required this.poets});

  /// Id 0 is the pinned/featured group (empty name).
  final int id;
  final String name;
  final List<Poet> poets;

  factory Century.fromJson(Map<String, dynamic> j) => Century(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    poets: [for (final p in (j['poets'] as List? ?? const [])) Poet.fromJson(p as Map<String, dynamic>)],
  );
}
