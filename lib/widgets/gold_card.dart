import 'package:flutter/material.dart';

import '../core/theme/ganj_colors.dart';

/// ganjoor.net card: max 752 wide, 2px gold border, 18px radius, soft shadow.
class GoldCard extends StatelessWidget {
  const GoldCard({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 752),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? c.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.gold, width: 2),
            boxShadow: [BoxShadow(color: c.ink.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: child,
        ),
      ),
    );
  }
}
