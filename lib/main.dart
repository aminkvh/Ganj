import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'startup_error.dart';
import 'router.dart' show initialLocationProvider;
import 'core/ui/smooth_wheel.dart';
import 'core/net/api_client.dart';
import 'core/text/content_en.dart';
import 'data/db/app_db.dart';
import 'data/providers.dart';
import 'features/player/audio_backend.dart';
import 'features/player/audio_handler.dart';
import 'features/player/audio_store.dart';
import 'features/player/player_controller.dart';
import 'features/player/unavailable_audio.dart';
import 'features/settings/licenses.dart';
import 'core/net/disk_image.dart';

/// `--route=/poem/2130` (desktop) opens the app on that page — handy for screenshots and checks.
Future<void> main(List<String> args) async {
  SmoothWheelBinding(); // smooth mouse-wheel scrolling on Windows/Linux
  try {
    await _start(args);
  } catch (e, st) {
    // A failure before the first screen used to leave an empty white window. Show it instead,
    // and keep the details in a log the reader can send.
    String? log;
    try {
      final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}ganj-startup.log');
      f.writeAsStringSync('${DateTime.now()}\n$e\n$st\n');
      log = f.path;
    } catch (_) {}
    runApp(StartupErrorApp(error: e, logPath: log));
  }
}

Future<void> _start(List<String> args) async {
  registerLicenses();
  // Linux plays through libmpv (media_kit); Windows uses just_audio_windows; others are native.
  // (Only when libmpv is installed; otherwise recitations explain how to add it.)
  if (Platform.isLinux && libmpvAvailable()) JustAudioMediaKit.ensureInitialized(linux: true, windows: false);

  final prefs = await SharedPreferences.getInstance();
  final english = EnglishContent.fromJson(
    names: await rootBundle.loadString('assets/seed/poet_names_en.json'),
    centuries: await rootBundle.loadString('assets/seed/centuries.json'),
  );
  final db = AppDb(driftDatabase(name: 'ganj'));
  // Pictures (portraits, manuscript thumbnails) are kept on disk, not fetched every launch.
  DiskImage.configure(
    directory: Directory('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}images'),
  );
  final audioDir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}audio');
  // Windows "N" editions lack Media Foundation until the Media Feature Pack is installed:
  // don't touch Windows' media code there, explain instead when play is pressed.
  // Linux without libmpv: same idea, and media_kit is never initialised there.
  final AudioUnavailableReason? noAudio = Platform.isWindows && !mediaFoundationAvailable()
      ? AudioUnavailableReason.windowsN
      : Platform.isLinux && !libmpvAvailable()
      ? AudioUnavailableReason.linuxNoMpv
      : null;
  final audioOk = noAudio == null;
  final AudioBackend backend = audioOk ? JustAudioBackend() : const UnavailableAudioBackend();

  // OS media controls (lock screen, notification, headset) on mobile and macOS only.
  GanjAudioHandler? handler;
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      handler = await AudioService.init(
        // Mobile and macOS always have media support, so this is the real player.
        builder: () => GanjAudioHandler(backend as JustAudioBackend),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'io.github.aminkvh.ganj.audio',
          androidNotificationChannelName: 'خوانش‌ها',
          androidNotificationOngoing: true,
        ),
      );
    } catch (e) {
      debugPrint('audio_service unavailable, playing without OS controls: $e');
    }
  }

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      appDbProvider.overrideWithValue(db),
      audioUnavailableProvider.overrideWithValue(noAudio),
      englishContentProvider.overrideWithValue(english),
      for (final a in args)
        if (a.startsWith('--route=')) initialLocationProvider.overrideWithValue(a.substring('--route='.length)),
      audioBackendProvider.overrideWithValue(backend),
      audioStoreProvider.overrideWith(
        (ref) => FileAudioStore(audioDir, createDio(), ref.watch(poetryRepositoryProvider)),
      ),
    ],
  );
  handler?.onSkip = (delta) =>
      delta > 0 ? container.read(playerProvider.notifier).next() : container.read(playerProvider.notifier).previous();

  runApp(UncontrolledProviderScope(container: container, child: const GanjApp()));
}
