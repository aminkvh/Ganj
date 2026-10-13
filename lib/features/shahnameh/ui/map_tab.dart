import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/external_link.dart';
import '../../map/poets_map_screen.dart' show mapTileLayerProvider;
import '../data/models.dart';
import '../data/place_merge.dart';
import '../data/shahnameh_providers.dart';
import 'person_sheet.dart';
import 'pin_clusters.dart';
import 'sh_style.dart';

/// «نقشه»: the places of the Shahnameh — Ganj's curated places with Ganjoor's tags merged in.
/// Pins are tinted by the age a place first appears in; legendary places are soft circles.
/// A story chosen here or on the timeline shows only its places, its route numbered.
class ShahnamehMapTab extends ConsumerStatefulWidget {
  const ShahnamehMapTab({super.key, required this.world, this.place, this.story});

  final ShWorld world;

  /// Opened on this place / with this story shown (deep links).
  final String? place, story;

  @override
  ConsumerState<ShahnamehMapTab> createState() => _ShahnamehMapTabState();
}

class _ShahnamehMapTabState extends ConsumerState<ShahnamehMapTab> {
  final _map = MapController();
  late String? _story = widget.story;
  int? _age;
  bool _ganjoorOnly = false;

  ShWorld get w => widget.world;

  @override
  void initState() {
    super.initState();
    // The timeline may have chosen a story or a place before this tab was first built.
    final sel = ref.read(shSelectionProvider);
    _story ??= sel.story;
    if (widget.place ?? sel.place case final id?) {
      // Consumed once, after the build (providers can't change while the tree builds).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.place == null) ref.read(shSelectionProvider.notifier).takePlace();
        _openPlace(id);
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  List<ShPlace> _places() {
    final live = _story == null ? const <ShPlaceTag>[] : (ref.watch(storyPlaceTagsProvider(_story!)).value ?? const []);
    return mergePlaces(
      w.places,
      [...w.ganjoorTags, ...live],
      storiesOfPoem: (poemId) {
        final o = w.sectionOfPoem(poemId)?.order;
        return [
          for (final s in w.stories)
            if (o != null && s.sections.contains(o)) s.id,
        ];
      },
    );
  }

  /// The age a place first appears in (its earliest story); null when no story is set there.
  int? _ageOf(ShPlace p) {
    int? best;
    for (final id in p.stories) {
      final s = w.storyById(id);
      if (s != null && (best == null || s.age < best)) best = s.age;
    }
    return best;
  }

  List<ShPlace> _visible(List<ShPlace> all) {
    final story = _story == null ? null : w.storyById(_story!);
    return [
      for (final p in all)
        if ((story == null || story.places.contains(p.id) || p.stories.contains(story.id)) &&
            (_age == null || _ageOf(p) == _age) &&
            (!_ganjoorOnly || p.tags.isNotEmpty))
          p,
    ];
  }

  /// Story order of the selected story's places: its route if it has one.
  List<String> _stops(ShStory s) => w.routes.where((r) => r.story == s.id).firstOrNull?.places ?? s.places;

  void _fit(List<ShPlace> places) {
    if (places.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([for (final p in places) LatLng(p.lat, p.lng)]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48), maxZoom: 7));
      } catch (_) {
        // The map isn't laid out yet; its initial fit covers it.
      }
    });
  }

  void _setStory(String? id) {
    setState(() => _story = id);
    _fit(_visible(_places()));
  }

  void _openPlace(String id) {
    if (!mounted) return;
    final p = _places().where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    try {
      _map.move(LatLng(p.lat, p.lng), 6);
    } catch (_) {}
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.ganj.page,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (_, scroll) => _PlaceSheet(
          world: w,
          place: p,
          ageIndex: _ageOf(p),
          scroll: scroll,
          onStory: (s) {
            Navigator.of(sheet).pop();
            ref.read(shSelectionProvider.notifier).showSection(s.from);
            DefaultTabController.maybeOf(context)?.animateTo(0);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    ref.listen(shSelectionProvider, (_, sel) {
      if (sel.story != null) _setStory(sel.story);
      if (sel.place != null) {
        final id = ref.read(shSelectionProvider.notifier).takePlace()!;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openPlace(id));
      }
    });
    final offline = ref.watch(ganjoorLocationsProvider).hasError;
    final all = _places();
    final shown = _visible(all);
    final story = _story == null ? null : w.storyById(_story!);
    final stops = story == null ? const <String>[] : _stops(story);
    final hasRoute = story != null && w.routes.any((r) => r.story == story.id);
    final byId = {for (final p in all) p.id: p};
    final tintOf = {for (final p in shown) p.id: _ageOf(p)};
    final route = [
      for (final id in stops)
        if (byId[id] case final p?) LatLng(p.lat, p.lng),
    ];
    // Unfiltered, open on the epic's heartland rather than fit Andalus and the Land of Darkness.
    const heartland = {'iran', 'turan', 'sistan', 'kabul', 'mazandaran'};
    final unfiltered = story == null && _age == null && !_ganjoorOnly;
    final fitTo = unfiltered
        ? [
            for (final p in shown)
              if (heartland.contains(p.region)) p,
          ]
        : shown;
    final bounds = LatLngBounds.fromPoints([for (final p in fitTo.isEmpty ? all : fitTo) LatLng(p.lat, p.lng)]);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<int?>(
                key: const ValueKey('age-filter'),
                tooltip: l.shAllAges,
                onSelected: (a) {
                  setState(() => _age = a == -1 ? null : a);
                  _fit(_visible(_places()));
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: -1, child: Text(l.shAllAges)),
                  for (final a in w.ages)
                    PopupMenuItem(
                      value: a.index,
                      child: Row(
                        children: [
                          CircleAvatar(radius: 6, backgroundColor: ageTint(context, a.index)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(ageName(context, a), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                child: Chip(
                  avatar: _age == null
                      ? const Icon(Icons.layers_outlined, size: 18)
                      : CircleAvatar(radius: 8, backgroundColor: ageTint(context, _age!)),
                  label: Text(_age == null ? l.shAllAges : ageName(context, w.ages[_age!])),
                ),
              ),
              PopupMenuButton<String?>(
                key: const ValueKey('story-filter'),
                tooltip: l.shAllStories,
                onSelected: (s) => _setStory(s == '' ? null : s),
                itemBuilder: (_) => [
                  PopupMenuItem(value: '', child: Text(l.shAllStories)),
                  for (final s in w.stories)
                    if (s.places.isNotEmpty) PopupMenuItem(value: s.id, child: Text(storyName(context, s))),
                ],
                child: Chip(
                  avatar: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      story == null ? l.shAllStories : storyName(context, story),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              FilterChip(
                label: Text(l.shGanjoorOnly),
                selected: _ganjoorOnly,
                onSelected: (v) {
                  setState(() => _ganjoorOnly = v);
                  _fit(_visible(_places()));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48), maxZoom: 7),
                  minZoom: 2,
                  maxZoom: 11,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  ref.watch(mapTileLayerProvider),
                  CircleLayer(
                    circles: [
                      for (final p in shown)
                        if (p.precision == PlacePrecision.mythic)
                          CircleMarker(
                            point: LatLng(p.lat, p.lng),
                            radius: 90000,
                            useRadiusInMeter: true,
                            color: _tint(context, tintOf[p.id]).withValues(alpha: 0.18),
                            borderColor: _tint(context, tintOf[p.id]).withValues(alpha: 0.6),
                            borderStrokeWidth: 1.5,
                          ),
                    ],
                  ),
                  if (route.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          strokeWidth: 3.5,
                          color: _tint(context, story!.age),
                          pattern: const StrokePattern.dotted(spacingFactor: 2),
                        ),
                      ],
                    ),
                  _PlaceMarkers(
                    places: shown,
                    tintOf: (p) => _tint(context, tintOf[p.id]),
                    numberOf: (p) => hasRoute && stops.contains(p.id) ? stops.indexOf(p.id) + 1 : null,
                    onTap: (p) => _openPlace(p.id),
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
              if (offline)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: Chip(
                    avatar: Icon(Icons.cloud_off, size: 16, color: c.muted),
                    label: Text(l.shTilesNeedInternet, style: TextStyle(fontSize: 12, color: c.muted)),
                    backgroundColor: c.paper.withValues(alpha: 0.9),
                  ),
                ),
              PositionedDirectional(bottom: 30, start: 8, child: _Legend(world: w)),
            ],
          ),
        ),
        if (story != null)
          _StoryStops(
            key: const ValueKey('story-stops'),
            world: w,
            story: story,
            stops: [for (final id in stops) ?byId[id]],
            numbered: hasRoute,
            onPlace: _openPlace,
            onClose: () {
              ref.read(shSelectionProvider.notifier).showStory(null);
              _setStory(null);
            },
          ),
      ],
    );
  }

  Color _tint(BuildContext context, int? age) => age == null ? context.ganj.muted : ageTint(context, age);
}

/// Pins, fanned out in a ring where they would overlap at the current zoom so each stays
/// tappable (Damavand, Amol, Rey and the Alborz sit close together); rebuilt as the map zooms.
class _PlaceMarkers extends StatelessWidget {
  const _PlaceMarkers({required this.places, required this.tintOf, required this.numberOf, required this.onTap});

  final List<ShPlace> places;
  final Color Function(ShPlace) tintOf;
  final int? Function(ShPlace) numberOf;
  final ValueChanged<ShPlace> onTap;

  static const _size = 34.0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final byId = {for (final p in places) p.id: p};
    final groups = clusterPins({for (final p in places) p.id: camera.projectAtZoom(LatLng(p.lat, p.lng))}, size: _size);
    // Bubbles last, so they're drawn above the pins around them.
    groups.sort((a, b) => (a.isBubble ? 1 : 0).compareTo(b.isBubble ? 1 : 0));
    return MarkerLayer(
      markers: [
        for (final g in groups)
          if (g.isBubble)
            Marker(
              point: camera.unprojectAtZoom(g.centre),
              width: 44,
              height: 44,
              child: _Bubble(
                key: ValueKey('cluster-${g.ids.first}'),
                count: g.ids.length,
                onTap: () => MapController.of(context).fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([for (final id in g.ids) LatLng(byId[id]!.lat, byId[id]!.lng)]),
                    padding: const EdgeInsets.all(64),
                    maxZoom: camera.zoom + 4,
                    minZoom: camera.zoom + 1,
                  ),
                ),
              ),
            )
          else
            for (final (k, id) in g.ids.indexed)
              Marker(
                point: camera.unprojectAtZoom(
                  camera.projectAtZoom(LatLng(byId[id]!.lat, byId[id]!.lng)) + g.offsets[k],
                ),
                width: _size,
                height: _size + 6,
                alignment: g.ids.length > 1 || byId[id]!.precision == PlacePrecision.mythic
                    ? Alignment.center
                    : Alignment.topCenter,
                child: _Pin(
                  key: ValueKey('pin-$id'),
                  place: byId[id]!,
                  tint: tintOf(byId[id]!),
                  number: numberOf(byId[id]!),
                  onTap: () => onTap(byId[id]!),
                ),
              ),
      ],
    );
  }
}

/// Places too close to tell apart at this zoom: how many, and a tap to zoom in.
class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.count, required this.onTap});

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

class _Pin extends StatelessWidget {
  const _Pin({super.key, required this.place, required this.tint, required this.onTap, this.number});

  final ShPlace place;
  final Color tint;
  final VoidCallback onTap;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final name = placeName(context, place);
    final Widget icon;
    if (place.precision == PlacePrecision.mythic) {
      icon = Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: c.paper,
          shape: BoxShape.circle,
          border: Border.all(color: tint, width: 2),
        ),
        child: Icon(Icons.auto_awesome, size: 13, color: tint),
      );
    } else if (number != null) {
      icon = Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint,
          shape: BoxShape.circle,
          border: Border.all(color: c.paper, width: 2),
        ),
        child: Text(
          localDigits(number!),
          style: TextStyle(color: c.paper, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    } else {
      icon = Icon(
        place.fromGanjoor ? Icons.location_on_outlined : Icons.location_on,
        size: 34,
        color: tint,
        shadows: [Shadow(color: c.ink.withValues(alpha: 0.3), blurRadius: 3)],
      );
    }
    return Semantics(
      button: true,
      label: name,
      child: Tooltip(
        message: name,
        child: GestureDetector(
          onTap: onTap,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.world});

  final ShWorld world;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: c.paper.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in world.ages)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 4, backgroundColor: ageTint(context, a.index)),
                const SizedBox(width: 6),
                Text(ageName(context, a), style: TextStyle(fontSize: 10.5, color: c.ink)),
              ],
            ),
        ],
      ),
    );
  }
}

class _StoryStops extends StatelessWidget {
  const _StoryStops({
    super.key,
    required this.world,
    required this.story,
    required this.stops,
    required this.numbered,
    required this.onPlace,
    required this.onClose,
  });

  final ShWorld world;
  final ShStory story;
  final List<ShPlace> stops;
  final bool numbered;
  final ValueChanged<String> onPlace;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final tint = ageTint(context, story.age);
    return Material(
      color: c.paper,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      storyName(context, story),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tint, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, p) in stops.indexed) ...[
                      if (i > 0 && numbered) Icon(Icons.more_horiz, size: 16, color: c.muted),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: numbered
                            ? CircleAvatar(
                                backgroundColor: tint,
                                child: Text(localDigits(i + 1), style: TextStyle(color: c.paper, fontSize: 11)),
                              )
                            : Icon(Icons.place_outlined, size: 16, color: tint),
                        label: Text(placeName(context, p)),
                        onPressed: () => onPlace(p.id),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceSheet extends ConsumerWidget {
  const _PlaceSheet({
    required this.world,
    required this.place,
    required this.ageIndex,
    required this.scroll,
    required this.onStory,
  });

  final ShWorld world;
  final ShPlace place;
  final int? ageIndex;
  final ScrollController scroll;
  final ValueChanged<ShStory> onStory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.ganj;
    final en = isEn(context);
    final tint = ageIndex == null ? c.muted : ageTint(context, ageIndex!);
    final stories = [for (final id in place.stories) ?world.storyById(id)];
    final people = <int>{for (final s in stories) ...s.people};
    final note = en ? (place.noteEn ?? place.noteFa) : (place.noteFa ?? place.noteEn);
    final precision = switch (place.precision) {
      PlacePrecision.mythic => l.shMythic,
      PlacePrecision.approx => l.shApprox,
      PlacePrecision.exact => null,
    };
    return ListView(
      key: const ValueKey('place-sheet'),
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              en ? place.en : place.fa,
              style: en
                  ? TextStyle(fontSize: 24, color: tint, fontWeight: FontWeight.bold)
                  : nastaliqOf(context, 28).copyWith(color: tint),
            ),
            if (!place.fromGanjoor) const GanjAiBadge(),
          ],
        ),
        if (en && place.fa != place.en) Text(place.fa, style: TextStyle(color: c.muted)),
        if (!en && place.en != place.fa) Text(place.en, style: TextStyle(color: c.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Chip(visualDensity: VisualDensity.compact, label: Text(regionName(context, place.region))),
            if (precision != null)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  place.precision == PlacePrecision.mythic ? Icons.auto_awesome : Icons.near_me_outlined,
                  size: 16,
                ),
                label: Text(precision),
              ),
            if (place.fromGanjoor) Chip(visualDensity: VisualDensity.compact, label: Text(l.shFromGanjoor)),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note, style: TextStyle(color: c.ink, height: 1.7)),
          ),
        if (stories.isNotEmpty) ...[
          _Heading(l.shStoriesHere),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final s in stories)
                ActionChip(
                  avatar: const Icon(Icons.timeline, size: 16),
                  label: Text(storyName(context, s)),
                  side: BorderSide(color: ageTint(context, s.age)),
                  onPressed: () => onStory(s),
                ),
            ],
          ),
        ],
        if (people.isNotEmpty) ...[
          _Heading(l.shPeople),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final id in people)
                if (world.people.containsKey(id))
                  ActionChip(label: Text(personName(context, world, id)), onPressed: () => openPerson(context, id)),
            ],
          ),
        ],
        if (place.tags.isNotEmpty) ...[
          _Heading(l.shTaggedPoems),
          for (final t in place.tags)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.format_quote, color: c.gold),
              title: Text(
                world.sections.expand((s) => s.poems).where((p) => p.id == t.poemId).firstOrNull?.title ??
                    '${t.poemId}',
              ),
              subtitle: Text(world.sectionOfPoem(t.poemId)?.title ?? ''),
              onTap: () => context.push('/poem/${t.poemId}?c=${t.couplet}'),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.flag_outlined),
              label: Text(l.shReport),
              onPressed: () => reportProblem(
                context,
                ref,
                what: '${place.fa} (${place.en}) — ${place.id}',
                path: '/shahnameh?tab=map&place=${place.id}',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: nastaliqOf(context, 20).copyWith(color: context.ganj.lapis)),
  );
}
