import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/podcasts/podcast_data.dart';
import 'package:ganj/features/podcasts/poem_podcasts.dart';
import 'package:ganj/features/shahnameh/data/podcasts.dart';

import '../../support/test_app.dart';

Map<String, dynamic> _asset(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// A published file built at [builtAt], with one extra episode on Hafez's first ghazal.
String published(String builtAt, {int schema = 1}) {
  final poems = _asset('assets/seed/podcasts.json');
  final ravaq = (poems['podcasts'] as List).first as Map<String, dynamic>;
  (ravaq['poems'] as Map<String, dynamic>)['/hafez/ghazal/sh1'] = [
    ...(ravaq['poems']['/hafez/ghazal/sh1'] as List),
    'new-episode',
  ];
  return jsonEncode({
    'schema': schema,
    'builtAt': builtAt,
    'shahnameh': _asset('assets/seed/shahnameh/podcasts.json'),
    'poems': poems,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(FakePodcastData data) {
    final c = ProviderContainer(overrides: [podcastDataSourceProvider.overrideWithValue(data)]);
    addTearDown(c.dispose);
    return c;
  }

  List<String> sh1(List<PoemPodcast> ps) => ps.firstWhere((p) => p.id == 'ravaq').poems['/hafez/ghazal/sh1']!;

  test('the bundled lists when nothing was published', () async {
    final c = container(FakePodcastData());
    final lists = await c.read(podcastCatalogsProvider.future);
    expect(lists.builtAt, '2026-11-16');
    expect(sh1(await c.read(poemPodcastsProvider.future)), hasLength(1));
    expect(await c.read(shPodcastsProvider.future), isNotEmpty);
  });

  test('a newer saved copy is used from the start; an older one is not', () async {
    var c = container(FakePodcastData(savedText: published('2026-12-01T03:00:00Z')));
    expect(sh1(await c.read(poemPodcastsProvider.future)), contains('new-episode'));
    c = container(FakePodcastData(savedText: published('2026-01-01T03:00:00Z')));
    expect(sh1(await c.read(poemPodcastsProvider.future)), isNot(contains('new-episode')));
  });

  test('a newer published copy replaces the lists in the background', () async {
    final c = container(FakePodcastData(latestText: published('2026-12-01T03:00:00Z')));
    expect(sh1(await c.read(poemPodcastsProvider.future)), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sh1(await c.read(poemPodcastsProvider.future)), contains('new-episode'));
  });

  test('a file in a format this app does not know is ignored', () {
    expect(parsePublishedPodcasts(published('2026-12-01', schema: 2)), isNull);
    expect(parsePublishedPodcasts('<html>captive portal</html>'), isNull);
    expect(parsePublishedPodcasts(published('2026-12-01')), isNotNull);
  });
}
