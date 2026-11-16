import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../l10n/l10n.dart';
import '../player/audio_store.dart';
import 'book_audio.dart';
import 'library_providers.dart';

/// App-bar button on a book's page: download its recitations for listening offline. Shows the
/// download's progress while it runs.
class BookAudioButton extends ConsumerWidget {
  const BookAudioButton({super.key, required this.catId, required this.title});

  final int catId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(audioStoreProvider) == null) return const SizedBox.shrink();
    final job = ref.watch(bookAudioJobProvider);
    final c = context.ganj;
    return IconButton(
      key: const ValueKey('book-audio'),
      tooltip: context.l10n.bookAudio,
      icon: job?.catId == catId
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.gold,
                value: job!.total == 0 ? null : job.done / job.total,
              ),
            )
          : const Icon(Icons.download_for_offline_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: c.page,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (_, scroll) => BookAudioPanel(catId: catId, title: title, scroll: scroll),
        ),
      ),
    );
  }
}

/// The choices: the top recitation of each poem, every recitation, or one reciter's.
class BookAudioPanel extends ConsumerWidget {
  const BookAudioPanel({super.key, required this.catId, required this.title, this.scroll});

  final int catId;
  final String title;
  final ScrollController? scroll;

  Future<void> _start(BuildContext context, WidgetRef ref, BookAudioChoice choice) async {
    final l = context.l10n;
    final store = ref.read(audioStoreProvider);
    if (store == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(choice.artist ?? l.recitationsOf(title)),
        content: Text(l.recitationPlan(localDigits(choice.recitations.length), formatBytes(choice.totalBytes))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.download)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(bookAudioJobProvider.notifier).start(catId, title, choice, store);
    final msg = switch (result) {
      null => l.bookAudioBusy,
      BookAudioResult.done => l.recitationsDownloaded(title),
      BookAudioResult.stopped => l.downloadStopped,
      BookAudioResult.someFailed => l.bookAudioSomeFailed,
    };
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    final job = ref.watch(bookAudioJobProvider);

    Widget choiceTile(Key key, String name, BookAudioChoice ch) => ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text(
        l.bookAudioSummary(localDigits(ch.poems), formatBytes(ch.totalBytes)),
        style: TextStyle(color: c.muted, fontSize: 12),
      ),
      trailing: Icon(Icons.download_outlined, color: c.muted),
      enabled: job == null,
      onTap: () => _start(context, ref, ch),
    );

    final children = <Widget>[
      Text(
        l.recitationsOf(title),
        style: TextStyle(color: c.ink, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      if (job != null) ...[
        Text(l.jobProgress(job.label, localDigits(job.done), localDigits(job.total))),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total, color: c.gold),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const ValueKey('book-audio-stop'),
            onPressed: () => ref.read(bookAudioJobProvider.notifier).stop(),
            child: Text(l.stop),
          ),
        ),
      ] else
        ...switch (ref.watch(bookRecitationsProvider(catId))) {
          AsyncData(value: final all) when all.isEmpty => [Text(l.bookAudioNone, style: TextStyle(color: c.muted))],
          AsyncData(value: final all) => [
            choiceTile(const ValueKey('book-audio-top'), l.bookAudioTop, topOfEach(all)),
            choiceTile(const ValueKey('book-audio-all'), l.bookAudioAll, BookAudioChoice(all)),
            const SizedBox(height: 12),
            Text(
              l.bookAudioByReciter,
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
            ),
            for (final ch in byReciter(all)) choiceTile(ValueKey('book-audio-${ch.artist}'), ch.artist!, ch),
          ],
          AsyncError() => [
            Row(
              children: [
                Expanded(
                  child: Text(l.recitationsFailed, style: TextStyle(color: c.muted)),
                ),
                TextButton(onPressed: () => ref.invalidate(bookRecitationsProvider(catId)), child: Text(l.retry)),
              ],
            ),
          ],
          _ => [
            Text(l.listingRecitations(title), style: TextStyle(color: c.muted)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        },
    ];
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: children);
  }
}
