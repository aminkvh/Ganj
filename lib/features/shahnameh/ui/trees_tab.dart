import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/gold_card.dart';
import '../data/models.dart';
import '../data/person_search.dart';
import 'sh_style.dart';

/// Ganjoor's captioned family trees, and anyone else's tree by search.
class TreesTab extends StatefulWidget {
  const TreesTab({super.key, required this.world});

  final ShWorld world;

  @override
  State<TreesTab> createState() => _TreesTabState();
}

class _TreesTabState extends State<TreesTab> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _hasKin(int id) => widget.world.edgesOf(id).any((e) => e.kind.isKin);

  @override
  Widget build(BuildContext context) {
    final w = widget.world;
    final c = context.ganj;
    final l = context.l10n;
    final q = _query.text.trim();
    final found = q.isEmpty ? const <ShPerson>[] : searchPeople(w, q).where((p) => _hasKin(p.id)).take(30).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final id in w.treeRoots)
          if (w.people[id] case final p?)
            GoldCard(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(Icons.account_tree_outlined, color: c.gold),
                  title: Text(
                    p.tree ?? p.name,
                    style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(personName(context, w, id), style: TextStyle(color: c.muted)),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left : Icons.chevron_right,
                  ),
                  onTap: () => context.push('/shahnameh/tree/$id'),
                ),
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(l.shAnyPersonTree, style: nastaliqOf(context, 20).copyWith(color: c.lapis)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.shSearchPeople,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: c.paper,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        if (q.isNotEmpty && found.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(l.shNoResults, style: TextStyle(color: c.muted)),
            ),
          ),
        for (final p in found)
          ListTile(
            title: Text(personName(context, w, p.id)),
            subtitle: p.description == null ? null : Text(p.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => context.push('/shahnameh/tree/${p.id}'),
          ),
        const ShCredit(),
      ],
    );
  }
}
