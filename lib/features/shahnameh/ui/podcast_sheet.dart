import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/external_link.dart';
import '../../player/player_controller.dart';
import '../data/models.dart';
import '../data/podcasts.dart';
import 'sh_style.dart';

/// The podcasts that have episodes on [story].
List<ShPodcast> podcastsFor(List<ShPodcast> all, String story) => [
  for (final p in all)
    if (p.stories[story]?.isNotEmpty ?? false) p,
];

/// "1:05:10" / "58:24" in the interface's digits.
String episodeLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return localDigits(h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}');
}

/// The podcast episodes about [story], to play in the app.
Future<void> showPodcastSheet(BuildContext context, ShStory story, List<ShPodcast> podcasts) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.ganj.page,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scroll) => PodcastPanel(story: story, podcasts: podcasts, scroll: scroll),
    ),
  );
}

class PodcastPanel extends ConsumerWidget {
  const PodcastPanel({super.key, required this.story, required this.podcasts, this.scroll});

  final ShStory story;
  final List<ShPodcast> podcasts;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    final en = isEn(context);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          l.shPodcastsTitle,
          style: TextStyle(color: c.ink, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(en ? story.en : story.fa, style: TextStyle(color: c.muted)),
        for (final p in podcasts) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: en ? p.en : p.fa,
                        style: TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' · ${en ? p.authorEn : p.authorFa}',
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l.shPodcastPage,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(Icons.open_in_new, color: c.muted),
                onPressed: () => openExternal(context, p.link),
              ),
            ],
          ),
          _Episodes(podcast: p, story: story),
        ],
        const SizedBox(height: 12),
        Text(l.shPodcastNote, style: TextStyle(color: c.muted, fontSize: 12)),
      ],
    );
  }
}

class _Episodes extends StatelessWidget {
  const _Episodes({required this.podcast, required this.story});

  final ShPodcast podcast;
  final ShStory story;

  @override
  Widget build(BuildContext context) => PodcastFeed(
    podcast: podcast,
    builder: (episodes) => Column(
      children: [
        for (final guid in podcast.stories[story.id] ?? const <String>[])
          if (episodes[guid] case final e?)
            EpisodeTile(podcast: podcast, episode: e, route: storyRoute(story), closeOnPlay: true),
      ],
    ),
  );
}

/// A podcast's feed: [builder] once it has loaded; a bar while loading; a retry when it fails.
class PodcastFeed extends ConsumerWidget {
  const PodcastFeed({super.key, required this.podcast, required this.builder});

  final PodcastShow podcast;
  final Widget Function(Map<String, PodcastEpisode> episodes) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    return switch (ref.watch(podcastEpisodesProvider(podcast.feed))) {
      AsyncData(:final value) => builder(value),
      AsyncError() => Row(
        children: [
          Expanded(
            child: Text(l.shPodcastFailed, style: TextStyle(color: c.muted)),
          ),
          TextButton(onPressed: () => ref.invalidate(podcastEpisodesProvider(podcast.feed)), child: Text(l.retry)),
        ],
      ),
      _ => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
    };
  }
}

/// Where the mini player leads back to for an episode about [story]: the story on the timeline.
String storyRoute(ShStory story) => '/shahnameh?tab=timeline&section=${story.from}';

/// One episode: tap to play it in the app. The mini player leads back to [route].
class EpisodeTile extends ConsumerWidget {
  const EpisodeTile({
    super.key,
    required this.podcast,
    required this.episode,
    required this.route,
    this.closeOnPlay = false,
  });

  final PodcastShow podcast;
  final PodcastEpisode episode;
  final String route;

  /// Close the sheet it sits in once playing.
  final bool closeOnPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final id = '${podcast.id}/${episode.guid}';
    final playing = ref.watch(playerProvider.select((s) => s.episode?.id == id));
    return ListTile(
      key: ValueKey('podcast-${podcast.id}-${episode.guid}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(playing ? Icons.graphic_eq : Icons.play_circle_outline, color: c.brandRed),
      title: Text(episode.title),
      subtitle: episode.duration == null ? null : Text(episodeLength(episode.duration!)),
      onTap: () {
        ref
            .read(playerProvider.notifier)
            .playEpisode(
              PlayerEpisode(
                id: id,
                title: episode.title,
                podcast: isEn(context) ? podcast.en : podcast.fa,
                audioUrl: episode.audioUrl,
                route: route,
              ),
            );
        if (closeOnPlay) Navigator.of(context).maybePop();
      },
    );
  }
}
