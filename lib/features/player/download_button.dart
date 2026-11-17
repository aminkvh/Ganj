import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/recitation.dart';
import 'audio_store.dart';
import '../../l10n/l10n.dart';

/// Offline download for one recitation: download → progress (tap: pause or cancel) → downloaded
/// (tap to delete). A paused download keeps what it fetched; tap to resume or throw it away.
class DownloadButton extends ConsumerStatefulWidget {
  const DownloadButton({super.key, required this.recitation});

  final Recitation recitation;

  @override
  ConsumerState<DownloadButton> createState() => _DownloadButtonState();
}

enum _Action { pause, resume, discard }

class _DownloadButtonState extends ConsumerState<DownloadButton> {
  double? _progress;
  CancelToken? _cancel;
  bool _discard = false;

  Future<void> _download(AudioStore store) async {
    final r = widget.recitation;
    final cancel = _cancel = CancelToken();
    _discard = false;
    setState(() => _progress = 0);
    try {
      await store.download(
        r,
        cancel: cancel,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
    } catch (_) {
      if (!cancel.isCancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.downloadFailed)));
      }
    } finally {
      // Discarded only once the download has let go of its file.
      if (_discard) await store.discardPartial(r.id);
      _cancel = null;
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _act(AudioStore store, _Action a) async {
    switch (a) {
      case _Action.pause:
        _cancel?.cancel('paused');
      case _Action.resume:
        await _download(store);
      case _Action.discard:
        if (_cancel != null) {
          _discard = true;
          _cancel!.cancel('discarded');
        } else {
          await store.discardPartial(widget.recitation.id);
          if (mounted) setState(() {});
        }
    }
  }

  Widget _menu(AudioStore store, {required bool running, required Widget child, required String tooltip}) {
    final l = context.l10n;
    return PopupMenuButton<_Action>(
      key: ValueKey('rec-dl-menu-${widget.recitation.id}'),
      tooltip: tooltip,
      onSelected: (a) => _act(store, a),
      itemBuilder: (_) => [
        if (running)
          PopupMenuItem(value: _Action.pause, child: Text(l.pauseDownload))
        else
          PopupMenuItem(value: _Action.resume, child: Text(l.resumeDownload)),
        PopupMenuItem(value: _Action.discard, child: Text(l.discardDownload)),
      ],
      child: SizedBox(width: 40, height: 40, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(audioStoreProvider);
    if (store == null) return const SizedBox.shrink();
    final c = context.ganj;
    final l = context.l10n;
    final r = widget.recitation;
    if (_progress case final p?) {
      return _menu(
        store,
        running: true,
        tooltip: l.pauseDownload,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2, value: p == 0 ? null : p, color: c.gold),
        ),
      );
    }
    final done = store.isDownloaded(r.id);
    final part = done ? 0 : store.partialBytes(r.id);
    if (part > 0) {
      // Paused: the ring shows how far it got, with a resume mark inside.
      return _menu(
        store,
        running: false,
        tooltip: l.resumeDownload,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: r.mp3Size > 0 ? (part / r.mp3Size).clamp(0.0, 1.0) : null,
                color: c.muted,
              ),
            ),
            Icon(Icons.play_arrow, size: 14, color: c.gold),
          ],
        ),
      );
    }
    return IconButton(
      key: ValueKey('rec-dl-${r.id}'),
      tooltip: done ? l.removeFromDevice : l.downloadForListening,
      icon: Icon(done ? Icons.download_done : Icons.download_outlined, color: done ? c.gold : c.muted),
      onPressed: () async {
        if (done) {
          await store.delete(r.id);
          if (mounted) setState(() {});
        } else {
          await _download(store);
        }
      },
    );
  }

  @override
  void dispose() {
    _cancel?.cancel('left'); // the part stays: the download is paused
    super.dispose();
  }
}
