import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/recitation.dart';
import 'audio_store.dart';
import '../../l10n/l10n.dart';

/// Offline download toggle for one recitation: download → progress → downloaded (tap to delete).
class DownloadButton extends ConsumerStatefulWidget {
  const DownloadButton({super.key, required this.recitation});

  final Recitation recitation;

  @override
  ConsumerState<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<DownloadButton> {
  double? _progress;

  Future<void> _toggle(AudioStore store) async {
    final r = widget.recitation;
    if (store.isDownloaded(r.id)) {
      await store.delete(r.id);
      if (mounted) setState(() {});
      return;
    }
    setState(() => _progress = 0);
    try {
      await store.download(
        r,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.downloadFailed)));
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(audioStoreProvider);
    if (store == null) return const SizedBox.shrink();
    final c = context.ganj;
    if (_progress != null) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2, value: _progress == 0 ? null : _progress, color: c.gold),
        ),
      );
    }
    final done = store.isDownloaded(widget.recitation.id);
    return IconButton(
      key: ValueKey('rec-dl-${widget.recitation.id}'),
      tooltip: done ? context.l10n.removeFromDevice : context.l10n.downloadForListening,
      icon: Icon(done ? Icons.download_done : Icons.download_outlined, color: done ? c.gold : c.muted),
      onPressed: () => _toggle(store),
    );
  }
}
