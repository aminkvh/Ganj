import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/content_en.dart';
import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/literary.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../widgets/gold_card.dart';
import '../poem/couplets.dart';

/// Poets Ganjoor has tagged at all (cached a day).
final literaryPoetsProvider = FutureProvider<Set<int>>(
  (ref) => ref.watch(ganjoorApiProvider).literaryPoets(),
  retry: noAutoRetry,
);

/// The devices and their roles, by id (cached a month).
final literaryCatalogProvider = FutureProvider<Map<int, LiteraryDevice>>((ref) async {
  final list = await ref.watch(ganjoorApiProvider).literaryDevices();
  return {for (final d in list) d.id: d};
}, retry: noAutoRetry);

/// A poem's tags, with the devices they use.
typedef PoemLiterary = ({List<LiteraryTag> tags, Map<int, LiteraryDevice> catalog});

/// A poem's tags and the devices to read them by; nothing is fetched for poets Ganjoor hasn't
/// tagged, and the device list only for poems that have tags.
final poemLiteraryProvider = FutureProvider.autoDispose.family<PoemLiterary, ({int poemId, int poetId})>((
  ref,
  k,
) async {
  const none = (tags: <LiteraryTag>[], catalog: <int, LiteraryDevice>{});
  final poets = await ref.watch(literaryPoetsProvider.future);
  if (!poets.contains(k.poetId)) return none;
  final api = ref.watch(ganjoorApiProvider);
  final tags = await api.literaryTags(k.poemId);
  if (tags.isEmpty) return none;
  var catalog = await ref.watch(literaryCatalogProvider.future);
  if (tags.any((t) => !catalog.containsKey(t.deviceId))) {
    // A device defined after the list was cached: fetch the list again rather than drop the tag.
    catalog = {for (final d in await api.literaryDevices(refresh: true)) d.id: d};
  }
  return (tags: tags, catalog: catalog);
}, retry: noAutoRetry);

/// A device as shown under a beyt: its name and each role with the words that fill it.
class BeytDevice {
  const BeytDevice({required this.name, required this.roles, this.definition, this.uncertain = false});

  final String name;
  final String? definition;
  final List<(String role, String value)> roles;
  final bool uncertain;
}

const _english = {
  'tashbih': 'Simile',
  'esteare': 'Metaphor',
  'kenaye': 'Kenaye (implied meaning)',
  'majaz': 'Metonymy',
  'jenas': 'Pun',
  'tekrar': 'Repetition',
  'iham': 'Double meaning (iham)',
  'tazad': 'Antithesis',
  'eghragh': 'Hyperbole',
  'talmih': 'Allusion',
};

/// The devices tagged on [c]. A role that points at words shows them as the beyt has them;
/// otherwise its concept or free text.
List<BeytDevice> devicesOf(Couplet c, List<LiteraryTag> tags, Map<int, LiteraryDevice> catalog) => [
  for (final t in tags)
    if (t.coupletIndex == c.index)
      if (catalog[t.deviceId] case final d?)
        BeytDevice(
          name: englishContent != null ? (_english[d.key] ?? d.name) : d.name,
          definition: d.definition,
          uncertain: t.uncertain,
          roles: [
            for (final p in t.parts)
              if (_valueOf(c, p) case final v?) (d.slots[p.slotId] ?? '', v),
          ],
        ),
];

String? _valueOf(Couplet c, LiteraryPart p) {
  final start = p.wordStart, end = p.wordEnd ?? p.wordStart;
  if (p.misra > 0 && p.misra <= c.verses.length && start != null && end != null) {
    final words = c.verses[p.misra - 1].text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (start >= 1 && end >= start && end <= words.length) return words.sublist(start - 1, end).join(' ');
  }
  for (final s in [p.concept, p.text]) {
    if (s != null && s.trim().isNotEmpty) return s.trim();
  }
  return null;
}

/// The devices of one beyt, one quiet line each: the device, then its roles.
class BeytDevicesBlock extends StatelessWidget {
  const BeytDevicesBlock({super.key, required this.devices});

  final List<BeytDevice> devices;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in devices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Tooltip(
              message: d.definition ?? '',
              triggerMode: TooltipTriggerMode.tap,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: d.name,
                      style: TextStyle(color: c.brandRed, fontWeight: FontWeight.w600),
                    ),
                    if (d.uncertain) TextSpan(text: ' (${context.l10n.literaryUncertain})'),
                    for (final (i, (role, value)) in d.roles.indexed) ...[
                      TextSpan(text: i == 0 ? '  ' : '  ·  '),
                      if (role.isNotEmpty) TextSpan(text: '$role: '),
                      TextSpan(
                        text: value,
                        style: TextStyle(color: c.ink),
                      ),
                    ],
                  ],
                ),
                style: TextStyle(color: c.muted, height: 1.8),
              ),
            ),
          ),
      ],
    );
  }
}

/// Under the poem, with its other sections: every tagged beyt and its devices. Shown only
/// when Ganjoor has tagged the poem.
class PoemDevicesPanel extends ConsumerWidget {
  const PoemDevicesPanel({super.key, required this.poemId, required this.poetId, required this.couplets});

  final int poemId, poetId;
  final List<Couplet> couplets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(poemLiteraryProvider((poemId: poemId, poetId: poetId))).value;
    if (data == null || data.tags.isEmpty) return const SizedBox.shrink();
    final (:tags, :catalog) = data;
    final c = context.ganj;
    final beyts = [
      for (final cp in couplets)
        if (devicesOf(cp, tags, catalog) case final ds when ds.isNotEmpty) (cp, ds),
    ];
    if (beyts.isEmpty) return const SizedBox.shrink();
    return GoldCard(
      key: const ValueKey('panel-literary'),
      color: c.inner,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.auto_awesome_outlined, color: c.gold),
        title: Text(context.l10n.literaryDevices),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (cp, ds) in beyts) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: context.l10n.beytN(localDigits(cp.index + 1)),
                      style: TextStyle(color: c.gold, fontSize: 12),
                    ),
                    TextSpan(text: '   ${cp.verses.first.text}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ),
            BeytDevicesBlock(devices: ds),
          ],
          if (tags.any((t) => t.fromCorpus))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(context.l10n.literaryCorpusNote, style: TextStyle(color: c.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
