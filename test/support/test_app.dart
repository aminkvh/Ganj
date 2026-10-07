import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ganj/app.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/l10n/l10n.dart';
import 'package:ganj/router.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/data/repo/poetry_repository.dart';
import 'package:ganj/features/player/audio_backend.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_backend.dart';
import 'fixture_repository.dart';

/// The English content table, read from the assets on disk once.
final testEnglishContent = EnglishContent.fromJson(
  names: File('assets/seed/poet_names_en.json').readAsStringSync(),
  centuries: File('assets/seed/centuries.json').readAsStringSync(),
);

Future<SharedPreferences> mockPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Widget testApp(
  Widget home, {
  required SharedPreferences prefs,
  PoetryRepository? repo,
  AudioBackend? backend,
  AppDb? db,
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  String language = 'fa',
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  latinNumbers = language == 'en';
  englishContent = language == 'en' ? testEnglishContent : null;
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      appDbProvider.overrideWithValue(db ?? AppDb(NativeDatabase.memory())),
      sharedPrefsProvider.overrideWithValue(prefs),
      if (repo != null) poetryRepositoryProvider.overrideWithValue(repo),
      audioBackendProvider.overrideWithValue(backend ?? FakeAudioBackend()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: buildGanjTheme(brightness),
      locale: Locale(language),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: home,
    ),
  );
}

/// Real fonts for golden tests (otherwise flutter_test renders Ahem boxes).
Future<void> loadAppFonts() async {
  for (final (family, file) in [
    (kBodyFont, 'assets/fonts/Vazirmatn-Variable.ttf'),
    (kNastaliqFont, 'assets/fonts/NotoNastaliqUrdu-Variable.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(file))).load();
  }
}

/// The real app (router, shell, mini-player) starting at [location].
Widget testAppRouted(
  String location, {
  required SharedPreferences prefs,
  PoetryRepository? repo,
  List<Override> overrides = const [],
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      appDbProvider.overrideWithValue(AppDb(NativeDatabase.memory())),
      sharedPrefsProvider.overrideWithValue(prefs),
      poetryRepositoryProvider.overrideWithValue(repo ?? FixtureRepository()),
      audioBackendProvider.overrideWithValue(FakeAudioBackend()),
      initialLocationProvider.overrideWithValue(location),
      englishContentProvider.overrideWithValue(testEnglishContent),
      ...overrides,
    ],
    child: const GanjApp(),
  );
}
