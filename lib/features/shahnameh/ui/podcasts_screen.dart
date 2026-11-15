import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/error_retry.dart';
import '../../../widgets/external_link.dart';
import '../../../widgets/home_button.dart';
import '../data/models.dart';
import '../data/podcasts.dart';
import '../data/shahnameh_providers.dart';
import 'podcast_sheet.dart';
import 'sh_style.dart';

/// Every episode of the Shahnameh podcasts, story by story in the book's order.
class PodcastsScreen extends ConsumerStatefulWidget {
  const PodcastsScreen({super.key, this.podcast});

  /// The podcast to show first (its id).
  final String? podcast;

  @override
  ConsumerState<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends ConsumerState<PodcastsScreen> {
  String? _chosen;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final podcasts = ref.watch(shPodcastsProvider);
    final world = ref.watch(shahnamehWorldProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.shPodcasts), actions: const [HomeButton()]),
      body: switch ((podcasts, world)) {
        (AsyncData(value: final ps), AsyncData(value: final w)) when ps.isNotEmpty => _body(
          context,
          ps.firstWhere((p) => p.id == (_chosen ?? widget.podcast), orElse: () => ps.first),
          ps,
          w,
        ),
        (AsyncError(), _) || (_, AsyncError()) => ErrorRetry(
          onRetry: () {
            ref.invalidate(shPodcastsProvider);
            ref.invalidate(shahnamehWorldProvider);
          },
        ),
        (AsyncData(), AsyncData()) => const SizedBox.shrink(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, ShPodcast p, List<ShPodcast> all, ShWorld w) {
    final c = context.ganj;
    final l = context.l10n;
    final en = isEn(context);
    // An episode on two stories is listed once, under the first.
    final seen = <String>{};
    final stories = [
      for (final s in w.ages.expand((a) => a.stories))
        if ([
              for (final g in p.stories[s.id] ?? const <String>[])
                if (seen.add(g)) g,
            ]
            case final gs when gs.isNotEmpty)
          (s, gs),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (all.length > 1)
          DropdownButtonFormField<String>(
            key: const ValueKey('podcast-picker'),
            initialValue: p.id,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [
              for (final x in all)
                DropdownMenuItem(
                  value: x.id,
                  child: Text(en ? x.en : x.fa, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _chosen = v),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(en ? p.authorEn : p.authorFa, style: TextStyle(color: c.muted)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l.shPodcastPage),
              onPressed: () => openExternal(context, p.link),
            ),
          ],
        ),
        PodcastFeed(
          key: ValueKey(p.id),
          podcast: p,
          builder: (episodes) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (s, guids) in stories)
                if (guids.any(episodes.containsKey)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 2),
                    child: Text(
                      en ? s.en : s.fa,
                      key: ValueKey('podcast-story-${s.id}'),
                      style: TextStyle(color: ageTint(context, s.age), fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final g in guids)
                    if (episodes[g] case final e?) EpisodeTile(podcast: p, episode: e, story: s),
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(l.shPodcastNote, style: TextStyle(color: c.muted, fontSize: 12)),
      ],
    );
  }
}
