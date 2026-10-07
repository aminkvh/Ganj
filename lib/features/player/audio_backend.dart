import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// What the OS media controls show for the current track.
class MediaInfo {
  const MediaInfo({required this.id, required this.title, required this.artist, this.artUri});

  final String id;
  final String title;
  final String artist;
  final Uri? artUri;
}

/// Playback seam: the app talks to this, tests use a fake.
abstract class AudioBackend {
  Future<Duration?> load(Uri uri, {required MediaInfo info});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> stop();
  Future<void> setSpeed(double s);
  Stream<Duration> get position;
  Stream<bool> get playing;
  Stream<bool> get completed;

  /// Some platforms (Windows) learn the duration only after loading.
  Stream<Duration?> get duration;

  /// Errors that happen after loading (dropped stream, decoder failure…).
  Stream<Object> get errors;
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  JustAudioBackend([AudioPlayer? player]) : player = player ?? AudioPlayer();

  final AudioPlayer player;
  MediaInfo? current;

  /// Set by the OS media-session handler to publish now-playing info.
  void Function(MediaInfo info, Duration? duration)? onMedia;

  @override
  Future<Duration?> load(Uri uri, {required MediaInfo info}) async {
    current = info;
    final d = await player.setAudioSource(AudioSource.uri(uri));
    onMedia?.call(info, d);
    return d;
  }

  // just_audio's play() completes only when playback stops, so don't await it.
  @override
  Future<void> play() async => unawaited(player.play());

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration d) => player.seek(d);

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setSpeed(double s) => player.setSpeed(s);

  @override
  Stream<Duration> get position => player.positionStream;

  @override
  Stream<bool> get playing => player.playingStream;

  @override
  Stream<bool> get completed => player.processingStateStream.map((s) => s == ProcessingState.completed);

  @override
  Stream<Duration?> get duration => player.durationStream;

  @override
  Stream<Object> get errors => player.errorStream;

  @override
  Future<void> dispose() => player.dispose();
}
