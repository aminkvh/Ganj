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
import 'person_sheet.dart';
import 'sh_style.dart';

enum _Reach { one, two, all }

/// The people network, focused on one person (one or two steps out) or whole. Ties are
/// coloured and dashed by family; tap a person to open them, long-press to refocus.
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
    _graph = neighbourhood(
      widget.world,
      _reach == _Reach.all ? null : _focus,
      hops: _reach == _Reach.two ? 2 : 1,
      families: _families,
    );
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
        Expanded(
          child: _pos == null
              ? const Center(child: CircularProgressIndicator())
              : _Canvas(
                  key: const ValueKey('network-canvas'),
                  world: widget.world,
                  graph: _graph,
                  pos: _pos!,
                  focus: _focus,
                  onOpen: (id) => openPerson(context, id),
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
    required this.onOpen,
    required this.onFocus,
  });

  final ShWorld world;
  final NetGraph graph;
  final Map<int, (double, double)> pos;
  final int focus;
  final ValueChanged<int> onOpen, onFocus;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  final _transform = TransformationController();

  /// The viewport and canvas the view was last centred for; recentre when either changes.
  (Size, Size)? _centred;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final _Canvas(:world, :graph, :pos, :focus, :onOpen, :onFocus) = widget;
    return LayoutBuilder(
      builder: (context, box) {
        final n = graph.ids.length;
        // Bigger networks get a bigger canvas to pan around; small ones fit the screen.
        final side = math.max(math.min(box.maxWidth, box.maxHeight), 90.0 * math.sqrt(n));
        final size = Size(math.max(box.maxWidth, side), math.max(box.maxHeight, side));
        Offset at(int id) {
          final p = pos[id]!;
          return Offset(size.width / 2 + p.$1 * side * 0.42, size.height / 2 + p.$2 * side * 0.42);
        }

        final neighbours = {
          for (final e in graph.edges)
            if (e.a == focus || e.b == focus) e.other(focus),
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
          labelled: (id) =>
              id == focus || n <= 40 || neighbours.contains(id) || (world.people[id]?.importance ?? 0) > 0,
          name: (id) => personName(context, world, id),
          edgeColor: (f) => familyColor(context, f),
          node: c.paper,
          nodeBorder: c.gold,
          focusFill: c.brandRed,
          text: TextStyle(color: c.ink, fontSize: 11, fontFamily: kBodyFont),
          textDirection: Directionality.of(context),
        );
        final canvas = GestureDetector(
          onTapUp: (d) {
            final id = hit(d.localPosition);
            if (id != null) onOpen(id);
          },
          onLongPressStart: (d) {
            final id = hit(d.localPosition);
            if (id != null) onFocus(id);
          },
          child: CustomPaint(size: size, painter: painter),
        );
        final fits = size.width <= box.maxWidth + 0.5 && size.height <= box.maxHeight + 0.5;
        if (fits) return canvas;
        if (_centred != (box.biggest, size)) {
          _centred = (box.biggest, size);
          _transform.value = Matrix4.translationValues(
            (box.maxWidth - size.width) / 2,
            (box.maxHeight - size.height) / 2,
            0,
          );
        }
        return InteractiveViewer(
          constrained: false,
          minScale: 0.3,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(200),
          transformationController: _transform,
          child: canvas,
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
    required this.labelled,
    required this.name,
    required this.edgeColor,
    required this.node,
    required this.nodeBorder,
    required this.focusFill,
    required this.text,
    required this.textDirection,
  });

  final NetGraph graph;
  final Offset Function(int) at;
  final int focus;
  final int Function(int) importance;
  final bool Function(int) labelled;
  final String Function(int) name;
  final Color Function(RelationFamily) edgeColor;
  final Color node, nodeBorder, focusFill;
  final TextStyle text;
  final TextDirection textDirection;

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
    for (final id in graph.ids) {
      final o = at(id);
      final r = id == focus ? 13.0 : 5.0 + importance(id) * 3;
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
    for (final id in graph.ids) {
      if (!labelled(id)) continue;
      final o = at(id);
      final r = id == focus ? 13.0 : 5.0 + importance(id) * 3;
      final style = id == focus ? text.copyWith(fontWeight: FontWeight.bold, fontSize: 13) : text;
      final at0 = o + Offset(0, r + 2);
      final halo = TextPainter(
        text: TextSpan(
          text: name(id),
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = node,
          ),
        ),
        textDirection: textDirection,
      )..layout(maxWidth: 120);
      final tp = TextPainter(
        text: TextSpan(text: name(id), style: style),
        textDirection: textDirection,
      )..layout(maxWidth: 120);
      halo.paint(canvas, at0 - Offset(halo.width / 2, 0));
      tp.paint(canvas, at0 - Offset(tp.width / 2, 0));
    }
  }

  @override
  // Names and colours follow the language and theme, which the graph alone doesn't show.
  bool shouldRepaint(_NetPainter old) => true;
}
