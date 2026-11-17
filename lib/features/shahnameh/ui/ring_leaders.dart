import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/ganj_colors.dart';
import 'pin_clusters.dart';

/// For pins fanned out in a ring: a small dot on each one's true place and a thin line to
/// where its pin is drawn, so a moved pin never reads as being somewhere it isn't.
/// Put it under the marker layer; it groups [points] exactly as the markers do.
class RingLeaderLayer extends StatelessWidget {
  const RingLeaderLayer({super.key, required this.points, required this.size, this.pinTip = Offset.zero});

  final Map<String, LatLng> points;

  /// The `size` the marker layer passes to [clusterPins].
  final double size;

  /// Where a ring pin's line should end, relative to its marker's point (pixels).
  final Offset pinTip;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final c = context.ganj;
    final groups = clusterPins(
      {for (final e in points.entries) e.key: camera.projectAtZoom(e.value)},
      size: size,
      fanOut: camera.zoom >= ringMinZoom,
    );
    final lines = <Polyline>[];
    final dots = <CircleMarker>[];
    for (final g in groups) {
      if (g.isBubble || g.ids.length < 2) continue;
      for (final (k, id) in g.ids.indexed) {
        final at = points[id]!;
        final drawn = camera.unprojectAtZoom(camera.projectAtZoom(at) + g.offsets[k] + pinTip);
        lines.add(Polyline(points: [at, drawn], strokeWidth: 1.2, color: c.ink.withValues(alpha: 0.45)));
        dots.add(
          CircleMarker(
            point: at,
            radius: 3,
            color: c.ink.withValues(alpha: 0.7),
            borderColor: c.paper,
            borderStrokeWidth: 1,
          ),
        );
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        PolylineLayer(polylines: lines),
        CircleLayer(circles: dots),
      ],
    );
  }
}
