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
import '../shahnameh/ui/cluster_bubble.dart';
import '../shahnameh/ui/pin_clusters.dart';
import '../settings/settings_controller.dart';
import '../../core/text/content_en.dart';

/// OpenStreetMap tiles, as on ganjoor.net/map. The tile policy asks for an identifying
/// user agent and visible attribution (below). Tests swap this for an empty box.
final mapTileLayerProvider = Provider<Widget>(
  (ref) => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'io.github.aminkvh.ganj',
    // A tile that failed (rate limit, dropped connection) is asked for again instead of staying
    // blank, and a fast zoom doesn't fire a request per frame.
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    tileUpdateTransformer: TileUpdateTransformers.throttle(const Duration(milliseconds: 120)),
  ),
);

/// «نقشهٔ خاستگاه سخنوران»: poets of one era at their birthplaces, era by era on a slider.
class PoetsMapScreen extends ConsumerStatefulWidget {
  const PoetsMapScreen({super.key});

  @override
  ConsumerState<PoetsMapScreen> createState() => _PoetsMapScreenState();
}

class _PoetsMapScreenState extends ConsumerState<PoetsMapScreen> {
  /// 0 is every century; i is the i-th century that has located poets. Null: not chosen yet.
  int? _era;
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
          // Slider stops: all centuries first, then each century.
          final stops = eras.length + 1;
          final at = (_era ?? (ref.read(settingsProvider).mapStartsOnAll ? 0 : 1)).clamp(0, stops - 1);
          final poets = at == 0
              ? [
                  for (final e in eras)
                    for (final p in e.poets)
                      if (_located(p)) p,
                ]
              : eras[at - 1].poets.where(_located).toList();
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
                        _PoetMarkers(poets: poets, onSelect: (p) => setState(() => _selected = p)),
                        RichAttributionWidget(
                          showFlutterMapAttribution: false,
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
                eras: [context.l10n.allCenturies, for (final e in eras) localCentury(e.name)],
                index: at,
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

/// The poets as portrait markers. Portraits that would overlap on screen at the current zoom
/// are grouped: a few fan out in a ring so each stays tappable, more become one numbered
/// bubble (tap to zoom in). The layer rebuilds as the map zooms.
class _PoetMarkers extends StatelessWidget {
  const _PoetMarkers({required this.poets, required this.onSelect});

  final List<Poet> poets;
  final ValueChanged<Poet> onSelect;

  static const _w = 36.0, _h = 44.0;

  void _pickPoet(BuildContext context, List<Poet> group) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in group)
              ListTile(
                key: ValueKey('map-pick-${p.id}'),
                leading: PoetPortrait(url: p.imageAbsoluteUrl, width: 32, height: 40),
                title: Text(localPoetFull(p.id, p.name)),
                subtitle: Text(poetYears(ctx.l10n, p)),
                onTap: () {
                  Navigator.pop(ctx);
                  onSelect(p);
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final byId = {for (final p in poets) '${p.id}': p};
    LatLng at(Poet p) => LatLng(p.birthLatitude!, p.birthLongitude!);
    final groups = clusterPins({for (final p in poets) '${p.id}': camera.projectAtZoom(at(p))}, size: _w * 1.3);
    // Bubbles last, so they're drawn above the portraits around them.
    groups.sort((a, b) => (a.isBubble ? 1 : 0).compareTo(b.isBubble ? 1 : 0));
    return MarkerLayer(
      markers: [
        for (final g in groups)
          if (g.isBubble)
            Marker(
              point: camera.unprojectAtZoom(g.centre),
              width: 44,
              height: 44,
              child: ClusterBubble(
                key: ValueKey('map-cluster-${g.ids.first}'),
                count: g.ids.length,
                onTap: () {
                  // Poets born in one city share a point: no zoom pulls them apart, so list them.
                  final deepest = camera.maxZoom ?? 12;
                  final px = [for (final id in g.ids) camera.projectAtZoom(at(byId[id]!), deepest)];
                  final spread = px.map((p) => (p - px.first).distance).reduce(math.max);
                  if (spread < _w * 1.3) {
                    _pickPoet(context, [for (final id in g.ids) byId[id]!]);
                    return;
                  }
                  MapController.of(context).fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([for (final id in g.ids) at(byId[id]!)]),
                      padding: const EdgeInsets.all(64),
                      maxZoom: camera.zoom + 4,
                      minZoom: camera.zoom + 1,
                    ),
                  );
                },
              ),
            )
          else
            for (final (k, id) in g.ids.indexed)
              Marker(
                point: camera.unprojectAtZoom(camera.projectAtZoom(at(byId[id]!)) + g.offsets[k]),
                width: _w,
                height: _h,
                child: GestureDetector(
                  key: ValueKey('map-poet-$id'),
                  onTap: () => onSelect(byId[id]!),
                  child: Tooltip(
                    message: localPoet(byId[id]!.id, byId[id]!.nickname),
                    child: PoetPortrait(url: byId[id]!.imageAbsoluteUrl, width: 28, height: 36),
                  ),
                ),
              ),
      ],
    );
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
