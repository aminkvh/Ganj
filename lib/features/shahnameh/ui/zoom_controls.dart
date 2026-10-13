import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';

/// The transform that fits [content] inside [viewport], centred, never enlarging past [maxScale].
Matrix4 fitMatrix(Size viewport, Size content, {double margin = 0.95, double maxScale = 1}) {
  final s = math.min(maxScale, math.min(viewport.width / content.width, viewport.height / content.height) * margin);
  return Matrix4.translationValues(
    (viewport.width - content.width * s) / 2,
    (viewport.height - content.height * s) / 2,
    0,
  )..multiply(Matrix4.diagonal3Values(s, s, s));
}

/// The smallest zoom worth allowing: a bit below "everything fits".
double fitMinScale(Size viewport, Size content) =>
    math.min(0.5, math.min(viewport.width / content.width, viewport.height / content.height) * 0.8);

/// The view zoomed by [factor] around the middle of [viewport], within [min]..[max].
Matrix4 zoomedBy(Matrix4 now, double factor, Size viewport, {required double min, required double max}) {
  final scale = now.getMaxScaleOnAxis();
  final f = (scale * factor).clamp(min, max) / scale;
  final mid = Offset(viewport.width / 2, viewport.height / 2);
  return Matrix4.translationValues(mid.dx, mid.dy, 0)
    ..multiply(Matrix4.diagonal3Values(f, f, f))
    ..multiply(Matrix4.translationValues(-mid.dx, -mid.dy, 0))
    ..multiply(now);
}

/// Zooms the view by [factor] around the middle of [viewport], at once.
void zoomBy(TransformationController c, double factor, Size viewport, {required double min, required double max}) =>
    c.value = zoomedBy(c.value, factor, viewport, min: min, max: max);

/// Eases a view to a new zoom and position instead of jumping there.
class TransformAnimator {
  TransformAnimator(TickerProvider vsync, this._c)
    : _a = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 280));

  final TransformationController _c;
  final AnimationController _a;
  Animation<Matrix4>? _move;

  void to(Matrix4 target) {
    _move?.removeListener(_apply);
    _move = Matrix4Tween(
      begin: _c.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: _a, curve: Curves.easeOutCubic))..addListener(_apply);
    _a.forward(from: 0);
  }

  void _apply() => _c.value = _move!.value;

  void dispose() => _a.dispose();
}

/// Zoom in, zoom out, show everything — for views that pan and zoom.
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.onZoomIn, required this.onZoomOut, required this.onShowAll, this.extra});

  final VoidCallback onZoomIn, onZoomOut, onShowAll;

  /// Another button at the end (e.g. "centre on the person").
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    Widget button(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon), color: c.ink, onPressed: onTap);
    return Material(
      color: c.paper.withValues(alpha: 0.92),
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.add, l.shZoomIn, onZoomIn),
          button(Icons.remove, l.shZoomOut, onZoomOut),
          button(Icons.fit_screen_outlined, l.shShowAll, onShowAll),
          ?extra,
        ],
      ),
    );
  }
}
