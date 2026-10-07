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
import 'core/ui/smooth_wheel.dart';
import 'core/net/api_client.dart';
import 'core/text/content_en.dart';
import 'data/db/app_db.dart';
import 'data/providers.dart';
import 'features/player/audio_backend.dart';
import 'features/player/audio_handler.dart';
import 'features/player/audio_store.dart';
import 'features/player/player_controller.dart';
import 'features/settings/licenses.dart';

Future<void> main() async {
  SmoothWheelBinding(); // smooth mouse-wheel scrolling on Windows/Linux
  registerLicenses();
  // Linux plays through libmpv (media_kit); Windows uses just_audio_windows; others are native.
  if (Platform.isLinux) JustAudioMediaKit.ensureInitialized(linux: true, windows: false);

  final prefs = await SharedPreferences.getInstance();
  final english = EnglishContent.fromJson(
    names: await rootBundle.loadString('assets/seed/poet_names_en.json'),
    centuries: await rootBundle.loadString('assets/seed/centuries.json'),
  );
  final db = AppDb(driftDatabase(name: 'ganj'));
  final audioDir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}audio');
  final backend = JustAudioBackend();

  // OS media controls (lock screen, notification, headset) on mobile and macOS only.
  GanjAudioHandler? handler;
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      handler = await AudioService.init(
        builder: () => GanjAudioHandler(backend),
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
      englishContentProvider.overrideWithValue(english),
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
