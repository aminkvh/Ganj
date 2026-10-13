import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../data/models.dart';
import '../data/person_search.dart';
import '../data/shahnameh_providers.dart';
import 'network_view.dart';
import 'sh_style.dart';

/// «نامبردگان»: everyone named in the Shahnameh — the great figures first, then by the age
/// they first appear in, then those only Ganjoor's family trees know. Search covers names,
/// aliases and English names.
class PeopleTab extends ConsumerStatefulWidget {
  const PeopleTab({super.key, required this.world, this.onOpen, this.focus});

  final ShWorld world;

  /// Opens on the network, focused on this person.
  final int? focus;

  /// Opens a person (the person sheet).
  final ValueChanged<int>? onOpen;

  @override
  ConsumerState<PeopleTab> createState() => _PeopleTabState();
}

sealed class _Item {}

class _Header extends _Item {
  _Header(this.text, this.tint);
  final String text;
  final Color? tint;
}

class _Row extends _Item {
  _Row(this.person);
  final ShPerson person;
}

class _PeopleTabState extends ConsumerState<PeopleTab> {
  final _query = TextEditingController();
  List<_Item>? _sections;
  // A person chosen elsewhere in the hub before this tab was built.
  late final int? _asked = widget.focus ?? ref.read(shSelectionProvider).focus;
  late bool _network = _asked != null;
  late int _focus = _asked ?? _mostConnected();

  @override
  void initState() {
    super.initState();
    if (widget.focus == null && _asked != null) {
      // Consumed once, after the build (providers can't change while the tree builds).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shSelectionProvider.notifier).takeFocus();
      });
    }
  }

  int _mostConnected() {
    var best = w.people.keys.first;
    for (final id in w.people.keys) {
      if (w.edgesOf(id).length > w.edgesOf(best).length) best = id;
    }
    return best;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sections = null; // localized headers and tints: rebuilt for a new language or theme
  }

  @override
  void didUpdateWidget(PeopleTab old) {
    super.didUpdateWidget(old);
    if (widget.focus != null && widget.focus != old.focus) {
      _network = true;
      _focus = widget.focus!;
    }
  }

  ShWorld get w => widget.world;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  int _first(ShPerson p) => w.firstSection(p.id) ?? 1 << 20;

  List<_Item> _buildSections(BuildContext context) {
    final l = context.l10n;
    int byAppearance(ShPerson a, ShPerson b) {
      final f = _first(a).compareTo(_first(b));
      return f != 0 ? f : (w.presence[b.id]?.length ?? 0).compareTo(w.presence[a.id]?.length ?? 0);
    }

    final all = w.people.values.toList();
    final major = all.where((p) => p.importance >= 1).toList()
      ..sort((a, b) {
        final i = b.importance.compareTo(a.importance);
        return i != 0 ? i : byAppearance(a, b);
      });
    final rest = all.where((p) => p.importance < 1).toList()..sort(byAppearance);
    final items = <_Item>[_Header(l.shMajorFigures, null), for (final p in major) _Row(p)];
    for (final a in w.ages) {
      final inAge = [
        for (final p in rest)
          if (w.firstSection(p.id) case final f? when a.contains(f)) p,
      ];
      if (inAge.isEmpty) continue;
      items
        ..add(_Header(ageName(context, a), ageTint(context, a.index)))
        ..addAll([for (final p in inAge) _Row(p)]);
    }
    final unseen = [
      for (final p in rest)
        if (w.firstSection(p.id) == null) p,
    ];
    if (unseen.isNotEmpty) {
      items
        ..add(_Header(l.shOthers, null))
        ..addAll([for (final p in unseen) _Row(p)]);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    ref.listen(shSelectionProvider, (_, sel) {
      if (sel.focus == null) return;
      final f = ref.read(shSelectionProvider.notifier).takeFocus()!;
      setState(() {
        _network = true;
        _focus = f;
      });
    });
    final q = _query.text.trim();
    final items = q.isEmpty ? (_sections ??= _buildSections(context)) : [for (final p in searchPeople(w, q)) _Row(p)];
    final toggle = SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        ButtonSegment(value: false, icon: const Icon(Icons.list), label: Text(l.shList)),
        ButtonSegment(value: true, icon: const Icon(Icons.hub_outlined), label: Text(l.shNetwork)),
      ],
      selected: {_network},
      onSelectionChanged: (s) => setState(() => _network = s.single),
    );
    if (_network) {
      return Column(
        children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: toggle),
          Expanded(
            child: NetworkView(world: w, focus: _focus),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: toggle),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.shSearchPeople,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l.close,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_query.clear),
                    ),
              isDense: true,
              filled: true,
              fillColor: c.paper,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: c.borderGold),
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(l.shNoResults, style: TextStyle(color: c.muted)),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => switch (items[i]) {
                    _Header(:final text, :final tint) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                      child: Row(
                        children: [
                          if (tint != null) ...[
                            Container(
                              width: 4,
                              height: 22,
                              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(2)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(text, style: nastaliqOf(context, 20).copyWith(color: tint ?? c.brandRed)),
                        ],
                      ),
                    ),
                    _Row(:final person) => PersonRow(
                      world: w,
                      person: person,
                      onTap: widget.onOpen == null ? null : () => widget.onOpen!(person.id),
                    ),
                  },
                ),
        ),
      ],
    );
  }
}

/// A person in a list: name (English beside Persian in the English interface), one line
/// of description, and where they appear in the book.
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.world, required this.person, this.onTap});

  final ShWorld world;
  final ShPerson person;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final en = isEn(context) ? person.en : null;
    final first = world.firstSection(person.id);
    final tint = first == null ? c.muted : ageTint(context, world.ageOfSection(first).index);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: tint.withValues(alpha: 0.15),
              child: Text(
                person.name.characters.first,
                style: TextStyle(color: tint, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        en ?? person.name,
                        style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                      ),
                      if (en != null) Text(person.name, style: TextStyle(color: c.muted, fontSize: 13)),
                    ],
                  ),
                  if (person.description case final d? when d.isNotEmpty)
                    Text(
                      d,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  if (first != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: PresenceBar(world: world, person: person.id, height: 4),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
