import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/force_layout.dart';
import 'package:ganj/features/shahnameh/data/relation_kinds.dart';

import 'sh_support.dart';

void main() {
  final w = realWorld;

  test("one step from Rostam: his kin and ties, and the edges among them", () {
    final g = neighbourhood(w, 60);
    expect(g.ids, containsAll([60, 54, 128, 198]));
    for (final e in g.edges) {
      expect(g.ids.contains(e.a) && g.ids.contains(e.b), isTrue);
    }
  });

  test('two steps reach further and include the first', () {
    final one = neighbourhood(w, 60).ids.toSet();
    final two = neighbourhood(w, 60, hops: 2).ids.toSet();
    expect(two.containsAll(one), isTrue);
    expect(two.length, greaterThan(one.length));
  });

  test('family filter: only kin', () {
    final g = neighbourhood(w, 60, families: {RelationFamily.kin});
    expect(g.edges.every((e) => e.kind.family == RelationFamily.kin), isTrue);
    expect(g.ids, contains(54));
    expect(g.ids, isNot(contains(198)), reason: 'Esfandiyar is an enemy, not kin');
  });

  test('the whole network is everyone with a tie', () {
    final g = neighbourhood(w, null);
    expect(g.ids.length, greaterThan(200));
  });

  test('layout is deterministic, finite, centred on the focus', () {
    final g = neighbourhood(w, 60, hops: 2);
    final a = forceLayout(g, center: 60), b = forceLayout(g, center: 60);
    expect(a, b);
    expect(a[60], (0.0, 0.0));
    for (final p in a.values) {
      expect(p.$1.isFinite && p.$2.isFinite, isTrue);
    }
  });

  test('people are spread out, not piled up', () {
    final g = neighbourhood(w, 60);
    final pos = forceLayout(g, center: 60).values.toList();
    var close = 0;
    for (var i = 0; i < pos.length; i++) {
      for (var j = i + 1; j < pos.length; j++) {
        final dx = pos[i].$1 - pos[j].$1, dy = pos[i].$2 - pos[j].$2;
        if (dx * dx + dy * dy < 0.0004) close++;
      }
    }
    expect(close, 0);
  });

  test('a lone person lays out alone', () {
    final g = neighbourhood(w, 999999);
    expect(g.ids, [999999]);
    expect(forceLayout(g, center: 999999), {999999: (0.0, 0.0)});
  });
}
