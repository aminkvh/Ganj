import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../widgets/error_retry.dart';
import '../../../widgets/home_button.dart';
import '../data/models.dart';
import '../data/shahnameh_providers.dart';
import 'people_tab.dart';
import 'person_sheet.dart';
import 'timeline_tab.dart';
import 'map_tab.dart';
import 'trees_tab.dart';

/// The hub's parts, in tab order; also the `?tab=` values.
const kShTabs = ['timeline', 'map', 'people', 'trees'];

/// «جهان شاهنامه»: the Shahnameh's timeline, map, people and family trees.
class ShahnamehHubScreen extends ConsumerWidget {
  const ShahnamehHubScreen({super.key, this.tab, this.focus, this.section, this.place, this.story});

  final String? tab;

  /// A story order for the timeline to bring into view.
  final int? section;

  /// A place to open / a story to show on the map.
  final String? place, story;

  /// A person to focus the people network on.
  final int? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.ganj;
    final world = ref.watch(shahnamehWorldProvider);
    // Keeps the cross-tab selection alive while the hub is open (tabs come and go).
    ref.listen(shSelectionProvider, (_, _) {});
    return DefaultTabController(
      length: kShTabs.length,
      initialIndex: kShTabs.indexOf(tab ?? '').clamp(0, kShTabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.shahnamehWorld, style: nastaliqOf(context, 24).copyWith(color: c.brandRed)),
          actions: const [HomeButton()],
          bottom: TabBar(
            isScrollable: MediaQuery.sizeOf(context).width < 420,
            tabAlignment: MediaQuery.sizeOf(context).width < 420 ? TabAlignment.center : null,
            tabs: [
              Tab(icon: const Icon(Icons.timeline), text: l.shTimeline),
              Tab(icon: const Icon(Icons.map_outlined), text: l.shMap),
              Tab(icon: const Icon(Icons.groups_outlined), text: l.shPeople),
              Tab(icon: const Icon(Icons.account_tree_outlined), text: l.shTrees),
            ],
          ),
        ),
        body: world.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(shahnamehWorldProvider)),
          data: (w) => TabBarView(
            physics: const NeverScrollableScrollPhysics(), // the map and the river pan sideways
            children: [for (final t in kShTabs) _tab(t, w)],
          ),
        ),
      ),
    );
  }

  Widget _tab(String tab, ShWorld w) => switch (tab) {
    'timeline' => TimelineTab(world: w, section: section),
    'map' => ShahnamehMapTab(world: w, place: place, story: story),
    'trees' => TreesTab(world: w),
    'people' => Builder(
      builder: (context) => PeopleTab(world: w, focus: focus, onOpen: (id) => openPerson(context, id)),
    ),
    _ => const SizedBox.expand(),
  };
}
