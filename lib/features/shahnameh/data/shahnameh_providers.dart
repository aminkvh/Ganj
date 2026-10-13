import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/dto/people.dart';
import '../../../data/providers.dart';
import 'models.dart';
import 'world_loader.dart';

/// The whole bundled world; works offline from the first launch.
final shahnamehWorldProvider = FutureProvider<ShWorld>((ref) async {
  Future<String> load(String name) => rootBundle.loadString('assets/seed/shahnameh/$name');
  return loadWorld(
    generated: await load('generated.json'),
    ages: await load('ages.json'),
    places: await load('places.json'),
    namesEn: await load('names_en.json'),
  );
}, retry: noAutoRetry);

/// Kin and ties with evidence couplets (live, cached a month).
final personRelationsProvider = FutureProvider.autoDispose.family<PersonRelations, int>(
  (ref, id) => ref.watch(ganjoorApiProvider).personRelations(id),
  retry: noAutoRetry,
);

/// Couplets tagged with the person (live, cached a month).
final personPoemsProvider = FutureProvider.autoDispose.family<List<TaggedPoem>, int>(
  (ref, id) => ref.watch(ganjoorApiProvider).personPoems(id),
  retry: noAutoRetry,
);

/// What the hub is showing across its tabs: a story chosen on the timeline is drawn on the
/// map; a place chosen anywhere is opened on the map; a story chosen on the map is brought
/// into view on the timeline.
class ShSelection {
  const ShSelection({this.story, this.place, this.section, this.focus});

  final String? story, place;

  /// A person to focus the people network on.
  final int? focus;

  /// A story order for the timeline.
  final int? section;
}

class ShSelectionNotifier extends Notifier<ShSelection> {
  @override
  ShSelection build() => const ShSelection();

  void showStory(String? id) => state = ShSelection(story: id);
  void showPlace(String id) => state = ShSelection(place: id);
  void showSection(int order) => state = ShSelection(section: order);
  void showFocus(int person) => state = ShSelection(focus: person);

  int? takeFocus() {
    final f = state.focus;
    if (f != null) state = ShSelection(story: state.story);
    return f;
  }

  /// A place or section is acted on once (a sheet opened, a list scrolled), not on every
  /// later visit to the tab; the story stays until it is closed.
  String? takePlace() {
    final p = state.place;
    if (p != null) state = ShSelection(story: state.story);
    return p;
  }

  int? takeSection() {
    final s = state.section;
    if (s != null) state = ShSelection(story: state.story);
    return s;
  }
}

/// Ganjoor's place table (live, cached a month).
final ganjoorLocationsProvider = FutureProvider.autoDispose<List<GanjLocation>>(
  (ref) => ref.watch(ganjoorApiProvider).locations(),
  retry: noAutoRetry,
);

/// Ganjoor's current place tags in a story's sections — newer than the bundled snapshot.
final storyPlaceTagsProvider = FutureProvider.autoDispose.family<List<ShPlaceTag>, String>((ref, storyId) async {
  final w = await ref.watch(shahnamehWorldProvider.future);
  final story = w.storyById(storyId);
  if (story == null) return const [];
  final api = ref.watch(ganjoorApiProvider);
  final locations = {for (final l in await ref.watch(ganjoorLocationsProvider.future)) l.id: l};
  return [
    for (final o in story.sections)
      for (final t in await api.catPlaceTags(w.sections[o].catId))
        if (locations[t.locationId] case final l?)
          ShPlaceTag(locationId: l.id, name: l.name, lat: l.lat, lng: l.lng, poemId: t.poemId, couplet: t.coupletIndex),
  ];
}, retry: noAutoRetry);

/// Lives as long as the hub that listens to it: leaving the hub forgets the selection.
final shSelectionProvider = NotifierProvider.autoDispose<ShSelectionNotifier, ShSelection>(ShSelectionNotifier.new);
