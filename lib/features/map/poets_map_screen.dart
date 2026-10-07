import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/poet.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/external_link.dart';
import '../../widgets/poet_portrait.dart';
import '../home/poet_tile.dart';
import '../../core/text/content_en.dart';

/// OpenStreetMap tiles, as on ganjoor.net/map. The tile policy asks for an identifying
/// user agent and visible attribution (below). Tests swap this for an empty box.
final mapTileLayerProvider = Provider<Widget>(
  (ref) => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'io.github.aminkvh.ganj',
  ),
);

/// «نقشهٔ خاستگاه سخنوران»: poets of one era at their birthplaces, era by era on a slider.
class PoetsMapScreen extends ConsumerStatefulWidget {
  const PoetsMapScreen({super.key});

  @override
  ConsumerState<PoetsMapScreen> createState() => _PoetsMapScreenState();
}

class _PoetsMapScreenState extends ConsumerState<PoetsMapScreen> {
  int _era = 0;
  Poet? _selected;

  @override
  Widget build(BuildContext context) {
    final centuries = ref.watch(centuriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.birthplaceMap)),
      body: centuries.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(centuriesProvider)),
        data: (cs) {
          final eras = [
            for (final c in cs)
              if (c.id != 0 && c.poets.any(_located)) c,
          ];
          if (eras.isEmpty) return Center(child: Text(context.l10n.nothingHere));
          final era = eras[_era.clamp(0, eras.length - 1)];
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: const LatLng(33, 58),
                        initialZoom: 4,
                        minZoom: 2,
                        maxZoom: 12,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                        onTap: (_, _) => setState(() => _selected = null),
                      ),
                      children: [
                        ref.watch(mapTileLayerProvider),
                        _PoetMarkers(
                          poets: era.poets.where(_located).toList(),
                          onSelect: (p) => setState(() => _selected = p),
                        ),
                        RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution(
                              'OpenStreetMap contributors',
                              onTap: () => openExternal(
                                context,
                                'https://www.openstreetmap.org/copyright',
                                launcher: ref.read(urlLauncherProvider),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_selected case final p?)
                      PositionedDirectional(start: 12, end: 12, bottom: 12, child: _PoetCard(poet: p)),
                  ],
                ),
              ),
              _EraSlider(
                eras: [for (final e in eras) localCentury(e.name)],
                index: _era.clamp(0, eras.length - 1),
                onChanged: (i) => setState(() {
                  _era = i;
                  _selected = null;
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _located(Poet p) => p.birthLatitude != null && p.birthLongitude != null;
}

/// The era's poets as portrait markers. Portraits that would overlap on screen at the
/// current zoom are fanned out in a ring around the first, so every one stays tappable;
/// the layer rebuilds as the map zooms, so the ring keeps its size in pixels.
class _PoetMarkers extends StatelessWidget {
  const _PoetMarkers({required this.poets, required this.onSelect});

  final List<Poet> poets;
  final ValueChanged<Poet> onSelect;

  static const _w = 36.0, _h = 44.0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final groups = <(Offset, List<Poet>)>[];
    for (final p in poets) {
      final px = camera.projectAtZoom(LatLng(p.birthLatitude!, p.birthLongitude!));
      final i = groups.indexWhere((g) => (g.$1 - px).distance < _w * 1.6);
      i < 0 ? groups.add((px, [p])) : groups[i].$2.add(p);
    }
    return MarkerLayer(
      markers: [
        for (final (anchor, group) in groups)
          for (var k = 0; k < group.length; k++)
            Marker(
              point: camera.unprojectAtZoom(anchor + _ring(k, group.length)),
              width: _w,
              height: _h,
              child: GestureDetector(
                key: ValueKey('map-poet-${group[k].id}'),
                onTap: () => onSelect(group[k]),
                child: Tooltip(
                  message: localPoet(group[k].id, group[k].nickname),
                  child: PoetPortrait(url: group[k].imageAbsoluteUrl, width: 28, height: 36),
                ),
              ),
            ),
      ],
    );
  }

  static Offset _ring(int k, int n) {
    if (n == 1) return Offset.zero;
    final r = math.max(_w * 0.8, n * _w / (2 * math.pi) * 1.15);
    final a = 2 * math.pi * k / n - math.pi / 2;
    return Offset(r * math.cos(a), r * math.sin(a));
  }
}

class _EraSlider extends StatelessWidget {
  const _EraSlider({required this.eras, required this.index, required this.onChanged});

  final List<String> eras;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              eras[index],
              style: TextStyle(color: c.lapis, fontWeight: FontWeight.w600),
            ),
            Slider(
              value: index.toDouble(),
              max: (eras.length - 1).toDouble(),
              divisions: eras.length > 1 ? eras.length - 1 : null,
              label: eras[index],
              onChanged: eras.length > 1 ? (v) => onChanged(v.round()) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PoetCard extends StatelessWidget {
  const _PoetCard({required this.poet});

  final Poet poet;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            PoetPortrait(url: poet.imageAbsoluteUrl, width: 44, height: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localPoetFull(poet.id, poet.name),
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                  ),
                  Text(
                    [?poet.birthPlace, poetYears(context.l10n, poet)].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            FilledButton(
              key: const ValueKey('map-open-poet'),
              onPressed: () => context.push('/poet/${poet.id}'),
              child: Text(context.l10n.openPoet),
            ),
          ],
        ),
      ),
    );
  }
}
