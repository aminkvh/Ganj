import 'package:flutter/material.dart';

import '../core/theme/ganj_colors.dart';

/// Oval portrait with a double gold ring (76×96 by default).
class PoetPortrait extends StatelessWidget {
  const PoetPortrait({super.key, required this.url, this.width = 76, this.height = 96});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final placeholder = ColoredBox(
      color: c.inner,
      child: Icon(Icons.person, color: c.muted, size: width / 2),
    );
    return Container(
      width: width + 8,
      height: height + 8,
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(
        shape: OvalBorder(side: BorderSide(color: c.gold, width: 1.5)),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: ShapeDecoration(
          shape: OvalBorder(side: BorderSide(color: c.goldLight, width: 1.5)),
        ),
        child: ClipOval(
          child: url == null
              ? placeholder
              : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
        ),
      ),
    );
  }
}
