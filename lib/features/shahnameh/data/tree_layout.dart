import 'dart:collection';
import 'dart:math' as math;

import 'models.dart';

/// A family tree laid out in rows: one row per generation, every person exactly once.
/// x is in slot units (one person box per slot); [TreeLayout.width] slots in all.
class TreeNode {
  TreeNode(this.id, this.gen);

  final int id;
  final int gen;
  double x = 0;
}

enum TreeLinkKind { parent, spouse, sibling }

class TreeLink {
  const TreeLink(this.from, this.to, this.kind, {this.gap});

  /// For [TreeLinkKind.parent]: from the elder to the younger.
  final int from, to;
  final TreeLinkKind kind;

  /// Generations between them when more than one (an ancestor several rows up).
  final int? gap;
}

class TreeLayout {
  const TreeLayout(this.nodes, this.links, this.gens, this.width);

  final List<TreeNode> nodes;
  final List<TreeLink> links;
  final int gens;
  final double width;
}

/// Ganjoor's kinship graph is not a strict tree (two parents with their own lines, siblings
/// without parents, ancestors with unknown gaps, even loops), so: walk outwards from [rootId]
/// giving each person a generation the first time they're reached; hang each person under one
/// "primary" parent; put spouses and parentless siblings beside the person who led to them;
/// then lay subtrees side by side with parents centred over their children.
TreeLayout layoutTree(ShWorld w, int rootId) {
  final kin = [
    for (final e in w.edges)
      if (e.kind.isKin) e,
  ];
  if (!kin.any((e) => e.a == rootId || e.b == rootId)) return const TreeLayout([], [], 0, 0);
  final byPerson = <int, List<ShEdge>>{};
  for (final e in kin) {
    byPerson.putIfAbsent(e.a, () => []).add(e);
    byPerson.putIfAbsent(e.b, () => []).add(e);
  }
  // Parent and ancestor edges before spouses and siblings, so lines are found first.
  int rank(ShEdge e) => switch (e.kind.key) {
    'R:0' => 0,
    'R:3' => 1,
    'R:2' => 2,
    _ => 3,
  };
  for (final l in byPerson.values) {
    l.sort((a, b) => rank(a).compareTo(rank(b)));
  }

  final gen = <int, int>{rootId: 0};
  final order = <int>[rootId];
  final parentOf = <int, int>{};
  final besideOf = <int, int>{};
  void visit(int cur, ShEdge e) {
    final o = e.other(cur);
    final step = e.kind.key == 'R:3' ? (e.degree ?? 2) : 1;
    switch (e.kind.key) {
      case 'R:0' || 'R:3':
        if (e.a == cur) {
          gen[o] = gen[cur]! + step;
          parentOf[o] = cur;
        } else {
          gen[o] = gen[cur]! - step;
        }
      default:
        gen[o] = gen[cur]!;
        besideOf[o] = cur;
    }
    order.add(o);
  }

  // Direct ties (parent, spouse, sibling) give exact generations, so they are walked first;
  // an ancestor tie — its gap often unknown — only reaches people the direct ties can't.
  final queue = Queue<int>()..add(rootId);
  final reached = <int>[];
  while (queue.isNotEmpty) {
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      reached.add(cur);
      for (final e in byPerson[cur]!) {
        if (e.kind.key == 'R:3' || gen.containsKey(e.other(cur))) continue;
        visit(cur, e);
        queue.add(e.other(cur));
      }
    }
    for (final cur in reached) {
      for (final e in byPerson[cur]!) {
        if (e.kind.key != 'R:3' || gen.containsKey(e.other(cur))) continue;
        visit(cur, e);
        queue.add(e.other(cur));
      }
    }
    reached.clear();
  }

  // Someone reached going upwards may still have a parent of their own in the tree; and a
  // direct parent beats an ancestor (edges are sorted parent-first).
  for (final p in order) {
    if (parentOf[p] case final q? when kin.any((e) => e.kind.key == 'R:0' && e.a == q && e.b == p)) continue;
    for (final e in byPerson[p]!) {
      if ((e.kind.key == 'R:0' || e.kind.key == 'R:3') && e.b == p && gen[e.a]! < gen[p]!) {
        parentOf[p] = e.a;
        besideOf.remove(p);
        break;
      }
    }
  }

  // Spouses and siblings who have no parent here sit beside their anchor.
  int anchor(int p) {
    var a = p;
    final seen = <int>{};
    while (besideOf.containsKey(a) && !parentOf.containsKey(a) && seen.add(a)) {
      a = besideOf[a]!;
    }
    return a;
  }

  final beside = <int, List<int>>{};
  final roots = <int>[];
  for (final p in order) {
    if (parentOf.containsKey(p)) continue;
    final a = anchor(p);
    if (a != p) {
      beside.putIfAbsent(a, () => []).add(p);
    } else {
      roots.add(p);
    }
  }
  final children = <int, List<int>>{};
  for (final p in order) {
    final parent = parentOf[p];
    if (parent == null) continue;
    // A child of someone sitting beside an anchor hangs from the anchor's block.
    final host = parentOf.containsKey(parent) || !besideOf.containsKey(parent) ? parent : anchor(parent);
    children.putIfAbsent(host, () => []).add(p);
  }

  final nodes = {for (final p in order) p: TreeNode(p, gen[p]!)};
  void shift(int p, double dx) {
    nodes[p]!.x += dx;
    for (final s in beside[p] ?? const <int>[]) {
      nodes[s]!.x += dx;
    }
    for (final k in children[p] ?? const <int>[]) {
      shift(k, dx);
    }
  }

  // Returns the width of p's subtree, laid out from slot [left].
  double place(int p, double left) {
    final sats = beside[p] ?? const <int>[];
    final unit = 1.0 + sats.length;
    final kids = children[p] ?? const <int>[];
    var span = 0.0;
    for (final k in kids) {
      span += place(k, left + span);
    }
    final total = math.max(span, unit);
    if (kids.isNotEmpty && span < unit) {
      for (final k in kids) {
        shift(k, (unit - span) / 2);
      }
    }
    double x;
    if (kids.isEmpty) {
      x = left;
    } else {
      final xs = [for (final k in kids) nodes[k]!.x];
      final mid = (xs.reduce(math.min) + xs.reduce(math.max)) / 2;
      x = (mid - (unit - 1) / 2).clamp(left, left + total - unit);
    }
    nodes[p]!.x = x;
    for (final (i, s) in sats.indexed) {
      nodes[s]!.x = x + 1 + i;
    }
    return total;
  }

  var width = 0.0;
  for (final r in roots) {
    width += place(r, width);
  }

  final top = gen.values.reduce(math.min);
  final laid = [for (final p in order) TreeNode(p, gen[p]! - top)..x = nodes[p]!.x];
  final links = <TreeLink>[];
  final drawn = <String>{};
  for (final e in kin) {
    if (!gen.containsKey(e.a) || !gen.containsKey(e.b) || e.a == e.b) continue;
    final pair = e.a < e.b ? '${e.a}-${e.b}' : '${e.b}-${e.a}';
    if (!drawn.add('$pair-${e.kind.key}')) continue;
    switch (e.kind.key) {
      case 'R:0' || 'R:3':
        final (elder, younger) = gen[e.a]! <= gen[e.b]! ? (e.a, e.b) : (e.b, e.a);
        final d = gen[younger]! - gen[elder]!;
        links.add(TreeLink(elder, younger, TreeLinkKind.parent, gap: d > 1 ? d : null));
      case 'R:2':
        links.add(TreeLink(e.a, e.b, TreeLinkKind.spouse));
      default:
        links.add(TreeLink(e.a, e.b, TreeLinkKind.sibling));
    }
  }
  return TreeLayout(laid, links, gen.values.reduce(math.max) - top + 1, width);
}
