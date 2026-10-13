import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/ai_badge.dart';
import '../data/models.dart';
import '../data/shahnameh_providers.dart';
import 'person_sheet.dart';
import 'sh_style.dart';

/// A story on the timeline: its title, one line of what happens, who is in it and where,
/// and the ways onwards — read it, or see it on the map.
class StoryCard extends ConsumerWidget {
  const StoryCard({super.key, required this.world, required this.story, this.highlight = false, this.onMap});

  final ShWorld world;
  final ShStory story;
  final bool highlight;

  /// Instead of [showOnMap] — for a card shown in a sheet, which must close first.
  final void Function({String? story, String? place})? onMap;

  /// Ganjoor's summary of the story's first summarised poem (Persian), and whether Ganjoor's
  /// AI wrote it.
  (String, bool)? _summaryFa() {
    for (final o in story.sections) {
      for (final p in world.sections[o].poems) {
        if (world.summaries[p.id] case final s?) return (s, world.aiSummaries.contains(p.id));
      }
    }
    return null;
  }

  int? get _firstPoem {
    final poems = world.sections[story.from].poems;
    return poems.isEmpty ? null : poems.first.id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    final en = isEn(context);
    final tint = ageTint(context, story.age);
    final ganjoor = _summaryFa();
    // (text, Ganjoor's AI wrote it); Ganj's own summaries are covered by the card's badge.
    final (String, bool)? summary = en
        ? (story.summaryEn != null ? (story.summaryEn!, false) : ganjoor)
        : (ganjoor ?? (story.summaryEn != null ? (story.summaryEn!, false) : null));
    final places = [for (final id in story.places) ?world.placeById(id)];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? c.goldLight.withValues(alpha: 0.6) : c.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? tint : c.borderGold.withValues(alpha: 0.6), width: highlight ? 2 : 1),
        boxShadow: [BoxShadow(color: c.ink.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    en ? story.en : story.fa,
                    style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const Padding(padding: EdgeInsets.only(top: 3), child: GanjAiBadge()),
                IconButton(
                  tooltip: l.shReport,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(Icons.flag_outlined, color: c.muted),
                  onPressed: () => reportProblem(
                    context,
                    ref,
                    what: '${story.fa} (${story.en}) — ${story.id}',
                    path: '/shahnameh?tab=timeline&section=${story.from}',
                  ),
                ),
              ],
            ),
            if (en) Text(story.fa, style: TextStyle(color: c.muted, fontSize: 13)),
            if (summary case (final text, final ai))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: text),
                      if (ai) ...[
                        const TextSpan(text: '  '),
                        const WidgetSpan(alignment: PlaceholderAlignment.middle, child: AiBadge()),
                      ],
                    ],
                  ),
                  style: TextStyle(color: c.ink.withValues(alpha: 0.85), height: 1.7),
                ),
              ),
            if (story.people.isNotEmpty || places.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final id in story.people.take(8))
                      if (world.people.containsKey(id))
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(personName(context, world, id)),
                          side: BorderSide(color: tint.withValues(alpha: 0.5)),
                          onPressed: () => openPerson(context, id),
                        ),
                    for (final p in places)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.place_outlined, size: 16, color: c.brandRed),
                        label: Text(placeName(context, p)),
                        onPressed: () => onMap != null ? onMap!(place: p.id) : showOnMap(context, ref, place: p.id),
                      ),
                  ],
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                if (_firstPoem case final id?)
                  TextButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(l.shRead),
                    onPressed: () => context.push('/poem/$id'),
                  ),
                if (places.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(l.shShowOnMap),
                    onPressed: () => onMap != null ? onMap!(story: story.id) : showOnMap(context, ref, story: story.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Switches the hub to its map with a story or a place chosen (or opens the hub there).
void showOnMap(BuildContext context, WidgetRef ref, {String? story, String? place}) {
  final sel = ref.read(shSelectionProvider.notifier);
  place == null ? sel.showStory(story) : sel.showPlace(place);
  final tabs = DefaultTabController.maybeOf(context);
  if (tabs != null) {
    tabs.animateTo(1);
  } else {
    context.push(place == null ? '/shahnameh?tab=map&story=$story' : '/shahnameh?tab=map&place=$place');
  }
}
