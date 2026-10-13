import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/error_retry.dart';
import '../../../widgets/home_button.dart';
import '../data/models.dart';
import '../data/shahnameh_providers.dart';
import '../data/tree_layout.dart';
import 'person_sheet.dart';
import 'sh_style.dart';

const _slot = 124.0, _boxW = 108.0, _boxH = 48.0, _row = 100.0, _pad = 24.0;

/// `/shahnameh/tree/:id`: the family tree around one person.
class FamilyTreeScreen extends ConsumerWidget {
  const FamilyTreeScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final world = ref.watch(shahnamehWorldProvider);
    final w = world.value;
    final title = w == null ? '' : '${context.l10n.shFamilyTree} · ${personName(context, w, id)}';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [HomeButton()]),
      body: world.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(shahnamehWorldProvider)),
        data: (w) => FamilyTreeView(world: w, root: id),
      ),
    );
  }
}

/// Generations in rows, spouses side by side (double line), siblings without known parents
/// dotted, ancestors several generations up dashed with the count. Pan and zoom; opens
/// centred on [root].
class FamilyTreeView extends StatefulWidget {
  const FamilyTreeView({super.key, required this.world, required this.root});

  final ShWorld world;
  final int root;

  @override
  State<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends State<FamilyTreeView> {
  late TreeLayout _layout = layoutTree(widget.world, widget.root);
  final _transform = TransformationController();
  Size? _centredFor;

  @override
  void didUpdateWidget(FamilyTreeView old) {
    super.didUpdateWidget(old);
    if (old.root != widget.root || old.world != widget.world) {
      _layout = layoutTree(widget.world, widget.root);
      _centredFor = null;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Offset _centre(TreeNode n, bool rtl) {
    final x = rtl ? _layout.width - 1 - n.x : n.x;
    return Offset(_pad + x * _slot + _boxW / 2, _pad + n.gen * _row + _boxH / 2);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    if (_layout.nodes.isEmpty) {
      return Center(
        child: Text(l.shNoTies, style: TextStyle(color: c.muted)),
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final size = Size(_pad * 2 + _layout.width * _slot, _pad * 2 + _layout.gens * _row);
    final byId = {for (final n in _layout.nodes) n.id: n};
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.biggest;
        if (_centredFor != viewport) {
          _centredFor = viewport;
          final root = _centre(byId[widget.root]!, rtl);
          _transform.value = Matrix4.translationValues(viewport.width / 2 - root.dx, viewport.height / 3 - root.dy, 0);
        }
        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(400),
              minScale: 0.25,
              maxScale: 2.5,
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LinksPainter(
                          layout: _layout,
                          centre: (id) => _centre(byId[id]!, rtl),
                          ink: c.borderGold,
                          spouse: c.brandRed.withValues(alpha: 0.7),
                          label: TextStyle(color: c.muted, fontSize: 11, fontFamily: kBodyFont),
                          gapText: (n) => l.shGenerations(localDigits(n)),
                          textDirection: Directionality.of(context),
                        ),
                      ),
                    ),
                    for (final n in _layout.nodes)
                      Positioned(
                        left: _centre(n, rtl).dx - _boxW / 2,
                        top: _centre(n, rtl).dy - _boxH / 2,
                        width: _boxW,
                        height: _boxH,
                        child: _PersonBox(
                          key: ValueKey('tree-node-${n.id}'),
                          world: widget.world,
                          id: n.id,
                          root: n.id == widget.root,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: personName(context, widget.world, widget.root),
                onPressed: () => setState(() => _centredFor = null),
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonBox extends StatelessWidget {
  const _PersonBox({super.key, required this.world, required this.id, required this.root});

  final ShWorld world;
  final int id;
  final bool root;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final first = world.firstSection(id);
    final tint = first == null ? c.borderGold : ageTint(context, world.ageOfSection(first).index);
    final p = world.people[id]!;
    final en = isEn(context) ? p.en : null;
    return Material(
      color: root ? c.goldLight : c.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tint, width: root ? 2.5 : 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openPerson(context, id),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  en ?? p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink, fontWeight: root ? FontWeight.bold : FontWeight.w500, fontSize: 13),
                ),
                if (en != null)
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinksPainter extends CustomPainter {
  _LinksPainter({
    required this.layout,
    required this.centre,
    required this.ink,
    required this.spouse,
    required this.label,
    required this.gapText,
    required this.textDirection,
  });

  final TreeLayout layout;
  final Offset Function(int id) centre;
  final Color ink, spouse;
  final TextStyle label;
  final String Function(int) gapText;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = ink
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final l in layout.links) {
      final a = centre(l.from), b = centre(l.to);
      switch (l.kind) {
        case TreeLinkKind.parent:
          final from = a.translate(0, _boxH / 2), to = b.translate(0, -_boxH / 2);
          final bend = to.dy - _row / 2 + _boxH / 2;
          final path = Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(from.dx, bend)
            ..lineTo(to.dx, bend)
            ..lineTo(to.dx, to.dy);
          if (l.gap != null) {
            _dashed(canvas, path, line, const [6, 4]);
            final tp = TextPainter(
              text: TextSpan(text: gapText(l.gap!), style: label),
              textDirection: textDirection,
            )..layout();
            tp.paint(canvas, Offset(from.dx + 4, (from.dy + bend) / 2 - tp.height / 2));
          } else {
            canvas.drawPath(path, line);
          }
        case TreeLinkKind.spouse:
          final (left, right) = a.dx < b.dx ? (a, b) : (b, a);
          final p = Paint()
            ..color = spouse
            ..strokeWidth = 1.4;
          for (final dy in [-2.0, 2.0]) {
            canvas.drawLine(left.translate(_boxW / 2, dy), right.translate(-_boxW / 2, dy), p);
          }
        case TreeLinkKind.sibling:
          final (left, right) = a.dx < b.dx ? (a, b) : (b, a);
          final path = Path()
            ..moveTo(left.dx + _boxW / 2, left.dy)
            ..lineTo(right.dx - _boxW / 2, right.dy);
          _dashed(canvas, path, line, const [2, 3]);
      }
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint, List<double> dash) {
    for (final m in path.computeMetrics()) {
      var d = 0.0, on = true, i = 0;
      while (d < m.length) {
        final len = dash[i % dash.length];
        if (on) canvas.drawPath(m.extractPath(d, d + len), paint);
        d += len;
        on = !on;
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) => old.layout != layout || old.ink != ink;
}
