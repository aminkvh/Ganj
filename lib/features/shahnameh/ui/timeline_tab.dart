import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../data/models.dart';
import '../data/shahnameh_providers.dart';
import 'timeline_river.dart';
import 'timeline_vertical.dart';

/// «گاه‌شمار»: the story list (phones) or the river (wide screens), switchable either way.
class TimelineTab extends ConsumerStatefulWidget {
  const TimelineTab({super.key, required this.world, this.section});

  final ShWorld world;

  /// A story order to bring into view.
  final int? section;

  @override
  ConsumerState<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends ConsumerState<TimelineTab> {
  // A story chosen on the map before this tab was built (tabs are rebuilt as they're shown).
  late int? _section = widget.section ?? ref.read(shSelectionProvider).section;
  late bool? _river = _section != null ? false : null;

  @override
  void initState() {
    super.initState();
    // Consumed once, after the build (providers can't change while the tree builds).
    if (widget.section == null && _section != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shSelectionProvider.notifier).takeSection();
      });
    }
  }

  @override
  void didUpdateWidget(TimelineTab old) {
    super.didUpdateWidget(old);
    // Asked to show a section: the story list is where sections are brought into view.
    if (widget.section != null && widget.section != old.section) {
      _river = false;
      _section = widget.section;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // A story chosen on the map is brought into view in the story list.
    ref.listen(shSelectionProvider, (_, sel) {
      if (sel.section == null) return;
      final s = ref.read(shSelectionProvider.notifier).takeSection();
      setState(() {
        _river = false;
        _section = s;
      });
    });
    final river = _river ?? (_section == null && MediaQuery.sizeOf(context).width >= 900);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, icon: const Icon(Icons.view_agenda_outlined), label: Text(l.shStories)),
              ButtonSegment(value: true, icon: const Icon(Icons.waterfall_chart), label: Text(l.shRiver)),
            ],
            selected: {river},
            onSelectionChanged: (s) => setState(() => _river = s.single),
          ),
        ),
        Expanded(
          child: river ? TimelineRiver(world: widget.world) : TimelineVertical(world: widget.world, section: _section),
        ),
      ],
    );
  }
}
