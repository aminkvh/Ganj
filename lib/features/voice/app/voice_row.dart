import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../data/api/dto/poem.dart';
import '../../../data/providers.dart' show sharedPrefsProvider;
import '../../../l10n/l10n.dart';
import '../../library/library_providers.dart' show formatBytes;
import '../../player/player_controller.dart';
import '../../player/unavailable_audio.dart';
import 'voice_cache.dart';
import 'voice_downloader.dart';
import 'voice_manifest.dart' show kFastVariant, kQualityVariant;
import 'voice_providers.dart';

/// The platforms that offer machine reading. Android and Windows are tested; Linux and macOS are offered untested
/// (Amin, 2026-11-09). iOS cannot run it: sherpa-onnx's iOS build does not expose onnxruntime, which the
/// text-to-phoneme model needs.
const kVoicePlatforms = {TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS};

/// True when the «خوانش ماشینی» row is offered for [p]: a platform in [kVoicePlatforms], the voice's folders exist,
/// audio can play here, and the poem has at least one beyt to read.
bool voiceRowVisible(WidgetRef ref, Poem p) {
  if (!kVoicePlatforms.contains(defaultTargetPlatform)) return false;
  if (ref.watch(voiceCacheBaseProvider) == null) return false;
  if (ref.watch(audioUnavailableProvider) != null) return false;
  return voiceCanRead(p);
}

/// The machine-reading row of the «خوانش‌ها» panel: get the voice once, then read this poem on the device.
class VoiceRow extends ConsumerWidget {
  const VoiceRow({super.key, required this.poem});

  final Poem poem;

  /// Fetches the manifest (for the size), asks, and downloads on accept.
  Future<void> _consent(BuildContext context, WidgetRef ref) async {
    final ctrl = ref.read(voiceProvider.notifier);
    final m = await ctrl.manifest();
    if (m == null || !context.mounted) return;
    final l = context.l10n;
    // Fast is the default; a manifest with one variant offers no choice.
    final offered = [
      for (final v in [kFastVariant, kQualityVariant])
        if (m.variants.containsKey(v)) v,
    ];
    var chosen = offered.first;
    final muted = TextStyle(color: context.ganj.muted, fontSize: 12);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.voiceRowTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // With a choice, each option shows its own size.
              Text(offered.length > 1 ? l.voiceConsentBodyChoice : l.voiceConsentBody(formatBytes(m.sizeOf(chosen)))),
              if (offered.length > 1)
                RadioGroup<String>(
                  groupValue: chosen,
                  onChanged: (v) => setState(() => chosen = v ?? chosen),
                  child: Column(
                    children: [
                      for (final v in offered)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: v,
                          title: Text(
                            '${v == kFastVariant ? l.voiceFast : l.voiceQuality} · ${formatBytes(m.sizeOf(v))}',
                          ),
                          subtitle: Text(v == kFastVariant ? l.voiceFastNote : l.voiceQualityNote, style: muted),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.voiceGet)),
          ],
        ),
      ),
    );
    if (ok == true) await ctrl.download(m, variant: chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    final voice = ref.watch(voiceProvider);
    final prepare = ref.watch(voicePrepareProvider(poem.id));
    final st = ref.watch(playerProvider);
    final player = ref.read(playerProvider.notifier);
    final prep = ref.read(voicePrepareProvider(poem.id).notifier);

    final current = st.poem?.id == poem.id && st.recitation?.id == kVoiceRecitationId;
    final playing = current && st.playing;

    // A background upgrade was just swapped in ([kVoiceImprovedNoticePref]): said in the row's muted subtitle until
    // the next reading starts ([PrepareController.start] spends it).
    final improved = voice is VoiceReady && ref.read(sharedPrefsProvider).getString(kVoiceImprovedNoticePref) != null;

    void start() => prep.start(poem, playWhenDone: true, artist: l.voiceRowTitle);
    void consent() => _consent(context, ref);

    String subtitle;
    VoidCallback? onPlay;
    IconData? trailingIcon;
    VoidCallback? onTrailing;
    var busy = false; // a spinner in place of the trailing icon

    switch (voice) {
      case VoiceAbsent(:final wasCorrupt):
        subtitle = wasCorrupt ? l.voiceWasCorrupt : l.voiceGetOnce;
        onPlay = onTrailing = consent;
        trailingIcon = Icons.download;
      case VoiceChecking():
        subtitle = l.voiceChecking;
        busy = true;
      case VoiceDownloading(:final got, :final total):
        final pct = total <= 0 ? 0 : (got * 100 ~/ total).clamp(0, 100);
        subtitle = l.voiceDownloading(localDigits(pct));
        trailingIcon = Icons.close;
        onTrailing = ref.read(voiceProvider.notifier).cancel;
      case VoiceFailed(:final kind):
        subtitle = switch (kind) {
          VoiceDownloadFailure.noSpace => l.voiceFailedSpace,
          VoiceDownloadFailure.checksum => l.voiceFailedChecksum,
          _ => l.voiceFailedOffline,
        };
        onPlay = onTrailing = consent;
        trailingIcon = Icons.refresh;
      case VoiceReady():
        switch (prepare) {
          case Preparing(:final done, :final total) when current && player.streaming:
            // Already playing as a stream while the rest is read: a playing row (the count stays as quiet info).
            subtitle = l.voicePreparing(localDigits(done), localDigits(total));
            onPlay = player.toggle;
          case Preparing(:final done, :final total):
            subtitle = l.voicePreparing(localDigits(done), localDigits(total));
            trailingIcon = Icons.close;
            onPlay = onTrailing = prep.cancel; // spec: Preparing | … | pause/cancel
          case PrepareFailed():
            subtitle = l.voicePrepareFailed;
            onPlay = onTrailing = start;
            trailingIcon = Icons.refresh;
          case PrepareIdle() || Prepared():
            // The one-time «got better» line stands in for the plain subtitle only; progress and errors stay.
            subtitle = improved ? l.voiceImproved : l.voiceOnDevice;
            // In error the wav may have been evicted or cleared: start() checks the cache and prepares again.
            onPlay = () => !current || st.status == PlayerStatus.error ? start() : player.toggle();
        }
    }

    return ListTile(
      dense: true,
      leading: IconButton(
        key: const ValueKey('voice-play'),
        tooltip: playing ? l.pause : l.play,
        icon: Stack(
          alignment: Alignment.center,
          children: [
            Icon(playing ? Icons.pause_circle : Icons.play_circle, color: c.brandRed, size: 32),
            if (current && (st.status == PlayerStatus.loading || st.waiting))
              SizedBox.square(dimension: 36, child: CircularProgressIndicator(strokeWidth: 2, color: c.brandRed)),
          ],
        ),
        onPressed: onPlay,
      ),
      title: Text(l.voiceRowTitle, style: TextStyle(fontWeight: current ? FontWeight.w700 : FontWeight.w400)),
      subtitle: Text(subtitle, style: TextStyle(color: c.muted, fontSize: 12)),
      trailing: busy
          ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.muted))
          : trailingIcon == null
          ? null
          : IconButton(
              key: const ValueKey('voice-trailing'),
              icon: Icon(trailingIcon, color: c.muted),
              onPressed: onTrailing,
            ),
    );
  }
}
