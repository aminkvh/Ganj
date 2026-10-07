import 'package:flutter/material.dart';

import '../core/theme/ganj_colors.dart';

/// Red ✤ between beyts (wide layout).
class OrnamentSeparator extends StatelessWidget {
  const OrnamentSeparator({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Text('✤', style: TextStyle(color: context.ganj.brandRed.withValues(alpha: 0.8), fontSize: 11, height: 1)),
  );
}

/// Dashed separator between beyts (narrow layout).
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 12,
    child: CustomPaint(painter: _DashPainter(context.ganj.borderGold), size: Size.infinite),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    final start = size.width * 0.2, end = size.width * 0.8;
    for (var x = start; x < end; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
