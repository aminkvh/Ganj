import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/gold_card.dart';
import '../../widgets/list_tiles.dart';
import '../../widgets/poet_portrait.dart';
import '../home/poet_tile.dart';
import '../../l10n/l10n.dart';
import '../../widgets/external_link.dart';
import '../../core/text/content_en.dart';
import '../../widgets/home_button.dart';
import '../library/poet_pack_button.dart';

class PoetScreen extends ConsumerWidget {
  const PoetScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(poetProvider(id));
    final c = context.ganj;
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value == null ? '' : localPoet(async.value!.poet.id, async.value!.poet.nickname)),
        actions: [
          const HomeButton(),
          if (async.value case final pc?) OpenOnGanjoorButton(fullUrl: pc.poet.fullUrl),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(poetProvider(id))),
        data: (pc) {
          final bio = pc.poet.description ?? pc.cat.description;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: GoldCard(
                  child: Column(
                    children: [
                      PoetPortrait(url: pc.poet.imageAbsoluteUrl, width: 100, height: 128),
                      const SizedBox(height: 8),
                      englishContent == null
                          ? Text(pc.poet.name, textAlign: TextAlign.center, style: nastaliqOf(context, 30))
                          : Text(
                              localPoetFull(pc.poet.id, pc.poet.name),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                      Text(poetYears(context.l10n, pc.poet), style: TextStyle(color: c.muted)),
                      PoetPackButton(poetId: pc.poet.id),
                      if (bio != null && bio.isNotEmpty) ...[const SizedBox(height: 12), ExpandableText(bio)],
                    ],
                  ),
                ),
              ),
              ...catContentSlivers(pc.cat),
            ],
          );
        },
      ),
    );
  }
}
