import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import '../../../core/net/api_client.dart';
import '../../../core/net/http_cache.dart';
import '../../../data/providers.dart';
import '../../podcasts/podcast_data.dart';

/// A podcast played from its public RSS feed (credited, with a link to its page).
abstract class PodcastShow {
  const PodcastShow({
    required this.id,
    required this.fa,
    required this.en,
    required this.authorFa,
    required this.authorEn,
    required this.feed,
    required this.link,
  });

  final String id, fa, en, authorFa, authorEn;

  /// The RSS feed, and the podcast's own page (for credit).
  final String feed, link;
}

/// A Shahnameh podcast with its episodes matched to the stories by hand
/// (assets/seed/shahnameh/podcasts.json).
class ShPodcast extends PodcastShow {
  const ShPodcast({
    required super.id,
    required super.fa,
    required super.en,
    required super.authorFa,
    required super.authorEn,
    required super.feed,
    required super.link,
    required this.stories,
  });

  factory ShPodcast.fromJson(Map<String, dynamic> j) => ShPodcast(
    id: j['id'] as String,
    fa: j['fa'] as String,
    en: j['en'] as String,
    authorFa: j['authorFa'] as String,
    authorEn: j['authorEn'] as String,
    feed: j['feed'] as String,
    link: j['link'] as String,
    stories: {
      for (final e in (j['stories'] as Map<String, dynamic>).entries)
        e.key: [for (final g in e.value as List) g as String],
    },
  );

  /// Story id → the feed's episode guids about it, in listening order.
  final Map<String, List<String>> stories;
}

/// Reads the bundled podcasts file; podcasts in a format this app doesn't know are left out.
List<ShPodcast> parsePodcasts(String text) => podcastsFromJson(jsonDecode(text) as Map<String, dynamic>);

List<ShPodcast> podcastsFromJson(Map<String, dynamic> j) {
  if (j['schema'] != 1) return const [];
  return [for (final p in j['podcasts'] as List) ShPodcast.fromJson(p as Map<String, dynamic>)];
}

/// One episode as the feed describes it now (titles and audio links can change; the guid stays).
class PodcastEpisode {
  const PodcastEpisode({required this.guid, required this.title, required this.audioUrl, this.duration});

  final String guid, title, audioUrl;
  final Duration? duration;
}

/// "1:05:10", "58:24" or "3910" → a duration; null for nothing usable (some feeds say "00:00").
Duration? parseItunesDuration(String? s) {
  if (s == null) return null;
  final parts = s.trim().split(':');
  if (parts.length > 3) return null;
  var secs = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null) return null;
    secs = secs * 60 + n;
  }
  return secs > 0 ? Duration(seconds: secs) : null;
}

/// The feed's playable episodes by guid.
Map<String, PodcastEpisode> parsePodcastFeed(String xml) {
  final doc = XmlDocument.parse(xml);
  final out = <String, PodcastEpisode>{};
  for (final item in doc.findAllElements('item')) {
    String? text(String name) => item.findElements(name).firstOrNull?.innerText.trim();
    final guid = text('guid');
    final url = item.findElements('enclosure').firstOrNull?.getAttribute('url')?.trim();
    if (guid == null || guid.isEmpty || url == null || url.isEmpty) continue;
    out[guid] = PodcastEpisode(
      guid: guid,
      title: text('title') ?? '',
      audioUrl: url,
      duration: parseItunesDuration(item.findElements('itunes:duration').firstOrNull?.innerText),
    );
  }
  return out;
}

/// The podcasts: the newest of the bundled list and the one published between releases.
final shPodcastsProvider = FutureProvider<List<ShPodcast>>(
  (ref) async => (await ref.watch(podcastCatalogsProvider.future)).shahnameh,
);

/// Fetches a feed's text; tests replace it.
final podcastFeedFetcherProvider = Provider<Future<String> Function(String url)>((ref) {
  final dio = createDio();
  final cache = HttpCache(ref.watch(appDbProvider));
  return (url) => cache.fetch('podcast-feed:$url', const Duration(days: 1), () async {
    final r = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/rss+xml, application/xml, */*'},
      ),
    );
    final body = r.data ?? '';
    parsePodcastFeed(body); // a broken page is not cached
    return body;
  });
});

/// A podcast's episodes, from its feed (fetched at most daily; the last copy when offline).
final podcastEpisodesProvider = FutureProvider.autoDispose.family<Map<String, PodcastEpisode>, String>(
  (ref, feed) async => parsePodcastFeed(await ref.watch(podcastFeedFetcherProvider)(feed)),
  retry: noAutoRetry,
);
