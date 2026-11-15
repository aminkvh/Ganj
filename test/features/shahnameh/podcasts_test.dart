import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/data/podcasts.dart';
import 'package:ganj/features/shahnameh/ui/podcast_sheet.dart';
import 'package:ganj/features/shahnameh/ui/podcasts_screen.dart';
import 'package:ganj/features/shahnameh/ui/shahnameh_entry.dart';
import 'package:ganj/features/shahnameh/ui/story_card.dart';

import '../../support/fake_audio_backend.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  final feedXml = File('test/fixtures/shahnameh/podcast_feed.xml').readAsStringSync();

  group('bundled podcasts', () {
    test('the podcasts are there, each with a feed and credit', () {
      expect(realPodcasts.map((p) => p.id), ['khodemooni', 'reading-ferdowsi', 'dastaminophen', 'shahpod', 'whispers']);
      for (final p in realPodcasts) {
        expect(Uri.parse(p.feed).scheme, 'https', reason: p.id);
        expect(Uri.parse(p.link).scheme, 'https', reason: p.id);
        expect([p.fa, p.en, p.authorFa, p.authorEn], everyElement(isNotEmpty), reason: p.id);
      }
    });

    test('every mapped story exists, and no story lists an episode twice', () {
      for (final p in realPodcasts) {
        for (final e in p.stories.entries) {
          expect(realWorld.storyById(e.key), isNotNull, reason: '${p.id}: ${e.key}');
          expect(e.value, isNotEmpty, reason: '${p.id}: ${e.key}');
          expect(e.value.toSet(), hasLength(e.value.length), reason: '${p.id}: ${e.key}');
        }
      }
    });

    test('Reading Ferdowsi covers the whole book; Khodemooni up to the Khaqan of Chin', () {
      final rf = realPodcasts.firstWhere((p) => p.id == 'reading-ferdowsi');
      expect(rf.stories.keys, containsAll(['kayumars', 'rostam-esfandiyar', 'fall']));
      final kh = realPodcasts.firstWhere((p) => p.id == 'khodemooni');
      expect(kh.stories['sohrab'], [
        'shenoto-rss-239249',
        'shenoto-rss-245496',
        'shenoto-rss-251254',
        'shenoto-rss-256985',
      ]);
      expect(kh.stories.keys.last, 'khaqan');
    });
  });

  group('feed', () {
    test('episodes by guid, with audio and length; items without audio are skipped', () {
      final eps = parsePodcastFeed(feedXml);
      expect(eps.keys, ['shenoto-rss-256985', 'shenoto-rss-239249']);
      final e = eps['shenoto-rss-256985']!;
      expect(e.title, 'اپیزود۲۹- سهراب‌کُشون');
      expect(e.audioUrl, 'https://example.org/29.mp3');
      expect(e.duration, const Duration(hours: 1, minutes: 23, seconds: 33));
      expect(eps['shenoto-rss-239249']!.duration, isNull, reason: '00:00 means unknown');
    });

    test('itunes durations', () {
      expect(parseItunesDuration('58:24'), const Duration(minutes: 58, seconds: 24));
      expect(parseItunesDuration('3910'), const Duration(seconds: 3910));
      expect(parseItunesDuration('1:05:10'), const Duration(hours: 1, minutes: 5, seconds: 10));
      expect(parseItunesDuration('abc'), isNull);
      expect(parseItunesDuration(null), isNull);
    });

    test('lengths in the interface digits', () {
      expect(episodeLength(const Duration(minutes: 58, seconds: 4)), '۵۸:۰۴');
      latinNumbers = true;
      addTearDown(() => latinNumbers = false);
      expect(episodeLength(const Duration(hours: 1, minutes: 5, seconds: 10)), '1:05:10');
    });
  });

  testWidgets('a story with podcasts: listen, pick an episode, it plays in the app', (tester) async {
    phone(tester);
    final backend = FakeAudioBackend();
    final fetched = <String>[];
    final prefs = await mockPrefs({'language': 'fa'});
    await tester.pumpWidget(
      testAppRouted(
        '/shahnameh?tab=timeline&section=13',
        prefs: prefs,
        backend: backend,
        overrides: [
          ...shOverrides(),
          podcastFeedFetcherProvider.overrideWithValue((url) async {
            fetched.add(url);
            return feedXml;
          }),
        ],
      ),
    );
    await settle(tester);
    final card = find.byKey(const ValueKey('story-sohrab'));
    await tester.tap(find.descendant(of: card, matching: find.text('شنیدن')));
    await settle(tester);

    expect(find.text('پادکست‌های این داستان'), findsOneWidget);
    expect(fetched, containsAll(['https://shenoto.net/feed/shahname']));
    // Only the episodes the fixture feed has are listed.
    expect(find.byKey(const ValueKey('podcast-khodemooni-shenoto-rss-256985')), findsOneWidget);
    expect(find.text('۱:۲۳:۳۳'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('podcast-khodemooni-shenoto-rss-239249')));
    await settle(tester);
    expect(find.text('پادکست‌های این داستان'), findsNothing, reason: 'the sheet closes');
    expect(backend.loaded.single.toString(), 'https://example.org/26.mp3');
    expect(backend.isPlaying, isTrue);
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('mini-player')), matching: find.text('شاهنامه خودمونی')),
      findsOneWidget,
    );
  });

  testWidgets('a story with no podcast has no listen button', (tester) async {
    phone(tester);
    final prefs = await mockPrefs({'language': 'fa'});
    final sohrab = realWorld.storyById('sohrab')!;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: StoryCard(world: realWorld, story: sohrab),
          ),
        ),
        prefs: prefs,
        overrides: shOverrides(podcasts: const []),
      ),
    );
    await settle(tester);
    expect(find.text('خواندن'), findsOneWidget);
    expect(find.text('شنیدن'), findsNothing);
  });

  testWidgets('the Shahnameh page has a podcasts card; it lists the episodes story by story', (tester) async {
    phone(tester);
    final backend = FakeAudioBackend();
    final fetched = <String>[];
    final prefs = await mockPrefs({'language': 'fa'});
    await tester.pumpWidget(
      testAppRouted(
        '/cat/33',
        prefs: prefs,
        backend: backend,
        overrides: [
          ...shOverrides(),
          podcastFeedFetcherProvider.overrideWithValue((url) async {
            fetched.add(url);
            return feedXml;
          }),
        ],
      ),
    );
    await settle(tester);
    final card = find.byKey(const ValueKey('shahnameh-podcasts-card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.textContaining('شاهنامه خودمونی · فردوسی‌خوانی · ')),
      findsOneWidget,
    );
    await tester.tap(card);
    await settle(tester);

    expect(find.byType(PodcastsScreen), findsOneWidget);
    expect(fetched, ['https://shenoto.net/feed/shahname']);
    // The fixture feed has two Sohrab episodes: one story heading, its episodes in listening order.
    expect(find.byKey(const ValueKey('podcast-story-sohrab')), findsOneWidget);
    expect(find.byKey(const ValueKey('podcast-story-kayumars')), findsNothing, reason: 'not in this feed');
    final first = tester.getTopLeft(find.byKey(const ValueKey('podcast-khodemooni-shenoto-rss-239249'))).dy;
    final last = tester.getTopLeft(find.byKey(const ValueKey('podcast-khodemooni-shenoto-rss-256985'))).dy;
    expect(first, lessThan(last));

    await tester.tap(find.byKey(const ValueKey('podcast-khodemooni-shenoto-rss-256985')));
    await settle(tester);
    expect(backend.loaded.single.toString(), 'https://example.org/29.mp3');
    expect(find.byType(PodcastsScreen), findsOneWidget, reason: 'the page stays open while it plays');

    await tester.tap(find.byKey(const ValueKey('podcast-picker')));
    await settle(tester);
    await tester.tap(find.text('فردوسی‌خوانی').last);
    await settle(tester);
    expect(fetched.last, startsWith('https://feeds.acast.com/'));
  });

  testWidgets('a section of the Shahnameh has the hub banner but no podcasts card', (tester) async {
    phone(tester);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testAppRouted('/cat/35', prefs: prefs, overrides: shOverrides()));
    await settle(tester);
    expect(find.byType(ShahnamehBanner), findsOneWidget);
    expect(find.byKey(const ValueKey('shahnameh-podcasts-card')), findsNothing);
  });
}
