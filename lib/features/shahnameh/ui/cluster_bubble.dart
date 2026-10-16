import 'package:flutter/material.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';

/// Pins too close to tell apart at this zoom: how many, and a tap to zoom in.
class ClusterBubble extends StatelessWidget {
  const ClusterBubble({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Semantics(
      button: true,
      label: localDigits(count),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.gold,
            shape: BoxShape.circle,
            border: Border.all(color: c.paper, width: 3),
            boxShadow: [BoxShadow(color: c.ink.withValues(alpha: 0.3), blurRadius: 4)],
          ),
          child: Text(
            localDigits(count),
            style: TextStyle(color: c.paper, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
