import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/poem.dart';
import '../../l10n/l10n.dart';
import '../../widgets/external_link.dart';
import '../../widgets/gold_card.dart';
import '../shahnameh/ui/podcast_sheet.dart';
import '../shahnameh/ui/sh_style.dart';
import 'poem_podcasts.dart';

/// «پادکست‌ها» on the poem page, under the recitations: podcast episodes about this poem, played in
/// the app. Collapsed by default; a feed is only fetched once the panel is opened.
class PoemPodcastPanel extends ConsumerWidget {
  const PoemPodcastPanel({super.key, required this.poem});

  final Poem poem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shows = podcastsForPoem(ref.watch(poemPodcastsProvider).value ?? const [], poem.fullUrl);
    if (shows.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    final l = context.l10n;
    final en = isEn(context);
    final count = shows.fold(0, (n, s) => n + s.$2.length);
    return GoldCard(
      key: const ValueKey('poem-podcasts'),
      color: c.inner,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.podcasts, color: c.gold),
        title: Text(l.poemPodcastsCount(localDigits(count))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (p, guids) in shows) ...[
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
            PodcastFeed(
              podcast: p,
              builder: (episodes) => Column(
                children: [
                  for (final g in guids)
                    if (episodes[g] case final e?) EpisodeTile(podcast: p, episode: e, route: '/poem/${poem.id}'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(l.shPodcastNote, style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
