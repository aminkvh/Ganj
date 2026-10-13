import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/relation_kinds.dart';
import 'package:ganj/features/shahnameh/data/tree_layout.dart';

import 'sh_support.dart';

/// A world of just these people and kin edges `(a, b, 'R', type, degree)`.
ShWorld tiny(List<(int, int, int, int?)> edges, {Map<int, int> gender = const {}}) {
  final ids = {
    for (final e in edges) ...[e.$1, e.$2],
  };
  return ShWorld(
    builtAt: '',
    people: {for (final i in ids) i: ShPerson(id: i, name: 'p$i', gender: gender[i] ?? 1)},
    edges: [for (final e in edges) ShEdge(e.$1, e.$2, relationKind('R', e.$3), degree: e.$4)],
    sections: const [],
    presence: const {},
    passing: const {},
    poemPeople: const {},
    summaries: const {},
    ages: const [],
    places: const [],
    routes: const [],
    ganjoorTags: const [],
    treeRoots: const [],
  );
}

void main() {
  TreeNode node(TreeLayout t, int id) => t.nodes.firstWhere((n) => n.id == id);

  void noOverlap(TreeLayout t) {
    final cells = <(int, double)>{};
    for (final n in t.nodes) {
      expect(cells.add((n.gen, n.x)), isTrue, reason: 'two people in one cell at gen ${n.gen}, x ${n.x}');
    }
  }

  test('parents above children, children centred under them', () {
    // 1 → 2, 3 ; 2 → 4
    final t = layoutTree(tiny([(1, 2, 0, null), (1, 3, 0, null), (2, 4, 0, null)]), 1);
    expect(node(t, 1).gen, 0);
    expect(node(t, 2).gen, 1);
    expect(node(t, 4).gen, 2);
    expect(node(t, 1).x, inInclusiveRange(node(t, 2).x, node(t, 3).x));
    noOverlap(t);
  });

  test('starting from a child still puts the parents on top', () {
    final t = layoutTree(tiny([(1, 2, 0, null), (2, 3, 0, null)]), 3);
    expect(node(t, 1).gen, 0);
    expect(node(t, 3).gen, 2);
  });

  test('spouses share a row, side by side', () {
    // 1 ♥ 5 ; 1 → 2
    final t = layoutTree(tiny([(1, 5, 2, null), (1, 2, 0, null)]), 1);
    expect(node(t, 5).gen, node(t, 1).gen);
    expect((node(t, 5).x - node(t, 1).x).abs(), 1);
    expect(t.links.where((l) => l.kind == TreeLinkKind.spouse), hasLength(1));
    noOverlap(t);
  });

  test('a known number of generations to an ancestor is kept as a gap', () {
    final t = layoutTree(tiny([(1, 2, 3, 3)]), 2);
    expect(node(t, 2).gen - node(t, 1).gen, 3);
    expect(t.links.single.gap, 3);
  });

  test('an ancestor without a known distance sits two rows up', () {
    final t = layoutTree(tiny([(1, 2, 3, null)]), 1);
    expect(node(t, 2).gen - node(t, 1).gen, 2);
  });

  test('a cycle in the data ends, and everyone appears once', () {
    final t = layoutTree(tiny([(1, 2, 0, null), (2, 1, 0, null), (2, 3, 0, null), (3, 1, 0, null)]), 1);
    expect(t.nodes.map((n) => n.id).toSet(), {1, 2, 3});
    expect(t.nodes, hasLength(3));
  });

  test('a child with two parents who both have ancestors is drawn once', () {
    // 10 → 1, 20 → 2, 1 ♥ 2, 1 → 3, 2 → 3
    final t = layoutTree(
      tiny([(10, 1, 0, null), (20, 2, 0, null), (1, 2, 2, null), (1, 3, 0, null), (2, 3, 0, null)]),
      3,
    );
    expect(t.nodes.where((n) => n.id == 3), hasLength(1));
    noOverlap(t);
  });

  test('siblings without known parents share the row', () {
    final t = layoutTree(tiny([(1, 2, 1, null)]), 1);
    expect(node(t, 1).gen, node(t, 2).gen);
    expect(t.links.single.kind, TreeLinkKind.sibling);
  });

  test('a person with no kin is a tree of one', () {
    final t = layoutTree(tiny([(1, 2, 0, null)]), 99);
    expect(t.nodes, isEmpty);
  });

  test("the real trees: Kayumars' line and Rostam's house lay out cleanly", () {
    for (final root in [1, 60]) {
      final t = layoutTree(realWorld, root);
      expect(t.nodes.length, greaterThan(5), reason: 'root $root');
      expect(t.nodes.map((n) => n.id).toSet().length, t.nodes.length);
      noOverlap(t);
      expect(t.width, greaterThan(0));
    }
    final rostam = layoutTree(realWorld, 60);
    expect(node(rostam, 54).gen, node(rostam, 60).gen - 1, reason: 'Zal is a generation above Rostam');
  });

  test('a direct parent wins over an ancestor reached first', () {
    // 1 →(ancestor, gap unknown) 4 ; 1 → 2 → 3 → 4: 4 hangs under 3, three rows below 1.
    final t = layoutTree(tiny([(1, 4, 3, null), (1, 2, 0, null), (2, 3, 0, null), (3, 4, 0, null)]), 1);
    expect(node(t, 4).gen, node(t, 3).gen + 1);
    expect(node(t, 4).gen - node(t, 1).gen, 3);
    expect(
      t.links.where((l) => l.kind == TreeLinkKind.parent && l.from == 3 && l.to == 4 && l.gap == null),
      hasLength(1),
    );
  });

  test("in Rostam's house, Rostam is Zal's son, a row below him", () {
    final t = layoutTree(realWorld, 64);
    expect(node(t, 60).gen, node(t, 54).gen + 1);
  });
}
