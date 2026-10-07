import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import 'player_controller.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';
import 'unavailable_audio.dart';
import '../../widgets/external_link.dart';

const _speeds = [0.75, 1.0, 1.25, 1.5];

String speedLabel(double s) => '×${localDecimal(s == s.roundToDouble() ? s.toInt() : s)}';

/// Persistent player bar shown under every screen while a recitation is loaded.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(playerProvider);
    final poem = s.poem, rec = s.recitation;
    if (s.status == PlayerStatus.idle || poem == null || rec == null) return const SizedBox.shrink();
    final c = context.ganj;
    final ctrl = ref.read(playerProvider.notifier);
    final total = s.duration.inMilliseconds;
    final progress = total <= 0 ? 0.0 : (s.position.inMilliseconds / total).clamp(0.0, 1.0);

    final Widget lead = switch (s.status) {
      PlayerStatus.loading => const SizedBox(
        width: 48,
        height: 48,
        child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      PlayerStatus.error => Icon(Icons.error_outline, color: c.brandRed),
      _ => IconButton(
        tooltip: s.playing ? context.l10n.pause : context.l10n.play,
        icon: Icon(s.playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: c.brandRed, size: 36),
        onPressed: ctrl.toggle,
      ),
    };

    return Material(
      key: const ValueKey('mini-player'),
      color: c.paper,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (s.status == PlayerStatus.ready)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: c.gold,
                  inactiveTrackColor: c.goldLight,
                  thumbColor: c.gold,
                ),
                child: Slider(
                  value: progress,
                  onChanged: total <= 0 ? null : (v) => ctrl.seek(Duration(milliseconds: (v * total).round())),
                ),
              )
            else
              Divider(height: 2, thickness: 2, color: c.goldLight),
            Row(
              children: [
                const SizedBox(width: 4),
                lead,
                Expanded(
                  child: InkWell(
                    onTap: () => GoRouter.maybeOf(context)?.push('/poem/${poem.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: s.status == PlayerStatus.error && ref.watch(audioUnavailableProvider) != null
                          ? Row(
                              children: [
                                if (ref.watch(audioUnavailableProvider) == AudioUnavailableReason.windowsN) ...[
                                  Expanded(child: Text(context.l10n.audioNeedsMediaPack)),
                                  TextButton(
                                    onPressed: () => openExternal(context, kMediaFeaturePackUrl),
                                    child: Text(context.l10n.howToInstall),
                                  ),
                                ] else
                                  Expanded(child: SelectableText(context.l10n.audioNeedsMpv)),
                              ],
                            )
                          : s.status == PlayerStatus.error
                          ? Row(
                              children: [
                                Expanded(child: Text(context.l10n.playFailed)),
                                TextButton(onPressed: ctrl.retry, child: Text(context.l10n.retry)),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(localTitle(poem.title), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  rec.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.muted, fontSize: 12),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: context.l10n.speed,
                  initialValue: s.speed,
                  onSelected: ctrl.setSpeed,
                  itemBuilder: (_) => [for (final v in _speeds) PopupMenuItem(value: v, child: Text(speedLabel(v)))],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(speedLabel(s.speed), style: TextStyle(color: c.muted)),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  icon: Icon(Icons.close, color: c.muted),
                  onPressed: ctrl.stop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
