import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/ai_badge.dart';
import '../data/shahnameh_providers.dart';
import 'person_sheet.dart';
import 'sh_style.dart';

/// Under a Shahnameh poem, as on ganjoor.net: «نامبردگان» (people in the story first,
/// passing mentions muted) and the places Ganjoor tagged. Other poems: nothing.
class ShahnamehPeopleChips extends ConsumerWidget {
  const ShahnamehPeopleChips({super.key, required this.poemId});

  final int poemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(shahnamehWorldProvider).value;
    if (w == null) return const SizedBox.shrink();
    // Ganjoor's current tags when it answers; the bundled ones meanwhile and offline.
    final live = ref.watch(poemTagsProvider(poemId)).value;
    final List<(int, int)> people;
    final Set<int> aiPeople;
    final List<(int locationId, String name, double lat, double lng)> liveSpots;
    if (live != null && live.isNotEmpty) {
      final best = <int, int>{};
      for (final t in live) {
        if (t.personId case final id? when w.people.containsKey(id)) {
          best[id] = best.containsKey(id) && best[id]! < t.mention ? best[id]! : t.mention;
        }
      }
      people = [for (final e in best.entries) (e.key, e.value)];
      aiPeople = {
        for (final t in live)
          if (t.ai && t.personId != null) t.personId!,
      };
      final locations = {for (final l in ref.watch(ganjoorLocationsProvider).value ?? const []) l.id: l};
      liveSpots = [
        for (final t in live)
          if (t.locationId case final loc?)
            if (locations[loc] case final l?) (l.id, l.name, l.lat, l.lng),
      ];
    } else {
      people = w.poemPeople[poemId] ?? const [];
      aiPeople = {
        for (final (id, _) in people)
          if (w.isAiTag(poemId, id)) id,
      };
      liveSpots = const [];
    }
    if (people.isEmpty && liveSpots.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    final ordered = [...people]..sort((a, b) => a.$2.compareTo(b.$2));
    // Map place id → label; places only Ganjoor knows are addressed as `g<location id>`.
    final places = <String, String>{};
    final spots = live != null && live.isNotEmpty
        ? liveSpots
        : [
            for (final t in w.ganjoorTags)
              if (t.poemId == poemId) (t.locationId, t.name, t.lat, t.lng),
          ];
    for (final (loc, name, _, _) in spots) {
      final curated = w.places.where((p) => p.ganjoorId == loc).firstOrNull;
      places[curated?.id ?? 'g$loc'] ??= curated == null ? name : placeName(context, curated);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.shPeople, style: TextStyle(color: c.muted, fontSize: 13)),
              if (aiPeople.isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: context.l10n.shAiTagsNote,
                  triggerMode: TooltipTriggerMode.tap,
                  child: const AiBadge(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final (id, mention) in ordered)
                if (w.people.containsKey(id))
                  ActionChip(
                    label: Text(personName(context, w, id), style: TextStyle(color: mention == 0 ? c.ink : c.muted)),
                    side: BorderSide(color: mention == 0 ? c.gold : c.borderGold.withValues(alpha: 0.5)),
                    onPressed: () => openPerson(context, id),
                  ),
              for (final MapEntry(key: id, value: label) in places.entries)
                ActionChip(
                  avatar: Icon(Icons.place_outlined, size: 16, color: c.brandRed),
                  label: Text(label),
                  onPressed: () => context.push('/shahnameh?tab=map&place=$id'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
