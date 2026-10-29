import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// On touch screens, a sideways drag that starts at either edge of a long, scrolling page goes
/// back. Android's own back gesture ignores a swipe that starts a little inside its edge or
/// drifts upward, and the page then takes it as a scroll or a tap; these strips take it instead.
class EdgeSwipeBack extends StatelessWidget {
  const EdgeSwipeBack({super.key, required this.child});

  final Widget child;

  static const _strip = 36.0;
  static const _distance = 64.0;

  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    if (!_touch) return child;
    // Both edges go back, in either text direction. Inward is the way: right from the left edge,
    // left from the right edge.
    Widget strip({required bool leftEdge}) {
      var travelled = 0.0;
      return Positioned(
        left: leftEdge ? 0 : null,
        right: leftEdge ? null : 0,
        top: 0,
        bottom: 0,
        width: _strip,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => travelled = 0,
          onHorizontalDragUpdate: (d) => travelled += leftEdge ? d.delta.dx : -d.delta.dx,
          onHorizontalDragEnd: (_) {
            if (travelled > _distance) GoRouter.maybeOf(context)?.pop();
          },
        ),
      );
    }

    return Stack(children: [child, strip(leftEdge: true), strip(leftEdge: false)]);
  }
}
