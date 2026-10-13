import 'dart:math' as math;

import '../../../core/text/persian_normalize.dart';
import 'models.dart';

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a));
}

String _key(String s) => normalizePersian(s).replaceAll('‌', '').replaceAll(' ', '');

/// Ganjoor's place tags onto Ganj's curated places: by Ganjoor's location id, else by the
/// same name within 20 km; anything else becomes a place of its own (`g<location id>`),
/// whose stories come from the tagged poems.
List<ShPlace> mergePlaces(
  List<ShPlace> curated,
  List<ShPlaceTag> tags, {
  List<String> Function(int poemId)? storiesOfPoem,
}) {
  final extra = <String, ShPlaceTag>{};
  final tagsOf = <String, List<ShPlaceTag>>{};
  final seen = <String>{};
  for (final t in tags) {
    if (!seen.add('${t.locationId}-${t.poemId}-${t.couplet}')) continue;
    ShPlace? home;
    for (final p in curated) {
      if (p.ganjoorId == t.locationId) {
        home = p;
        break;
      }
    }
    home ??= curated
        .where((p) => (_key(p.fa) == _key(t.name)) && haversineKm(p.lat, p.lng, t.lat, t.lng) <= 20)
        .firstOrNull;
    final id = home?.id ?? 'g${t.locationId}';
    if (home == null) extra[id] ??= t;
    tagsOf.putIfAbsent(id, () => []).add(t);
  }
  return [
    for (final p in curated) tagsOf.containsKey(p.id) ? p.copyWith(tags: [...p.tags, ...tagsOf[p.id]!]) : p,
    for (final MapEntry(key: id, value: t) in extra.entries)
      ShPlace(
        id: id,
        fa: t.name,
        en: t.name,
        lat: t.lat,
        lng: t.lng,
        region: 'other',
        precision: PlacePrecision.approx,
        ganjoorId: t.locationId,
        fromGanjoor: true,
        tags: tagsOf[id]!,
        stories: {
          if (storiesOfPoem != null)
            for (final tag in tagsOf[id]!) ...storiesOfPoem(tag.poemId),
        }.toList(),
      ),
  ];
}
