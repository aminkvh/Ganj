import 'dart:math' as math;
import 'dart:ui';

/// Pins that would overlap on screen, grouped: a few fan out in a small ring so each stays
/// tappable; more than [maxRing] become one bubble with a count (tap to zoom in) — a ring of
/// fifty would circle half the world.
class PinGroup {
  PinGroup(this.ids, this.centre, this.offsets);

  final List<String> ids;

  /// Screen position of the group (projected pixels).
  final Offset centre;

  /// Each pin's offset from its own place: zero alone, around [centre] in a ring.
  final List<Offset> offsets;

  bool get isBubble => offsets.isEmpty;
}

List<PinGroup> clusterPins(Map<String, Offset> px, {double size = 34, int maxRing = 5}) {
  final groups = <(Offset anchor, List<String> ids)>[];
  for (final MapEntry(key: id, value: p) in px.entries) {
    final i = groups.indexWhere((g) => (g.$1 - p).distance < size);
    i < 0 ? groups.add((p, [id])) : groups[i].$2.add(id);
  }
  return [
    for (final (anchor, ids) in groups)
      if (ids.length == 1)
        PinGroup(ids, px[ids.single]!, const [Offset.zero])
      else if (ids.length > maxRing)
        PinGroup(ids, _mean([for (final id in ids) px[id]!]), const [])
      else
        PinGroup(ids, anchor, [for (var k = 0; k < ids.length; k++) anchor + _ring(k, ids.length, size) - px[ids[k]]!]),
  ];
}

Offset _mean(List<Offset> ps) => ps.fold(Offset.zero, (a, b) => a + b) / ps.length.toDouble();

Offset _ring(int k, int n, double size) {
  final r = math.max(size * 0.8, n * size / (2 * math.pi) * 1.15);
  final a = 2 * math.pi * k / n - math.pi / 2;
  return Offset(r * math.cos(a), r * math.sin(a));
}
