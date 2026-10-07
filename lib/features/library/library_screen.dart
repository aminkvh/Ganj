import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/packs/pack_catalog.dart';
import '../../data/packs/pack_importer.dart';
import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../player/audio_store.dart';
import '../player/player_controller.dart';
import 'library_providers.dart';
import 'poet_audio.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

/// Offline library: per-poet packs (install / update / remove) and downloaded recitations.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _busy = <int, double>{}; // poetId → progress
  String _filter = '';
  String? _audioJob; // status line of a whole-poet audio download
  CancelToken? _audioCancel;

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _install(PackInfo p) async {
    final l = context.l10n;
    setState(() => _busy[p.poetId] = 0);
    try {
      await ref
          .read(packInstallerProvider)
          .install(
            p,
            onProgress: (v) {
              if (mounted) setState(() => _busy[p.poetId] = v);
            },
          );
      _snack(l.packReady(p.name));
    } catch (_) {
      _snack(l.packFailed(p.name));
    } finally {
      if (mounted) setState(() => _busy.remove(p.poetId));
      ref.invalidate(installedPacksProvider);
    }
  }

  Future<void> _remove(PackInfo p) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.packRemoveTitle(p.name)),
        content: Text(l.packRemoveBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy[p.poetId] = 0);
    try {
      await uninstall(ref.read(appDbProvider), p.poetId);
    } catch (_) {
      _snack(l.packRemoveFailed(p.name));
    } finally {
      if (mounted) setState(() => _busy.remove(p.poetId));
      ref.invalidate(installedPacksProvider);
    }
  }

  Future<void> _downloadPoetAudio(PackInfo p) async {
    final l = context.l10n;
    final store = ref.read(audioStoreProvider);
    if (store == null) return;
    setState(() => _audioJob = l.listingRecitations(p.name));
    try {
      final plan = await planPoetAudio(ref.read(ganjoorApiProvider), p.catId);
      if (!mounted) return;
      setState(() => _audioJob = null);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.recitationsOf(p.name)),
          content: Text(l.recitationPlan(localDigits(plan.recitations.length), formatBytes(plan.totalBytes))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.download)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final cancel = _audioCancel = CancelToken();
      await downloadPlan(
        plan,
        store,
        cancel: cancel,
        onItem: (done, total) {
          if (mounted) setState(() => _audioJob = l.jobProgress(p.name, localDigits(done), localDigits(total)));
        },
      );
      _snack(cancel.isCancelled ? l.downloadStopped : l.recitationsDownloaded(p.name));
    } catch (_) {
      _snack(l.recitationsFailed);
    } finally {
      if (mounted) setState(() => _audioJob = null);
      _audioCancel = null;
      ref.invalidate(downloadedAudioProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.offlineLibrary),
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.poetsTab),
              Tab(text: context.l10n.recitationsTab),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_audioJob != null)
              MaterialBanner(
                content: Text(_audioJob!),
                actions: [TextButton(onPressed: () => _audioCancel?.cancel(), child: Text(context.l10n.stop))],
              ),
            Expanded(child: TabBarView(children: [_packs(), _audio()])),
          ],
        ),
      ),
    );
  }

  Widget _packs() {
    final c = context.ganj;
    final catalog = ref.watch(packCatalogProvider);
    final installed = ref.watch(installedPacksProvider).value ?? const <int, String>{};
    return catalog.when(
      skipLoadingOnRefresh: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(packCatalogProvider)),
      data: (packs) {
        final shown =
            [
              for (final p in packs)
                if (_filter.isEmpty || matchesQuery(p.name, _filter)) p,
            ]..sort((a, b) {
              final ia = installed.containsKey(a.poetId), ib = installed.containsKey(b.poetId);
              return ia == ib ? a.name.compareTo(b.name) : (ia ? -1 : 1);
            });
        final total = ref.watch(installedPacksBytesProvider).value ?? 0;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                decoration: InputDecoration(
                  hintText: context.l10n.searchPoet,
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            if (installed.isNotEmpty)
              Text(
                context.l10n.installedSummary(localDigits(installed.length), formatBytes(total)),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => _packTile(shown[i], installed[shown[i].poetId]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _packTile(PackInfo p, String? installedDate) {
    final c = context.ganj;
    final busy = _busy[p.poetId];
    final installed = installedDate != null;
    final update = installed && p.pubDate.compareTo(installedDate) > 0;
    return ListTile(
      key: ValueKey('pack-${p.poetId}'),
      leading: Icon(installed ? Icons.offline_pin : Icons.cloud_outlined, color: installed ? c.gold : c.muted),
      title: Text(localPoet(p.poetId, p.name)),
      subtitle: Text(
        [
          formatBytes(p.size),
          if (installed) context.l10n.onDevice,
          if (update) context.l10n.updateAvailable,
        ].join(' · '),
        style: TextStyle(color: c.muted, fontSize: 12),
      ),
      onTap: installed ? () => context.push('/poet/${p.poetId}') : null,
      trailing: busy != null
          ? SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2, value: busy == 0 ? null : busy),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (update)
                  IconButton(
                    tooltip: context.l10n.update,
                    icon: const Icon(Icons.update),
                    onPressed: () => _install(p),
                  ),
                if (installed) ...[
                  IconButton(
                    key: ValueKey('pack-audio-${p.poetId}'),
                    tooltip: context.l10n.downloadAllRecitations,
                    icon: const Icon(Icons.headphones_outlined),
                    onPressed: _audioJob == null ? () => _downloadPoetAudio(p) : null,
                  ),
                  IconButton(
                    key: ValueKey('pack-del-${p.poetId}'),
                    tooltip: context.l10n.removeFromDevice,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(p),
                  ),
                ] else
                  IconButton(
                    key: ValueKey('pack-get-${p.poetId}'),
                    tooltip: context.l10n.downloadForReading,
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _install(p),
                  ),
              ],
            ),
    );
  }

  Widget _audio() {
    final c = context.ganj;
    final store = ref.watch(audioStoreProvider);
    return ref
        .watch(downloadedAudioProvider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(downloadedAudioProvider)),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(context.l10n.noRecitationsYet, textAlign: TextAlign.center),
                ),
              );
            }
            final total = list.fold<int>(0, (s, r) => s + r.bytes);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    context.l10n.recitationsSummary(localDigits(list.length), formatBytes(total)),
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final r = list[i];
                      return ListTile(
                        leading: Icon(Icons.headphones, color: c.gold),
                        title: Text(r.artist),
                        subtitle: Text('${r.title} · ${formatBytes(r.bytes)}', style: TextStyle(color: c.muted)),
                        onTap: r.poemId == 0 ? null : () => context.push('/poem/${r.poemId}'),
                        trailing: IconButton(
                          key: ValueKey('audio-del-${r.id}'),
                          tooltip: context.l10n.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            // A file that is playing is locked on Windows: stop it first.
                            if (ref.read(playerProvider).recitation?.id == r.id) {
                              await ref.read(playerProvider.notifier).stop();
                            }
                            await store?.delete(r.id);
                            ref.invalidate(downloadedAudioProvider);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
  }
}
