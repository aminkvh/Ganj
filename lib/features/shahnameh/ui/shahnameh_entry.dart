import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../data/api/dto/cat.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/gold_card.dart';
import '../data/podcasts.dart';

/// Ganjoor's category id of the Shahnameh.
const kShahnamehCatId = 33;

bool isShahnamehCat(Cat cat) => cat.id == kShahnamehCatId || cat.ancestors.any((a) => a.id == kShahnamehCatId);

/// On the Shahnameh's pages: the way into «جهان شاهنامه».
class ShahnamehBanner extends StatelessWidget {
  const ShahnamehBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    return GoldCard(
      color: c.inner,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/shahnameh'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined, color: c.gold, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.shahnamehWorld, style: nastaliqOf(context, 20).copyWith(color: c.brandRed)),
                      Text(l.shBannerSubtitle, style: TextStyle(color: c.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(
                  Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left : Icons.chevron_right,
                  color: c.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// On the Shahnameh's own page, under the banner: the way to every podcast episode.
class ShahnamehPodcastsCard extends ConsumerWidget {
  const ShahnamehPodcastsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podcasts = ref.watch(shPodcastsProvider).value ?? const [];
    if (podcasts.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    final en = Localizations.localeOf(context).languageCode == 'en';
    return GoldCard(
      key: const ValueKey('shahnameh-podcasts-card'),
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/shahnameh/podcasts'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Icon(Icons.headphones_outlined, color: c.gold, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.shPodcasts,
                        style: TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [for (final p in podcasts) en ? p.en : p.fa].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left : Icons.chevron_right,
                  color: c.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
