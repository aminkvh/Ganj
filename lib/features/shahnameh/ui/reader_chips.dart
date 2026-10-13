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
    final people = w?.poemPeople[poemId];
    if (w == null || people == null || people.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    final ordered = [...people]..sort((a, b) => a.$2.compareTo(b.$2));
    // Map place id → label; places only Ganjoor knows are addressed as `g<location id>`.
    final places = <String, String>{};
    for (final t in w.ganjoorTags) {
      if (t.poemId != poemId) continue;
      final curated = w.places.where((p) => p.ganjoorId == t.locationId).firstOrNull;
      places[curated?.id ?? 'g${t.locationId}'] ??= curated == null ? t.name : placeName(context, curated);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.shPeople, style: TextStyle(color: c.muted, fontSize: 13)),
              if (people.any((p) => w.isAiTag(poemId, p.$1))) ...[
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
