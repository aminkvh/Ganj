import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_backend.dart';
import 'player_controller.dart';

/// What the OS session shows for [info]; a live (still growing) stream has no duration.
MediaItem mediaItemFor(MediaInfo info, Duration? duration) => MediaItem(
  id: info.id,
  title: info.title,
  artist: info.artist,
  artUri: info.artUri,
  duration: info.live ? null : duration,
);

/// The OS session's system actions; a live stream offers no seek.
Set<MediaAction> mediaSystemActions(MediaInfo? info) =>
    (info?.live ?? false) ? const <MediaAction>{} : const {MediaAction.seek};

/// Bridges the just_audio player to the OS media session (lock screen, notification,
/// headset buttons) on Android/iOS/macOS. Skip buttons switch between recitations.
class GanjAudioHandler extends BaseAudioHandler with SeekHandler {
  GanjAudioHandler(this.backend) {
    final p = backend.player;
    p.playbackEventStream.listen((_) => playbackState.add(_state(p)), onError: _onError);
    p.playingStream.listen((_) => playbackState.add(_state(p)), onError: _onError);
    backend.onMedia = (info, duration) => mediaItem.add(mediaItemFor(info, duration));
  }

  final JustAudioBackend backend;

  /// The player controller shows the error in the app; the OS session just stops.
  void _onError(Object e, StackTrace _) => playbackState.add(
    playbackState.value.copyWith(processingState: AudioProcessingState.error, playing: false, errorMessage: '$e'),
  );
  Future<void> Function(int delta)? onSkip;

  /// The listener's intent when it differs from the player (a voice stream waiting for its next
  /// beyt: the player is paused but the listener wants it playing); null to show the player.
  bool? Function()? intentPlaying;

  /// Re-publishes the session state, e.g. when [intentPlaying] changes.
  void refresh() => playbackState.add(_state(backend.player));

  PlaybackState _state(AudioPlayer p) {
    final playing = intentPlaying?.call() ?? p.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: mediaSystemActions(backend.current),
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (p.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: p.position,
      bufferedPosition: p.bufferedPosition,
      speed: p.speed,
    );
  }

  /// Play / pause / toggle / stop from the OS controls go through the player controller when set,
  /// so a voice stream waiting for its next beyt sees the listener's choice.
  Future<void> Function()? onPlay, onPause, onToggle, onStop;

  @override
  Future<void> play() => onPlay?.call() ?? backend.play();

  @override
  Future<void> pause() => onPause?.call() ?? backend.pause();

  /// The headset / media button: toggles by the controller's intent, not the player's state.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final toggle = onToggle;
    if (button == MediaButton.media && toggle != null) return toggle();
    return super.click(button);
  }

  @override
  Future<void> seek(Duration position) async {
    if (backend.current?.live ?? false) return; // the voice stream is still growing
    await backend.seek(position);
  }

  @override
  Future<void> stop() async {
    await (onStop?.call() ?? backend.stop());
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkip?.call(1);

  @override
  Future<void> skipToPrevious() async => onSkip?.call(-1);
}

/// Connects the OS controls of [h] to the player in [c]: skip, play, pause, the media button and
/// stop go through the controller; while a voice stream waits, the OS shows the listener's intent.
void wireAudioHandler(GanjAudioHandler h, ProviderContainer c) {
  PlayerController ctrl() => c.read(playerProvider.notifier);
  h
    ..onSkip = ((delta) => delta > 0 ? ctrl().next() : ctrl().previous())
    ..onPlay = (() => ctrl().resume())
    ..onPause = (() => ctrl().pause())
    ..onToggle = (() => ctrl().toggle())
    // A voice stream must end in the controller (its later beyts are dropped); a plain recitation
    // stops in the player only and stays in the mini player, as before.
    ..onStop = (() => ctrl().streaming ? ctrl().stop() : c.read(audioBackendProvider).stop())
    ..intentPlaying = () {
      final s = c.read(playerProvider);
      return s.waiting ? s.playing : null;
    };
  c.listen(playerProvider.select((s) => (s.waiting, s.playing)), (_, _) => h.refresh());
}
