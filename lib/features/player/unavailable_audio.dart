import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_backend.dart';

/// Why recitations can't play on this computer.
enum AudioUnavailableReason {
  /// Windows "N" editions ship without Media Foundation until Microsoft's free Media Feature
  /// Pack is installed.
  windowsN,

  /// Linux plays through libmpv, which isn't installed.
  linuxNoMpv,
}

/// Recitations can't play on this computer (see [AudioUnavailableReason]).
class AudioUnavailable implements Exception {
  const AudioUnavailable();

  @override
  String toString() => 'audio is not available on this computer';
}

/// True when Windows' media components are present (always true off Windows).
bool mediaFoundationAvailable({String? systemRoot, bool Function(String path)? exists}) {
  final root = systemRoot ?? Platform.environment['SystemRoot'] ?? r'C:\Windows';
  return (exists ?? (p) => File(p).existsSync())('$root\\System32\\mfplat.dll');
}

const _libmpvDirs = [
  '/usr/lib/x86_64-linux-gnu',
  '/usr/lib/aarch64-linux-gnu',
  '/lib/x86_64-linux-gnu',
  '/usr/lib64',
  '/usr/lib',
  '/usr/local/lib',
];
const _libmpvNames = ['libmpv.so.2', 'libmpv.so.1', 'libmpv.so'];

/// True when libmpv (Linux audio) is installed in one of the usual library folders.
bool libmpvAvailable({bool Function(String path)? exists}) {
  final e = exists ?? (p) => File(p).existsSync();
  return [
    for (final d in _libmpvDirs)
      for (final n in _libmpvNames) '$d/$n',
  ].any(e);
}

/// Stands in for the real player where audio can't work, so pressing play explains why
/// instead of failing inside Windows' media code.
class UnavailableAudioBackend implements AudioBackend {
  const UnavailableAudioBackend();

  @override
  Future<Duration?> load(Uri uri, {required MediaInfo info}) async => throw const AudioUnavailable();
  @override
  Future<void> play() async => throw const AudioUnavailable();
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration d) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<Duration?> get duration => const Stream.empty();
  @override
  Stream<Object> get errors => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

/// Microsoft's page listing the Media Feature Pack for each Windows N version.
const kMediaFeaturePackUrl =
    'https://support.microsoft.com/topic/media-feature-pack-list-for-windows-n-editions-c1c6fffa-d052-8338-7a79-a4bb980a700a';

/// Set at start-up when audio can't work here; null when it can.
final audioUnavailableProvider = Provider<AudioUnavailableReason?>((ref) => null);
