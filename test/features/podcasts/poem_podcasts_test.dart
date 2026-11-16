import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/podcasts/poem_podcasts.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/shahnameh/data/podcasts.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';

final List<PoemPodcast> realPoemPodcasts = parsePoemPodcasts(File('assets/seed/podcasts.json').readAsStringSync());

const _fake = PoemPodcast(
  id: 'fake',
  fa: 'پادکست آزمایشی',
  en: 'Test podcast',
  authorFa: 'گوینده',
  authorEn: 'Host',
  feed: 'https://example.org/feed.xml',
  link: 'https://example.org/',
  poems: {
    '/hafez/ghazal/sh1': ['shenoto-rss-239249', 'not-in-the-feed'],
    '/hafez/ghazal/sh2': ['shenoto-rss-256985'],
  },
);

void main() {
  final feedXml = File('test/fixtures/shahnameh/podcast_feed.xml').readAsStringSync();

  group('bundled poem podcasts', () {
    test('each has a feed, credit and a unique id', () {
      expect(realPoemPodcasts, isNotEmpty);
      expect(realPoemPodcasts.map((p) => p.id).toSet(), hasLength(realPoemPodcasts.length));
      for (final p in realPoemPodcasts) {
        expect(Uri.parse(p.feed).scheme, 'https', reason: p.id);
        expect(Uri.parse(p.link).scheme, 'https', reason: p.id);
        expect([p.fa, p.en, p.authorFa, p.authorEn], everyElement(isNotEmpty), reason: p.id);
        expect(p.poems, isNotEmpty, reason: p.id);
      }
    });

    test('poems are Ganjoor paths, none lists an episode twice', () {
      final path = RegExp(r'^/[a-z0-9-]+(/[a-z0-9-]+)*/sh\d+$');
      for (final p in realPoemPodcasts) {
        for (final e in p.poems.entries) {
          expect(e.key, matches(path), reason: '${p.id}: ${e.key}');
          expect(e.value, isNotEmpty, reason: '${p.id}: ${e.key}');
          expect(e.value.toSet(), hasLength(e.value.length), reason: '${p.id}: ${e.key}');
        }
      }
    });

    test('Ravaq covers all of Hafez\'s ghazals', () {
      final ravaq = realPoemPodcasts.firstWhere((p) => p.id == 'ravaq');
      for (var n = 1; n <= 495; n++) {
        expect(ravaq.poems['/hafez/ghazal/sh$n'], hasLength(1), reason: 'ghazal $n');
      }
    });
  });

  test('podcasts for a poem', () {
    expect(podcastsForPoem(const [_fake], '/hafez/ghazal/sh2').single.$2, ['shenoto-rss-256985']);
    expect(podcastsForPoem(const [_fake], '/hafez/ghazal/sh3'), isEmpty);
  });

  testWidgets('a poem with podcasts: the panel fetches the feed only when opened, and plays', (tester) async {
    final backend = FakeAudioBackend();
    final fetched = <String>[];
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        backend: backend,
        overrides: [
          poemPodcastsProvider.overrideWithValue(const AsyncData([_fake])),
          podcastFeedFetcherProvider.overrideWithValue((url) async {
            fetched.add(url);
            return feedXml;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('poem-podcasts'));
    expect(panel, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('پادکست‌ها (۲)')), findsOneWidget);
    expect(fetched, isEmpty, reason: 'nothing is fetched until the panel is opened');

    await tester.ensureVisible(panel);
    await tester.tap(find.text('پادکست‌ها (۲)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(fetched, ['https://example.org/feed.xml']);
    expect(find.byKey(const ValueKey('podcast-fake-shenoto-rss-239249')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-fake-shenoto-rss-256985')), findsNothing, reason: 'another poem');

    await tester.tap(find.byKey(const ValueKey('podcast-fake-shenoto-rss-239249')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(backend.loaded.single.toString(), 'https://example.org/26.mp3');
    expect(backend.isPlaying, isTrue);
  });

  testWidgets('a poem without podcasts shows no panel', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        backend: FakeAudioBackend(),
        overrides: [poemPodcastsProvider.overrideWithValue(const AsyncData([]))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('poem-podcasts')), findsNothing);
  });
}
