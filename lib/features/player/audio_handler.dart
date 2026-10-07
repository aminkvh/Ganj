import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_backend.dart';

/// Bridges the just_audio player to the OS media session (lock screen, notification,
/// headset buttons) on Android/iOS/macOS. Skip buttons switch between recitations.
class GanjAudioHandler extends BaseAudioHandler with SeekHandler {
  GanjAudioHandler(this.backend) {
    final p = backend.player;
    p.playbackEventStream.listen((_) => playbackState.add(_state(p)), onError: _onError);
    p.playingStream.listen((_) => playbackState.add(_state(p)), onError: _onError);
    backend.onMedia = (info, duration) => mediaItem.add(
      MediaItem(id: info.id, title: info.title, artist: info.artist, artUri: info.artUri, duration: duration),
    );
  }

  final JustAudioBackend backend;

  /// The player controller shows the error in the app; the OS session just stops.
  void _onError(Object e, StackTrace _) => playbackState.add(
    playbackState.value.copyWith(processingState: AudioProcessingState.error, playing: false, errorMessage: '$e'),
  );
  Future<void> Function(int delta)? onSkip;

  PlaybackState _state(AudioPlayer p) => PlaybackState(
    controls: [
      MediaControl.skipToPrevious,
      if (p.playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ],
    systemActions: const {MediaAction.seek},
    androidCompactActionIndices: const [0, 1, 3],
    processingState: switch (p.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    },
    playing: p.playing,
    updatePosition: p.position,
    bufferedPosition: p.bufferedPosition,
    speed: p.speed,
  );

  @override
  Future<void> play() => backend.play();

  @override
  Future<void> pause() => backend.pause();

  @override
  Future<void> seek(Duration position) => backend.seek(position);

  @override
  Future<void> stop() async {
    await backend.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkip?.call(1);

  @override
  Future<void> skipToPrevious() async => onSkip?.call(-1);
}
