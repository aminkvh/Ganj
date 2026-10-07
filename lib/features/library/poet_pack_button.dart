import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/content_en.dart';
import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../l10n/l10n.dart';
import 'library_providers.dart';

/// On a poet's page: download that poet's Ganjoor pack for offline reading and search (or
/// show that it is on the device / has an update). Hidden when the poet has no pack.
class PoetPackButton extends ConsumerStatefulWidget {
  const PoetPackButton({super.key, required this.poetId});

  final int poetId;

  @override
  ConsumerState<PoetPackButton> createState() => _PoetPackButtonState();
}

class _PoetPackButtonState extends ConsumerState<PoetPackButton> {
  double? _progress;

  Future<void> _install() async {
    final packs = ref.read(packCatalogProvider).value ?? const [];
    final p = packs.where((p) => p.poetId == widget.poetId).firstOrNull;
    if (p == null) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _progress = 0);
    try {
      await ref
          .read(packInstallerProvider)
          .install(
            p,
            onProgress: (v) {
              if (mounted) setState(() => _progress = v);
            },
          );
      messenger.showSnackBar(SnackBar(content: Text(l.packReady(localPoet(p.poetId, p.name)))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.packFailed(localPoet(p.poetId, p.name)))));
    } finally {
      if (mounted) {
        setState(() => _progress = null);
        ref.invalidate(installedPacksProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    final pack = (ref.watch(packCatalogProvider).value ?? const []).where((p) => p.poetId == widget.poetId).firstOrNull;
    if (pack == null) return const SizedBox.shrink();
    final installedDate = (ref.watch(installedPacksProvider).value ?? const {})[widget.poetId];
    final progress = _progress;
    if (progress != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            const SizedBox(height: 4),
            Text(localDigits('${(progress * 100).round()}٪'), style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ),
      );
    }
    if (installedDate != null && installedDate.compareTo(pack.pubDate) >= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.offline_pin, color: c.gold, size: 18),
            const SizedBox(width: 6),
            Text(l.onDevice, style: TextStyle(color: c.muted)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FilledButton.tonalIcon(
        key: const ValueKey('poet-pack-get'),
        onPressed: _install,
        icon: Icon(installedDate == null ? Icons.download_for_offline_outlined : Icons.update),
        label: Text(installedDate == null ? '${l.downloadForReading} · ${formatBytes(pack.size)}' : l.updateAvailable),
      ),
    );
  }
}
