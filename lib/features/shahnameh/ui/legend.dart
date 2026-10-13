import 'package:flutter/material.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../data/relation_kinds.dart';
import 'sh_style.dart';

/// «راهنما»: a button that opens (and closes) a small key to what is drawn.
class LegendToggle extends StatefulWidget {
  const LegendToggle({super.key, required this.legend});

  final Widget legend;

  @override
  State<LegendToggle> createState() => _LegendToggleState();
}

class _LegendToggleState extends State<LegendToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: c.paper.withValues(alpha: 0.92),
          elevation: 3,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: context.l10n.shLegend,
            isSelected: _open,
            icon: const Icon(Icons.help_outline),
            selectedIcon: const Icon(Icons.close),
            onPressed: () => setState(() => _open = !_open),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: _open
              ? Padding(padding: const EdgeInsets.only(top: 6), child: widget.legend)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.rows});

  final List<(Widget, String)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Material(
      color: c.paper,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (sample, text) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(width: 44, height: 20, child: Center(child: sample)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(text, style: TextStyle(color: c.ink, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short line drawn the way the views draw ties.
class _Line extends StatelessWidget {
  const _Line({required this.color, this.dash, this.twin = false, this.width = 1.6});

  final Color color;
  final List<double>? dash;
  final bool twin;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(40, 12),
    painter: _LinePainter(color: color, dash: dash, twin: twin, width: width),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.color, required this.dash, required this.twin, required this.width});

  final Color color;
  final List<double>? dash;
  final bool twin;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width;
    for (final dy in twin ? [-2.0, 2.0] : [0.0]) {
      final y = size.height / 2 + dy;
      if (dash == null) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      } else {
        var x = 0.0, on = true, i = 0;
        while (x < size.width) {
          final step = dash![i % dash!.length];
          if (on) canvas.drawLine(Offset(x, y), Offset((x + step).clamp(0, size.width), y), p);
          x += step;
          on = !on;
          i++;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

Widget _box(Color border, Color fill) => Container(
  width: 34,
  height: 16,
  decoration: BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(5),
    border: Border.all(color: border, width: 1.5),
  ),
);

/// What a family tree draws.
class TreeLegend extends StatelessWidget {
  const TreeLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    return _Card(
      rows: [
        (_Line(color: c.borderGold), l.shLegendParent),
        (_Line(color: c.borderGold, dash: const [6, 4]), l.shLegendAncestor),
        (_Line(color: c.brandRed.withValues(alpha: 0.7), twin: true, width: 1.4), l.shLegendSpouse),
        (_Line(color: c.borderGold, dash: const [2, 3]), l.shLegendSibling),
        (_box(c.gold, c.goldLight), l.shLegendRoot),
        (
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var a = 0; a < 4; a++)
                Container(width: 9, height: 14, margin: const EdgeInsets.all(0.5), color: ageTint(context, a)),
            ],
          ),
          l.shLegendAges,
        ),
        (
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: ShapeDecoration(color: c.gold, shape: const StadiumBorder()),
            child: Text(
              '+ / −',
              style: TextStyle(color: c.paper, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          l.shLegendBranch,
        ),
      ],
    );
  }
}

/// What the people network draws.
class NetworkLegend extends StatelessWidget {
  const NetworkLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    Widget dot(double r, Color fill) => Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: c.gold, width: 1.4),
      ),
    );
    return _Card(
      rows: [
        (dot(8, c.brandRed), l.shLegendFocus),
        (
          Row(mainAxisSize: MainAxisSize.min, children: [dot(4, c.paper), const SizedBox(width: 4), dot(8, c.paper)]),
          l.shLegendSize,
        ),
        for (final f in RelationFamily.values)
          (_Line(color: familyColor(context, f), dash: familyDash(f)), familyLabel(l, f)),
        (const SizedBox.shrink(), l.shLegendLines),
      ],
    );
  }
}
