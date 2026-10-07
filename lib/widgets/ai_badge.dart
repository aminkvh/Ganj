import 'package:flutter/material.dart';

import '../core/theme/ganj_colors.dart';
import '../l10n/l10n.dart';

/// Marks AI-generated text, as ganjoor.net does.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c.gold),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(context.l10n.aiBadge, style: TextStyle(fontSize: 11, color: c.gold)),
    );
  }
}
