import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../data/models.dart';
import '../data/person_search.dart';
import 'sh_style.dart';

/// Search for a person and pick one (null when dismissed). [where] narrows who can be picked.
Future<int?> pickPerson(BuildContext context, ShWorld world, {bool Function(ShPerson)? where}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PersonPicker(world: world, where: where),
    );

class _PersonPicker extends StatefulWidget {
  const _PersonPicker({required this.world, this.where});

  final ShWorld world;
  final bool Function(ShPerson)? where;

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final w = widget.world;
    final found = searchPeople(w, _q).where(widget.where ?? (_) => true).take(40).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: context.l10n.shSearchPeople,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in found)
                    ListTile(
                      title: Text(personName(context, w, p.id)),
                      subtitle: w.firstSection(p.id) == null ? null : PresenceBar(world: w, person: p.id, height: 4),
                      onTap: () => Navigator.of(context).pop(p.id),
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
