import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../data/force_layout.dart';
import '../data/models.dart';
import '../data/relation_kinds.dart';
import 'legend.dart';
import 'person_hover.dart';
import 'person_picker.dart';
import 'person_sheet.dart';
import 'sh_style.dart';
import 'zoom_controls.dart';

enum _Reach { one, two, all }

/// The people network, focused on one person (one or two steps out) or whole. Ties are
/// coloured and dashed by family. Tap a person to open them, focus on them or hide them;
/// add anyone by search; zoom out to see everything.
class NetworkView extends StatefulWidget {
  const NetworkView({super.key, required this.world, required this.focus});

  final ShWorld world;
  final int focus;

  @override
  State<NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<NetworkView> {
  late int _focus = widget.focus;
  _Reach _reach = _Reach.one;
  final _families = {...RelationFamily.values};
  late NetGraph _graph;
  Map<int, (double, double)>? _pos;
  int _job = 0;

  /// Taken out of / brought into the view by the reader.
  final _hidden = <int>{};
  final _added = <int>{};

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(NetworkView old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) {
      _focus = widget.focus;
      _rebuild();
    }
  }

  void _rebuild() {
    final base = neighbourhood(
      widget.world,
      _reach == _Reach.all ? null : _focus,
      hops: _reach == _Reach.two ? 2 : 1,
      families: _families,
    );
    final ids = {...base.ids, ..._added}..removeAll(_hidden);
    final edges = [
      ...base.edges.where((e) => ids.contains(e.a) && ids.contains(e.b)),
      // Ties of the people added by hand, to anyone in view.
      for (final a in _added)
        for (final e in widget.world.edgesOf(a))
          if (_families.contains(e.kind.family) && ids.contains(e.a) && ids.contains(e.b) && !base.edges.contains(e)) e,
    ];
    _graph = NetGraph((ids.toList()..sort()), edges.toSet().toList());
    final g = _graph;
    final job = ++_job;
    // Big graphs settle off the UI thread; small ones right away.
    if (g.ids.length <= 120) {
      _pos = forceLayout(g, center: g.ids.contains(_focus) ? _focus : null);
    } else {
      _pos = null;
      compute(_layoutIsolate, (g, g.ids.contains(_focus) ? _focus : null)).then((p) {
        if (mounted && job == _job) setState(() => _pos = p);
      });
    }
  }

  void _set(VoidCallback f) => setState(() {
    f();
    _rebuild();
  });

  Future<void> _add() async {
    final w = widget.world;
    final id = await pickPerson(context, w, where: (p) => w.edgesOf(p.id).isNotEmpty);
    if (id != null && mounted) {
      _set(() {
        _hidden.remove(id);
        _added.add(id);
      });
    }
  }

  /// Open, focus here, or hide — for the person tapped at [at] (global position).
  Future<void> _menu(int id, Offset at) async {
    final l = context.l10n;
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & box.size),
      items: [
        PopupMenuItem(enabled: false, child: Text(personName(context, widget.world, id))),
        PopupMenuItem(value: 'open', child: Text(l.shOpen)),
        if (id != _focus) PopupMenuItem(value: 'focus', child: Text(l.shFocusHere)),
        PopupMenuItem(value: 'hide', child: Text(l.shHide)),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        openPerson(context, id);
      case 'focus':
        _set(() {
          _focus = id;
          _hidden.remove(id);
          if (_reach == _Reach.all) _reach = _Reach.one;
        });
      case 'hide':
        _set(() {
          _hidden.add(id);
          _added.remove(id);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_Reach>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: _Reach.one, label: Text(l.shOneStep)),
                    ButtonSegment(value: _Reach.two, label: Text(l.shTwoSteps)),
                    ButtonSegment(value: _Reach.all, label: Text(l.shWholeNetwork)),
                  ],
                  selected: {_reach},
                  onSelectionChanged: (s) => _set(() => _reach = s.single),
                ),
              ),
              IconButton(tooltip: l.shAddPerson, icon: const Icon(Icons.person_add_alt), onPressed: _add),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final f in RelationFamily.values)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: FilterChip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(radius: 5, backgroundColor: familyColor(context, f)),
                    label: Text(familyLabel(l, f)),
                    selected: _families.contains(f),
                    showCheckmark: false,
                    onSelected: (on) => _set(() => on ? _families.add(f) : _families.remove(f)),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                l.shPeopleCount(localDigits(_graph.ids.length)),
                key: const ValueKey('network-count'),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_hidden.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('${l.shHidden}:', style: TextStyle(color: c.muted, fontSize: 12)),
                for (final id in _hidden)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: InputChip(
                      key: ValueKey('hidden-$id'),
                      visualDensity: VisualDensity.compact,
                      label: Text(personName(context, widget.world, id)),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => _set(() => _hidden.remove(id)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _pos == null
              ? const Center(child: CircularProgressIndicator())
              : _Canvas(
                  key: const ValueKey('network-canvas'),
                  world: widget.world,
                  graph: _graph,
                  pos: _pos!,
                  focus: _focus,
                  onTap: _menu,
                  onFocus: (id) => _set(() {
                    _focus = id;
                    if (_reach == _Reach.all) _reach = _Reach.one;
                  }),
                ),
        ),
      ],
    );
  }
}

Map<int, (double, double)> _layoutIsolate((NetGraph, int?) a) => forceLayout(a.$1, center: a.$2);

class _Canvas extends StatefulWidget {
  const _Canvas({
    super.key,
    required this.world,
    required this.graph,
    required this.pos,
    required this.focus,
    required this.onTap,
    required this.onFocus,
  });

  final ShWorld world;
  final NetGraph graph;
  final Map<int, (double, double)> pos;
  final int focus;

  /// A person tapped, with where (global position) — for the menu.
  final void Function(int id, Offset at) onTap;
  final ValueChanged<int> onFocus;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _ease = TransformAnimator(this, _transform);

  /// The viewport and canvas the view was last centred for; recentre when either changes.
  (Size, Size)? _centred;

  /// The person under the mouse (desktop), shown with a card.
  int? _hover;

  /// Names laid out once per graph, focus, language and theme — not on every frame.
  Map<int, (TextPainter, TextPainter)> _labels = const {};
  Object? _labelsFor;

  @override
  void dispose() {
    _ease.dispose();
    _transform.dispose();
    super.dispose();
  }

  Map<int, (TextPainter, TextPainter)> _labelsOf(BuildContext context, Set<int> labelled) {
    final c = context.ganj;
    final key = (widget.graph, widget.focus, Localizations.localeOf(context), c.ink, c.paper);
    if (key == _labelsFor) return _labels;
    _labelsFor = key;
    final dir = Directionality.of(context);
    final base = TextStyle(color: c.ink, fontSize: 11, fontFamily: kBodyFont);
    return _labels = {
      for (final id in labelled)
        id: () {
          final style = id == widget.focus ? base.copyWith(fontWeight: FontWeight.bold, fontSize: 13) : base;
          final name = personName(context, widget.world, id);
          final halo = TextPainter(
            text: TextSpan(
              text: name,
              style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..color = c.paper,
              ),
            ),
            textDirection: dir,
          )..layout(maxWidth: 120);
          final text = TextPainter(
            text: TextSpan(text: name, style: style),
            textDirection: dir,
          )..layout(maxWidth: 120);
          return (halo, text);
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final _Canvas(:world, :graph, :pos, :focus, :onTap, :onFocus) = widget;
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.biggest;
        final n = graph.ids.length;
        // Bigger networks get a bigger canvas; zoom out (or "show all") to see it whole.
        final side = math.max(math.min(box.maxWidth, box.maxHeight), 90.0 * math.sqrt(n));
        final size = Size(math.max(box.maxWidth, side), math.max(box.maxHeight, side));
        // Fit the layout's real extent inside the canvas (a few people settle far out).
        final k = canvasScale(pos, side);
        Offset at(int id) {
          final p = pos[id]!;
          return Offset(size.width / 2 + p.$1 * k, size.height / 2 + p.$2 * k);
        }

        final neighbours = {
          for (final e in graph.edges)
            if (e.a == focus || e.b == focus) e.other(focus),
        };
        final labelled = {
          for (final id in graph.ids)
            if (id == focus || n <= 40 || neighbours.contains(id) || (world.people[id]?.importance ?? 0) > 0) id,
        };
        int? hit(Offset local) {
          int? best;
          var bestD = 28.0 * 28.0;
          for (final id in graph.ids) {
            final d = (at(id) - local).distanceSquared;
            if (d < bestD) {
              bestD = d;
              best = id;
            }
          }
          return best;
        }

        final painter = _NetPainter(
          graph: graph,
          at: at,
          focus: focus,
          importance: (id) => world.people[id]?.importance ?? 0,
          labels: _labelsOf(context, labelled),
          edgeColor: (f) => familyColor(context, f),
          node: c.paper,
          nodeBorder: c.gold,
          focusFill: c.brandRed,
          hover: _hover,
        );
        final minScale = fitMinScale(viewport, size);
        if (_centred != (viewport, size)) {
          _centred = (viewport, size);
          _transform.value = Matrix4.translationValues(
            (viewport.width - size.width) / 2,
            (viewport.height - size.height) / 2,
            0,
          );
        }
        return Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              minScale: minScale,
              maxScale: 3,
              boundaryMargin: EdgeInsets.all(math.max(viewport.width, viewport.height)),
              transformationController: _transform,
              child: MouseRegion(
                onHover: (e) {
                  final id = hit(e.localPosition);
                  if (id != _hover) setState(() => _hover = id);
                },
                onExit: (_) {
                  if (_hover != null) setState(() => _hover = null);
                },
                child: GestureDetector(
                  onTapUp: (d) {
                    final id = hit(d.localPosition);
                    if (id != null) onTap(id, d.globalPosition);
                  },
                  onLongPressStart: (d) {
                    final id = hit(d.localPosition);
                    if (id != null) onFocus(id);
                  },
                  // Panning moves one picture instead of redrawing every tie and name.
                  child: AnimatedSwitcher(
                    // A new set of people cross-fades in rather than jumping.
                    duration: const Duration(milliseconds: 220),
                    child: RepaintBoundary(
                      key: ValueKey(graph),
                      child: CustomPaint(key: const ValueKey('network-paint'), size: size, painter: painter),
                    ),
                  ),
                ),
              ),
            ),
            if (_hover case final id? when pos.containsKey(id))
              () {
                // Beside the person, kept inside the view.
                final p = MatrixUtils.transformPoint(_transform.value, at(id));
                return Positioned(
                  left: (p.dx + 18).clamp(4, math.max(4, viewport.width - 290)),
                  top: (p.dy + 12).clamp(4, math.max(4, viewport.height - 200)),
                  child: IgnorePointer(
                    child: PersonHoverCard(world: world, id: id),
                  ),
                );
              }(),
            const PositionedDirectional(top: 10, start: 10, child: LegendToggle(legend: NetworkLegend())),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: ZoomControls(
                onZoomIn: () => _ease.to(zoomedBy(_transform.value, 1.4, viewport, min: minScale, max: 3)),
                onZoomOut: () => _ease.to(zoomedBy(_transform.value, 1 / 1.4, viewport, min: minScale, max: 3)),
                onShowAll: () => _ease.to(fitMatrix(viewport, size)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NetPainter extends CustomPainter {
  _NetPainter({
    required this.graph,
    required this.at,
    required this.focus,
    required this.importance,
    required this.labels,
    required this.edgeColor,
    required this.node,
    required this.nodeBorder,
    required this.focusFill,
    this.hover,
  });

  final int? hover;
  final NetGraph graph;
  final Offset Function(int) at;
  final int focus;
  final int Function(int) importance;

  /// Prepared names (halo, text) of the people to label.
  final Map<int, (TextPainter, TextPainter)> labels;
  final Color Function(RelationFamily) edgeColor;
  final Color node, nodeBorder, focusFill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in graph.edges) {
      final touchesFocus = e.a == focus || e.b == focus;
      final p = Paint()
        ..color = edgeColor(e.kind.family).withValues(alpha: touchesFocus ? 0.9 : 0.4)
        ..strokeWidth = touchesFocus ? 1.8 : 1
        ..style = PaintingStyle.stroke;
      final a = at(e.a), b = at(e.b);
      final dash = familyDash(e.kind.family);
      if (dash == null) {
        canvas.drawLine(a, b, p);
      } else {
        final len = (b - a).distance;
        final dir = (b - a) / (len == 0 ? 1 : len);
        var d = 0.0;
        var on = true;
        var i = 0;
        while (d < len) {
          final step = dash[i % dash.length];
          if (on) canvas.drawLine(a + dir * d, a + dir * math.min(d + step, len), p);
          d += step;
          on = !on;
          i++;
        }
      }
    }
    if (hover case final h? when graph.ids.contains(h)) {
      // The hovered person's ties, drawn again on top.
      for (final e in graph.edges) {
        if (e.a != h && e.b != h) continue;
        canvas.drawLine(
          at(e.a),
          at(e.b),
          Paint()
            ..color = edgeColor(e.kind.family)
            ..strokeWidth = 2.6,
        );
      }
    }
    for (final id in graph.ids) {
      final o = at(id);
      final r = id == focus ? 13.0 : 5.0 + importance(id) * 3;
      if (id == hover) {
        canvas.drawCircle(o, r + 5, Paint()..color = nodeBorder.withValues(alpha: 0.35));
      }
      canvas.drawCircle(o, r, Paint()..color = id == focus ? focusFill : node);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = nodeBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    // Names last, each on a halo of paper, so ties never strike through them.
    for (final MapEntry(key: id, value: (halo, text)) in labels.entries) {
      if (!graph.ids.contains(id)) continue;
      final o = at(id);
      final r = id == focus ? 13.0 : 5.0 + importance(id) * 3;
      final top = o + Offset(0, r + 2);
      halo.paint(canvas, top - Offset(halo.width / 2, 0));
      text.paint(canvas, top - Offset(text.width / 2, 0));
    }
  }

  @override
  bool shouldRepaint(_NetPainter old) =>
      old.graph != graph ||
      old.focus != focus ||
      old.hover != hover ||
      old.labels != labels ||
      old.node != node ||
      old.focusFill != focusFill;
}
