import 'dart:collection';
import 'dart:math' as math;

import 'models.dart';
import 'relation_kinds.dart';

/// Part of the people network: some people and the ties among them.
class NetGraph {
  const NetGraph(this.ids, this.edges);

  final List<int> ids;
  final List<ShEdge> edges;
}

/// The people within [hops] ties of [center] (whole network when null), through ties of
/// the given [families] only.
NetGraph neighbourhood(ShWorld w, int? center, {int hops = 1, Set<RelationFamily>? families}) {
  bool ok(ShEdge e) => families == null || families.contains(e.kind.family);
  final Set<int> ids;
  if (center == null) {
    ids = {
      for (final e in w.edges)
        if (ok(e)) ...[e.a, e.b],
    };
  } else {
    ids = {center};
    var frontier = [center];
    for (var h = 0; h < hops; h++) {
      final next = <int>[];
      for (final p in frontier) {
        for (final e in w.edgesOf(p)) {
          if (ok(e) && ids.add(e.other(p))) next.add(e.other(p));
        }
      }
      frontier = next;
    }
  }
  final seen = <String>{};
  final edges = [
    for (final e in w.edges)
      if (ok(e) && e.a != e.b && ids.contains(e.a) && ids.contains(e.b) && seen.add('${e.a}-${e.b}-${e.kind.key}')) e,
  ];
  return NetGraph(SplayTreeSet.of(ids).toList(), edges);
}

/// Fruchterman–Reingold in a unit square, seeded so the same graph always looks the same;
/// [center] is pinned at the origin. Positions are roughly within ±1.
Map<int, (double, double)> forceLayout(NetGraph g, {int? center, int iterations = 300, int seed = 7}) {
  final n = g.ids.length;
  if (n == 1) return {g.ids.single: (0.0, 0.0)};
  final rnd = math.Random(seed);
  final index = {for (final (i, id) in g.ids.indexed) id: i};
  final xs = List<double>.generate(n, (i) => math.cos(2 * math.pi * i / n) + (rnd.nextDouble() - 0.5) * 0.1);
  final ys = List<double>.generate(n, (i) => math.sin(2 * math.pi * i / n) + (rnd.nextDouble() - 0.5) * 0.1);
  final c = center == null ? null : index[center];
  if (c != null) {
    xs[c] = 0;
    ys[c] = 0;
  }
  final links = [for (final e in g.edges) (index[e.a]!, index[e.b]!)];
  final k = math.sqrt(4.0 / n);
  var t = 0.2;
  final dx = List<double>.filled(n, 0), dy = List<double>.filled(n, 0);
  for (var it = 0; it < iterations; it++) {
    dx.fillRange(0, n, 0);
    dy.fillRange(0, n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var ddx = xs[i] - xs[j], ddy = ys[i] - ys[j];
        var d2 = ddx * ddx + ddy * ddy;
        if (d2 < 1e-9) {
          ddx = (rnd.nextDouble() - 0.5) * 1e-3;
          ddy = (rnd.nextDouble() - 0.5) * 1e-3;
          d2 = ddx * ddx + ddy * ddy;
        }
        final f = k * k / d2; // repulsion / distance, applied to the unnormalised vector
        dx[i] += ddx * f;
        dy[i] += ddy * f;
        dx[j] -= ddx * f;
        dy[j] -= ddy * f;
      }
    }
    for (final (a, b) in links) {
      final ddx = xs[a] - xs[b], ddy = ys[a] - ys[b];
      final d = math.sqrt(ddx * ddx + ddy * ddy) + 1e-9;
      final f = d / k; // attraction d²/k, over d
      dx[a] -= ddx * f;
      dy[a] -= ddy * f;
      dx[b] += ddx * f;
      dy[b] += ddy * f;
    }
    // A weak pull to the middle keeps loose parts from drifting away.
    for (var i = 0; i < n; i++) {
      dx[i] -= xs[i] * 0.05;
      dy[i] -= ys[i] * 0.05;
    }
    for (var i = 0; i < n; i++) {
      if (i == c) continue;
      final d = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]) + 1e-9;
      final step = math.min(d, t);
      xs[i] += dx[i] / d * step;
      ys[i] += dy[i] / d * step;
    }
    t *= 0.985;
  }
  _gatherDetached(n, links, xs, ys);
  return {for (final (i, id) in g.ids.indexed) id: (xs[i], ys[i])};
}

/// Groups not tied to the main network drift far out in a force layout and squeeze it when the
/// view fits everything: bring each one in to sit just outside the main group, same direction.
void _gatherDetached(int n, List<(int, int)> links, List<double> xs, List<double> ys) {
  final group = List<int>.filled(n, -1);
  final next = <int, List<int>>{};
  for (final (a, b) in links) {
    next.putIfAbsent(a, () => []).add(b);
    next.putIfAbsent(b, () => []).add(a);
  }
  final groups = <List<int>>[];
  for (var i = 0; i < n; i++) {
    if (group[i] >= 0) continue;
    final members = <int>[i];
    group[i] = groups.length;
    for (var k = 0; k < members.length; k++) {
      for (final o in next[members[k]] ?? const <int>[]) {
        if (group[o] < 0) {
          group[o] = groups.length;
          members.add(o);
        }
      }
    }
    groups.add(members);
  }
  if (groups.length < 2) return;
  groups.sort((a, b) => b.length.compareTo(a.length));
  final main = groups.first;
  final cx = main.map((i) => xs[i]).reduce((a, b) => a + b) / main.length;
  final cy = main.map((i) => ys[i]).reduce((a, b) => a + b) / main.length;
  final radii = [for (final i in main) math.sqrt(math.pow(xs[i] - cx, 2) + math.pow(ys[i] - cy, 2))]..sort();
  final rim = radii[(radii.length * 0.9).floor().clamp(0, radii.length - 1)] * 1.1 + 0.05;
  for (final members in groups.skip(1)) {
    final gx = members.map((i) => xs[i]).reduce((a, b) => a + b) / members.length;
    final gy = members.map((i) => ys[i]).reduce((a, b) => a + b) / members.length;
    final d = math.sqrt(math.pow(gx - cx, 2) + math.pow(gy - cy, 2));
    if (d <= rim) continue;
    final f = rim / d;
    final dx = cx + (gx - cx) * f - gx, dy = cy + (gy - cy) * f - gy;
    for (final i in members) {
      xs[i] += dx;
      ys[i] += dy;
    }
  }
}

/// Pixels per layout unit so every position fits within 45% of [side] from the middle — a
/// few people settle far out, and "show all" must show them too.
double canvasScale(Map<int, (double, double)> pos, double side) {
  final extent = pos.values.fold(0.5, (m, p) => math.max(m, math.max(p.$1.abs(), p.$2.abs())));
  return side * 0.45 / extent;
}
