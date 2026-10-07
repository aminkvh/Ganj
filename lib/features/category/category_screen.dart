import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/gold_card.dart';
import '../../widgets/list_tiles.dart';
import '../../widgets/external_link.dart';
import '../../core/text/content_en.dart';
import '../../widgets/home_button.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(localTitle(async.value?.cat.title ?? '')),
        actions: [
          const HomeButton(),
          if (async.value case final pc?) OpenOnGanjoorButton(fullUrl: pc.cat.fullUrl),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(catProvider(id))),
        data: (pc) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Breadcrumb(crumbsFor(pc, includeSelf: false)),
              ),
            ),
            if (pc.cat.description?.isNotEmpty ?? false)
              SliverToBoxAdapter(child: GoldCard(child: ExpandableText(pc.cat.description!))),
            ...catContentSlivers(pc.cat),
          ],
        ),
      ),
    );
  }
}
