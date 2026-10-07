import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/poem.dart';
import '../../data/api/dto/recitation.dart';
import '../../widgets/gold_card.dart';
import 'download_button.dart';
import 'player_controller.dart';
import '../../l10n/l10n.dart';

/// «خوانش‌ها» panel on the poem page: one row per reciter, play/pause, download, scroll lock.
class RecitationList extends ConsumerWidget {
  const RecitationList({super.key, required this.poem, required this.scrollLocked, required this.onToggleLock});

  final Poem poem;
  final bool scrollLocked;
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final st = ref.watch(playerProvider);
    final ctrl = ref.read(playerProvider.notifier);
    final mine = st.poem?.id == poem.id;

    Widget row(Recitation r) {
      final current = mine && st.recitation?.id == r.id;
      final playing = current && st.playing;
      return ListTile(
        dense: true,
        leading: IconButton(
          key: ValueKey('rec-play-${r.id}'),
          tooltip: playing ? context.l10n.pause : context.l10n.play,
          icon: Icon(playing ? Icons.pause_circle : Icons.play_circle, color: c.brandRed, size: 32),
          onPressed: () => !current
              ? ctrl.play(poem, r)
              : st.status == PlayerStatus.error
              ? ctrl.retry()
              : ctrl.toggle(),
        ),
        title: Text(r.artist, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w400)),
        subtitle: Text(
          [r.title, if (!r.inSync) context.l10n.notInSync].join(' — '),
          style: TextStyle(color: c.muted, fontSize: 12),
        ),
        trailing: DownloadButton(recitation: r),
      );
    }

    return GoldCard(
      color: c.inner,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.headphones, color: c.gold),
        title: Text(context.l10n.recitationsCount(localDigits(poem.recitations.length))),
        trailing: IconButton(
          tooltip: scrollLocked ? context.l10n.autoScrollOff : context.l10n.autoScrollOn,
          icon: Icon(scrollLocked ? Icons.lock : Icons.swap_vert, color: c.muted),
          onPressed: onToggleLock,
        ),
        children: [for (final r in poem.recitations) row(r)],
      ),
    );
  }
}
