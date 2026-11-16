import 'dart:convert';
import 'dart:io' show gzip;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/http_cache.dart';
import '../../data/providers.dart';
import '../shahnameh/data/podcasts.dart';
import 'poem_podcasts.dart';

/// Where the podcast lists are published between app releases (by the repository's "podcasts-data"
/// workflow, tool/podcast_update.dart), so new episodes and podcasts reach readers without an update.
const kPodcastDataUrl = 'https://github.com/aminkvh/Ganj/releases/download/podcasts-data/podcasts.json.gz';

/// The published file is checked at most this often.
const kPodcastDataCheck = Duration(days: 2);

/// Both podcast lists, and when they were built (ISO date or date-time; later sorts after earlier).
class PodcastCatalogs {
  const PodcastCatalogs({required this.builtAt, required this.shahnameh, required this.poems});

  final String builtAt;
  final List<ShPodcast> shahnameh;
  final List<PoemPodcast> poems;
}

/// The published file, if this app can use it: schema 1 with both lists, each in a format it knows.
PodcastCatalogs? parsePublishedPodcasts(String text) {
  try {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['schema'] != 1 || j['builtAt'] is! String) return null;
    final sh = podcastsFromJson(j['shahnameh'] as Map<String, dynamic>);
    final poems = poemPodcastsFromJson(j['poems'] as Map<String, dynamic>);
    if (sh.isEmpty || poems.isEmpty) return null;
    return PodcastCatalogs(builtAt: j['builtAt'] as String, shahnameh: sh, poems: poems);
  } catch (_) {
    return null;
  }
}

class PodcastDataSource {
  PodcastDataSource({required this._dio, required this._cache});

  final Dio _dio;
  final HttpCache _cache;

  /// The last published copy downloaded, however old; null if none yet.
  Future<String?> saved() => _cache.peek(kPodcastDataUrl);

  /// The published copy: from the cache when checked recently, else downloaded. Only a usable
  /// file is ever saved; offline with nothing saved, this throws.
  Future<String> latest() => _cache.fetch(kPodcastDataUrl, kPodcastDataCheck, () async {
    final r = await _dio.get<List<int>>(
      kPodcastDataUrl,
      options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
    );
    final text = utf8.decode(gzip.decode(r.data!));
    if (parsePublishedPodcasts(text) == null) throw const FormatException('unusable podcast data');
    return text;
  });
}

final podcastDataSourceProvider = Provider<PodcastDataSource>(
  (ref) => PodcastDataSource(dio: createDio(), cache: HttpCache(ref.watch(appDbProvider))),
);

/// The podcast lists, from the first launch: the newest of the bundled ones and the last published
/// copy downloaded. Then, in the background, a newer published copy replaces them.
class PodcastCatalogsNotifier extends AsyncNotifier<PodcastCatalogs> {
  @override
  Future<PodcastCatalogs> build() async {
    final sh = await rootBundle.loadString('assets/seed/shahnameh/podcasts.json');
    final poems = await rootBundle.loadString('assets/seed/podcasts.json');
    var lists = PodcastCatalogs(
      builtAt: ((jsonDecode(poems) as Map<String, dynamic>)['builtAt'] as String?) ?? '',
      shahnameh: parsePodcasts(sh),
      poems: parsePoemPodcasts(poems),
    );
    try {
      final saved = parsePublishedPodcasts(await ref.read(podcastDataSourceProvider).saved() ?? '');
      if (saved != null && saved.builtAt.compareTo(lists.builtAt) > 0) lists = saved;
    } catch (_) {
      // Nothing saved to read: the bundled lists it is.
    }
    final current = lists.builtAt;
    Future(() => _refresh(current));
    return lists;
  }

  Future<void> _refresh(String current) async {
    try {
      final published = parsePublishedPodcasts(await ref.read(podcastDataSourceProvider).latest());
      if (!ref.mounted || published == null || published.builtAt.compareTo(current) <= 0) return;
      state = AsyncData(published);
    } catch (_) {
      // Offline, or nothing newer: keep what we have.
    }
  }
}

final podcastCatalogsProvider = AsyncNotifierProvider<PodcastCatalogsNotifier, PodcastCatalogs>(
  PodcastCatalogsNotifier.new,
  retry: noAutoRetry,
);
