import 'dart:math' as math;

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
import 'legend.dart';
import 'person_hover.dart';
import 'person_sheet.dart';
import 'sh_style.dart';
import 'zoom_controls.dart';

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

class _FamilyTreeViewState extends State<FamilyTreeView> with SingleTickerProviderStateMixin {
  // Big trees open compact; branches open and close with the toggle under a person.
  late Set<int> _collapsed = compactCollapse(widget.world, widget.root);
  late TreeLayout _layout = layoutTree(widget.world, widget.root, collapsed: _collapsed);
  final _transform = TransformationController();
  late final _ease = TransformAnimator(this, _transform);

  /// The first placement is immediate; later re-centring (a branch opened) eases.
  bool _placed = false;

  /// Bumped when branches open or close, so the drawing cross-fades.
  int _version = 0;
  Size? _centredFor;

  /// Whom to bring to the middle after the next layout: the tree's person, or a toggled branch.
  late int _centreOn = widget.root;

  @override
  void didUpdateWidget(FamilyTreeView old) {
    super.didUpdateWidget(old);
    if (old.root != widget.root || old.world != widget.world) {
      _collapsed = compactCollapse(widget.world, widget.root);
      _layout = layoutTree(widget.world, widget.root, collapsed: _collapsed);
      _centreOn = widget.root;
      _centredFor = null;
    }
  }

  @override
  void dispose() {
    _ease.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggle(int id) => setState(() {
    _collapsed = {..._collapsed};
    _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);
    _layout = layoutTree(widget.world, widget.root, collapsed: _collapsed);
    _centreOn = id;
    _centredFor = null;
    _version++;
  });

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
        final minScale = fitMinScale(viewport, size);
        if (_centredFor != viewport) {
          _centredFor = viewport;
          final scale = _transform.value.getMaxScaleOnAxis().clamp(minScale, 2.5);
          final spot = _centre(byId[_centreOn] ?? byId[widget.root] ?? _layout.nodes.first, rtl);
          final target = Matrix4.translationValues(
            viewport.width / 2 - spot.dx * scale,
            viewport.height / 3 - spot.dy * scale,
            0,
          )..multiply(Matrix4.diagonal3Values(scale, scale, scale));
          if (_placed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ease.to(target);
            });
          } else {
            _placed = true;
            _transform.value = target;
          }
        }
        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              boundaryMargin: EdgeInsets.all(math.max(viewport.width, viewport.height)),
              minScale: minScale,
              maxScale: 2.5,
              // Panning moves one picture instead of redrawing every box and line.
              // Opening or folding a branch cross-fades to the new drawing.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                layoutBuilder: (current, previous) =>
                    Stack(alignment: AlignmentDirectional.topStart, children: [...previous, ?current]),
                child: RepaintBoundary(
                  key: ValueKey(_version),
                  child: SizedBox.fromSize(
                    key: const ValueKey('tree-canvas'),
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
                              paper: c.page,
                              label: TextStyle(color: c.muted, fontSize: 11, fontFamily: kBodyFont),
                              gapText: (n) => l.shGenerations(localDigits(n)),
                              textDirection: Directionality.of(context),
                            ),
                          ),
                        ),
                        for (final n in _layout.nodes) ...[
                          Positioned(
                            left: _centre(n, rtl).dx - _boxW / 2,
                            top: _centre(n, rtl).dy - _boxH / 2,
                            width: _boxW,
                            height: _boxH,
                            child: PersonHover(
                              world: widget.world,
                              id: n.id,
                              child: _PersonBox(
                                key: ValueKey('tree-node-${n.id}'),
                                world: widget.world,
                                id: n.id,
                                root: n.id == widget.root,
                              ),
                            ),
                          ),
                          if (_layout.hasChildren(n.id))
                            Positioned(
                              left: _centre(n, rtl).dx - 22,
                              top: _centre(n, rtl).dy + _boxH / 2 - 2,
                              width: 44,
                              height: 22,
                              child: _BranchToggle(
                                key: ValueKey('tree-toggle-${n.id}'),
                                hidden: _layout.hiddenBelow[n.id],
                                onTap: () => _toggle(n.id),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const PositionedDirectional(top: 10, start: 10, child: LegendToggle(legend: TreeLegend())),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: ZoomControls(
                onZoomIn: () => _ease.to(zoomedBy(_transform.value, 1.4, viewport, min: minScale, max: 2.5)),
                onZoomOut: () => _ease.to(zoomedBy(_transform.value, 1 / 1.4, viewport, min: minScale, max: 2.5)),
                onShowAll: () => _ease.to(fitMatrix(viewport, size)),
                extra: IconButton(
                  tooltip: personName(context, widget.world, widget.root),
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () => setState(() {
                    _centreOn = widget.root;
                    _centredFor = null;
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Under a person with children: «−» to fold their branch away, «+n» to open it again.
class _BranchToggle extends StatelessWidget {
  const _BranchToggle({super.key, required this.hidden, required this.onTap});

  /// How many are folded away; null when the branch is open.
  final int? hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    final open = hidden == null;
    return Tooltip(
      message: open ? l.shCollapse : l.shExpand,
      child: Material(
        color: open ? c.paper : c.gold,
        shape: StadiumBorder(side: BorderSide(color: c.gold)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              open ? '−' : '+${localDigits(hidden!)}',
              style: TextStyle(color: open ? c.ink : c.paper, fontSize: 12, fontWeight: FontWeight.bold, height: 1),
            ),
          ),
        ),
      ),
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
    required this.paper,
    required this.label,
    required this.gapText,
    required this.textDirection,
  });

  final TreeLayout layout;
  final Offset Function(int id) centre;
  final Color ink, spouse, paper;
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
            // On a backing, so lines passing by don't run through the words.
            final at = Offset(from.dx + 4, (from.dy + bend) / 2 - tp.height / 2);
            canvas.drawRRect(
              RRect.fromRectAndRadius((at & tp.size).inflate(2), const Radius.circular(4)),
              Paint()..color = paper.withValues(alpha: 0.9),
            );
            tp.paint(canvas, at);
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
