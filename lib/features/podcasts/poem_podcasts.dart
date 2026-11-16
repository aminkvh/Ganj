import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shahnameh/data/podcasts.dart';
import 'podcast_data.dart';

/// A podcast that reads or discusses poems (Hafez's ghazals, the Masnavi, Nezami…), with its episodes
/// matched by hand to the Ganjoor poems they are about (assets/seed/podcasts.json).
class PoemPodcast extends PodcastShow {
  const PoemPodcast({
    required super.id,
    required super.fa,
    required super.en,
    required super.authorFa,
    required super.authorEn,
    required super.feed,
    required super.link,
    required this.poems,
  });

  factory PoemPodcast.fromJson(Map<String, dynamic> j) => PoemPodcast(
    id: j['id'] as String,
    fa: j['fa'] as String,
    en: j['en'] as String,
    authorFa: j['authorFa'] as String,
    authorEn: j['authorEn'] as String,
    feed: j['feed'] as String,
    link: j['link'] as String,
    poems: {
      for (final e in (j['poems'] as Map<String, dynamic>).entries)
        e.key: [for (final g in e.value as List) g as String],
    },
  );

  /// A poem's Ganjoor path (`/hafez/ghazal/sh1`) → the feed's episode guids about it, in listening order.
  final Map<String, List<String>> poems;
}

/// Reads the bundled file; podcasts in a format this app doesn't know are left out.
List<PoemPodcast> parsePoemPodcasts(String text) => poemPodcastsFromJson(jsonDecode(text) as Map<String, dynamic>);

List<PoemPodcast> poemPodcastsFromJson(Map<String, dynamic> j) {
  if (j['schema'] != 1) return const [];
  return [for (final p in j['podcasts'] as List) PoemPodcast.fromJson(p as Map<String, dynamic>)];
}

/// The podcasts with episodes on the poem at [fullUrl], each with those episodes' guids.
List<(PoemPodcast, List<String>)> podcastsForPoem(List<PoemPodcast> all, String fullUrl) => [
  for (final p in all)
    if (p.poems[fullUrl] case final gs? when gs.isNotEmpty) (p, gs),
];

/// The poem podcasts: the newest of the bundled list and the one published between releases.
final poemPodcastsProvider = FutureProvider<List<PoemPodcast>>(
  (ref) async => (await ref.watch(podcastCatalogsProvider.future)).poems,
);
