import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/disk_image.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/extras.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../widgets/external_link.dart';
import '../../widgets/gold_card.dart';

/// A poet's «منابع کاغذی» (cached a month).
final paperSourcesProvider = FutureProvider.autoDispose.family<List<PaperSource>, int>(
  (ref, rootCatId) => ref.watch(ganjoorApiProvider).paperSources(rootCatId),
  retry: noAutoRetry,
);

/// On a poet's page: the edition Ganjoor's text follows, and (opened) every manuscript and
/// printed edition Ganjoor lists. Nothing when Ganjoor lists none.
class PaperSourcesPanel extends ConsumerWidget {
  const PaperSourcesPanel({super.key, required this.rootCatId});

  final int rootCatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(paperSourcesProvider(rootCatId)).value ?? const <PaperSource>[];
    if (sources.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    final l = context.l10n;
    // The text's own source first, then manuscripts, then printed editions.
    int rank(PaperSource s) => s.textSource ? 0 : (s.manuscript ? 1 : 2);
    final ordered = [...sources]..sort((a, b) => rank(a).compareTo(rank(b)));
    final textSource = ordered.where((s) => s.textSource).firstOrNull;
    return GoldCard(
      key: const ValueKey('panel-sources'),
      color: c.inner,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.menu_book_outlined, color: c.gold),
        title: Text(l.paperSources),
        subtitle: textSource == null
            ? null
            : Text(
                '${l.textSource}: ${textSource.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
        children: [
          for (final s in ordered)
            ListTile(
              leading: SizedBox(
                width: 40,
                height: 56,
                child: s.thumb.isEmpty
                    ? Icon(s.manuscript ? Icons.auto_stories_outlined : Icons.book_outlined, color: c.muted)
                    : Image(
                        image: DiskImage(s.thumb),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.book_outlined, color: c.muted),
                      ),
              ),
              title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                s.textSource
                    ? '${s.manuscript ? l.manuscript : l.printedEdition} · ${l.textSource}'
                    : (s.manuscript ? l.manuscript : l.printedEdition),
                style: TextStyle(color: s.textSource ? c.gold : c.muted, fontSize: 12),
              ),
              trailing: Icon(Icons.open_in_new, color: c.muted, size: 18),
              onTap: () => openExternal(context, s.url),
            ),
        ],
      ),
    );
  }
}
