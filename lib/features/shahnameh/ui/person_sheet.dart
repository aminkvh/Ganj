import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../data/api/dto/people.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/ai_badge.dart';
import '../data/models.dart';
import '../data/relation_kinds.dart';
import '../data/shahnameh_providers.dart';
import 'hub_screen.dart' show kShTabs;
import 'sh_style.dart';

/// Opens a person: a bottom sheet on phones, a side panel on wide screens, so the page
/// underneath (the timeline, the map, a poem) stays where it was.
Future<void> openPerson(BuildContext context, int id) {
  // Inside the hub, the sheet's links switch the hub's tabs instead of opening another hub.
  final tabs = DefaultTabController.maybeOf(context);
  final selection = tabs == null ? null : ProviderScope.containerOf(context).read(shSelectionProvider.notifier);
  HubLink? hub(BuildContext sheet) => tabs == null
      ? null
      : (tab, {section, place, focus}) {
          Navigator.of(sheet).pop();
          if (section != null) selection!.showSection(section);
          if (place != null) selection!.showPlace(place);
          if (focus != null) selection!.showFocus(focus);
          tabs.animateTo(kShTabs.indexOf(tab));
        };
  if (MediaQuery.sizeOf(context).width >= 900) {
    return showGeneralDialog(
      context: context,
      // Beside the pages (like the bottom sheets), so a poem or tree opened from it shows on top.
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      pageBuilder: (sheet, _, _) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Material(
          color: sheet.ganj.page,
          elevation: 8,
          child: SizedBox(
            width: 460,
            height: double.infinity,
            child: SafeArea(
              child: PersonPanel(id: id, hub: hub(sheet)),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.ganj.page,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (_, scroll) => PersonPanel(id: id, scrollController: scroll, hub: hub(sheet)),
    ),
  );
}

/// Switches the hub to [tab] (one of [kShTabs]) with something chosen there.
typedef HubLink = void Function(String tab, {int? section, String? place, int? focus});

/// Everything about one person; tapping someone else opens them here, with a way back.
class PersonPanel extends ConsumerStatefulWidget {
  const PersonPanel({super.key, required this.id, this.scrollController, this.hub});

  final int id;
  final ScrollController? scrollController;

  /// Set when opened inside the hub; otherwise links open the hub.
  final HubLink? hub;

  @override
  ConsumerState<PersonPanel> createState() => _PersonPanelState();
}

class _PersonPanelState extends ConsumerState<PersonPanel> {
  late final _trail = [widget.id];

  int get _id => _trail.last;

  void _open(int id) => setState(() => _trail.add(id));

  @override
  Widget build(BuildContext context) {
    final world = ref.watch(shahnamehWorldProvider).value;
    final p = world?.people[_id];
    if (world == null) return const Center(child: CircularProgressIndicator());
    if (p == null) {
      return Center(
        child: Text(context.l10n.notFoundPage, style: TextStyle(color: context.ganj.muted)),
      );
    }
    return PopScope(
      canPop: _trail.length == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_trail.removeLast);
      },
      child: ListView(
        key: ValueKey(_id),
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _Header(world: world, person: p, onBack: _trail.length > 1 ? () => setState(_trail.removeLast) : null),
          if (world.firstSection(p.id) != null) _Presence(world: world, person: p, hub: widget.hub),
          _Ties(world: world, person: p, onOpen: _open),
          _Actions(world: world, person: p, hub: widget.hub),
          _Places(world: world, person: p, hub: widget.hub),
          _TaggedPoems(person: p.id),
          _Report(person: p),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.world, required this.person, this.onBack});

  final ShWorld world;
  final ShPerson person;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    final first = world.firstSection(person.id);
    final tint = first == null ? c.borderGold : ageTint(context, world.ageOfSection(first).index);
    final en = person.en;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.only(start: 14, top: 4, bottom: 4),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: tint, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
              Expanded(
                child: Text(person.name, style: nastaliqOf(context, 30).copyWith(color: c.brandRed)),
              ),
            ],
          ),
          if (en != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  en,
                  style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const GanjAiBadge(),
              ],
            ),
          if (first != null)
            Text(ageName(context, world.ageOfSection(first)), style: TextStyle(color: tint, fontSize: 13)),
          if (person.aliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${l.shAliases}: ${person.aliases.join('، ')}', style: TextStyle(color: c.muted)),
            ),
          if (person.description case final d? when d.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: d),
                    if (person.aiDescription) ...[
                      const TextSpan(text: '  '),
                      const WidgetSpan(alignment: PlaceholderAlignment.middle, child: AiBadge()),
                    ],
                  ],
                ),
                style: TextStyle(color: c.ink, height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.ai = false});

  final String text;

  /// The section rests on Ganjoor's AI-suggested tags.
  final bool ai;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Row(
      children: [
        Flexible(
          child: Text(text, style: nastaliqOf(context, 20).copyWith(color: context.ganj.lapis)),
        ),
        if (ai) ...[
          const SizedBox(width: 8),
          Tooltip(message: context.l10n.shAiTagsNote, triggerMode: TooltipTriggerMode.tap, child: const AiBadge()),
        ],
      ],
    ),
  );
}

class _Presence extends StatelessWidget {
  const _Presence({required this.world, required this.person, this.hub});

  final HubLink? hub;

  final ShWorld world;
  final ShPerson person;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final present = world.presence[person.id] ?? const [];
    final ages = {for (final o in present) world.ageOfSection(o).index};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(context.l10n.shAppearsIn, ai: world.hasAiTags(person.id)),
        PresenceBar(
          world: world,
          person: person.id,
          height: 10,
          onTapSection: (o) =>
              hub != null ? hub!('timeline', section: o) : context.push('/shahnameh?tab=timeline&section=$o'),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          children: [
            for (final a in world.ages)
              if (ages.contains(a.index))
                Text(ageName(context, a), style: TextStyle(color: ageTint(context, a.index), fontSize: 12)),
            Text(context.l10n.shSections(localDigits(present.length)), style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

/// Kin first (parents, spouses, siblings, children, ancestors), then the other ties by family.
class _Ties extends ConsumerWidget {
  const _Ties({required this.world, required this.person, required this.onOpen});

  final ShWorld world;
  final ShPerson person;
  final ValueChanged<int> onOpen;

  static const _kinOrder = ['R:0>', 'R:2', 'R:1', 'R:0<', 'R:3>', 'R:3<'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final live = ref.watch(personRelationsProvider(person.id));
    final seen = <String>{};
    final kin = <ShEdge>[], ties = <ShEdge>[];
    for (final e in world.edgesOf(person.id)) {
      if (!seen.add('${e.other(person.id)}-${e.kind.key}-${e.a == person.id}')) continue;
      (e.kind.isKin ? kin : ties).add(e);
    }
    String order(ShEdge e) => e.kind.directional ? '${e.kind.key}${e.b == person.id ? '>' : '<'}' : e.kind.key;
    kin.sort((a, b) => _kinOrder.indexOf(order(a)).compareTo(_kinOrder.indexOf(order(b))));
    ties.sort((a, b) => a.kind.family.index.compareTo(b.kind.family.index));
    final failed = live.hasError && !live.isLoading;
    // One key per row: `kin-<other>` / `tie-<other>-<kind>`, made unique when the data holds
    // two ties of a kind with the same person (e.g. a parent edge and an ancestor edge).
    final keys = <String>{};
    Key keyOf(ShEdge e, String prefix) {
      final other = e.other(person.id);
      final base = prefix == 'kin' ? 'kin-$other' : 'tie-$other-${e.kind.key}';
      return ValueKey(keys.add(base) ? base : '$base-${e.kind.key}-${e.a == person.id ? 'of' : 'by'}');
    }

    Widget rows(List<ShEdge> edges, String prefix) => Column(
      children: [
        for (final e in edges)
          _TieRow(
            key: keyOf(e, prefix),
            world: world,
            subject: person.id,
            edge: e,
            live: live.value?.find(e.other(person.id), e.kind.key.substring(0, 1), int.parse(e.kind.key.substring(2))),
            onOpen: onOpen,
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kin.isNotEmpty) ...[_SectionTitle(l.shRelatives), rows(kin, 'kin')],
        if (ties.isNotEmpty) ...[_SectionTitle(l.shTies), rows(ties, 'tie')],
        if (kin.isEmpty && ties.isEmpty) ...[
          _SectionTitle(l.shRelatives),
          Text(l.shNoTies, style: TextStyle(color: context.ganj.muted)),
        ],
        if (failed && (kin.isNotEmpty || ties.isNotEmpty))
          _InlineRetry(onRetry: () => ref.invalidate(personRelationsProvider(person.id))),
      ],
    );
  }
}

class _TieRow extends StatefulWidget {
  const _TieRow({
    super.key,
    required this.world,
    required this.subject,
    required this.edge,
    required this.onOpen,
    this.live,
  });

  final ShWorld world;
  final int subject;
  final ShEdge edge;
  final RelationRow? live;
  final ValueChanged<int> onOpen;

  @override
  State<_TieRow> createState() => _TieRowState();
}

class _TieRowState extends State<_TieRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    final e = widget.edge;
    final other = e.other(widget.subject);
    final otherPerson = widget.world.people[other];
    // "a is [kind] of b": seen from a, the role reads «قاتلِ b»; seen from b, a is «قاتل».
    final ofSide = e.a == widget.subject;
    final noun = kinNoun(e.kind, ofSide: ofSide, gender: otherPerson?.gender ?? 0);
    final label = isEn(context) ? noun.en : noun.fa;
    final live = widget.live;
    final count = live?.evidenceCount ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: familyColor(context, e.kind.family), shape: BoxShape.circle),
              ),
              Text(label, style: TextStyle(color: c.muted)),
              InkWell(
                onTap: () => widget.onOpen(other),
                child: Text(
                  personName(context, widget.world, other),
                  style: TextStyle(
                    color: c.lapis,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: c.goldLight,
                  ),
                ),
              ),
              if (e.degree case final d? when d > 1)
                Text('(${l.shGenerations(localDigits(d))})', style: TextStyle(color: c.muted, fontSize: 12)),
              if (live?.note case final n? when n.isNotEmpty && !e.kind.isKin)
                Text('— $n', style: TextStyle(color: c.muted, fontSize: 12)),
              if (count > 0)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  label: Text(l.shEvidence(localDigits(count)), style: const TextStyle(fontSize: 12)),
                  avatar: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16),
                  onPressed: () => setState(() => _open = !_open),
                ),
            ],
          ),
          if (_open && live != null)
            for (final ev in live.evidence)
              InkWell(
                onTap: () => context.push('/poem/${ev.poemId}?c=${ev.coupletIndex}'),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsetsDirectional.only(start: 14, top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.poem, borderRadius: BorderRadius.circular(10)),
                  child: Text(ev.text, style: TextStyle(color: c.ink, height: 1.8)),
                ),
              ),
        ],
      ),
    );
  }
}

/// Ways onwards: the family tree (when there is kin) and the network.
class _Actions extends StatelessWidget {
  const _Actions({required this.world, required this.person, this.hub});

  final HubLink? hub;

  final ShWorld world;
  final ShPerson person;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final hasKin = world.edgesOf(person.id).any((e) => e.kind.isKin);
    if (world.edgesOf(person.id).isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (hasKin)
            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(l.shFamilyTree),
              onPressed: () => context.push('/shahnameh/tree/${person.id}'),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.hub_outlined),
            label: Text(l.shShowNetwork),
            onPressed: () => hub != null
                ? hub!('people', focus: person.id)
                : context.push('/shahnameh?tab=people&focus=${person.id}'),
          ),
        ],
      ),
    );
  }
}

/// Curated places of the stories this person takes part in.
class _Places extends StatelessWidget {
  const _Places({required this.world, required this.person, this.hub});

  final HubLink? hub;

  final ShWorld world;
  final ShPerson person;

  @override
  Widget build(BuildContext context) {
    final ids = <String>{
      for (final s in world.stories)
        if (s.people.contains(person.id)) ...s.places,
    };
    final places = [for (final id in ids) ?world.placeById(id)];
    if (places.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(context.l10n.shPlaces),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in places)
              ActionChip(
                avatar: const Icon(Icons.place_outlined, size: 18),
                label: Text(placeName(context, p)),
                onPressed: () =>
                    hub != null ? hub!('map', place: p.id) : context.push('/shahnameh?tab=map&place=${p.id}'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TaggedPoems extends ConsumerStatefulWidget {
  const _TaggedPoems({required this.person});

  final int person;

  @override
  ConsumerState<_TaggedPoems> createState() => _TaggedPoemsState();
}

class _TaggedPoemsState extends ConsumerState<_TaggedPoems> {
  static const _page = 12;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    final poems = ref.watch(personPoemsProvider(widget.person));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.shTaggedPoems, ai: poems.value?.any((t) => t.ai) ?? false),
        poems.when(
          loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          error: (_, _) => _InlineRetry(onRetry: () => ref.invalidate(personPoemsProvider(widget.person))),
          data: (list) => list.isEmpty
              ? Text(l.nothingHere, style: TextStyle(color: c.muted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final t in list.take(_shown))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(t.title, style: TextStyle(color: c.lapis)),
                        subtitle: t.coupletText == null
                            ? null
                            : Text(
                                t.coupletText!,
                                style: TextStyle(color: t.mention == 0 ? c.ink : c.muted, height: 1.7),
                              ),
                        onTap: () => context.push('/poem/${t.poemId}?c=${t.coupletIndex}'),
                      ),
                    if (list.length > _shown)
                      TextButton(onPressed: () => setState(() => _shown += _page), child: Text(l.more)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// «گزارش خطا»: an email to Ganj about this person.
class _Report extends ConsumerWidget {
  const _Report({required this.person});

  final ShPerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        icon: const Icon(Icons.flag_outlined),
        label: Text(context.l10n.shReport),
        onPressed: () => reportProblem(
          context,
          ref,
          what: '${person.name}${person.en == null ? '' : ' (${person.en})'} #${person.id}',
          path: '/shahnameh/person/${person.id}',
        ),
      ),
    ),
  );
}

/// A live part that couldn't load; the bundled parts around it stay.
class _InlineRetry extends StatelessWidget {
  const _InlineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.cloud_off, size: 18, color: context.ganj.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(context.l10n.shCouldNotLoad, style: TextStyle(color: context.ganj.muted)),
      ),
      TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
    ],
  );
}
