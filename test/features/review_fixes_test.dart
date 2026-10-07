import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:ganj/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/home/home_screen.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_audio_backend.dart';
import '../support/fixture_repository.dart';
import '../support/test_app.dart';

/// Throws a real network error (DioException) until [online]; can hold the next load open.
class FlakyRepository extends FixtureRepository {
  bool online = false;
  Completer<void>? gate;

  @override
  Future<Poem> poem(int id) async {
    if (!online) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/poem/$id'),
        reason: 'offline',
      );
    }
    await gate?.future;
    return super.poem(id);
  }
}

/// Like testApp but WITHOUT the test-only `retry: null`, so production retry behaviour applies.
Widget prodLikeApp(Widget home, SharedPreferences prefs, FixtureRepository repo) => ProviderScope(
  overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    poetryRepositoryProvider.overrideWithValue(repo),
    audioBackendProvider.overrideWithValue(FakeAudioBackend()),
    appDbProvider.overrideWithValue(AppDb(NativeDatabase.memory())),
  ],
  child: MaterialApp(
    theme: buildGanjTheme(Brightness.light),
    locale: const Locale('fa'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: home,
  ),
);

void main() {
  testWidgets('network error shows retry promptly (no silent auto-retry)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(prodLikeApp(const PoemScreen(id: 2130), prefs, FlakyRepository()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });

  testWidgets('pressing retry shows progress while reloading', (tester) async {
    final prefs = await mockPrefs();
    final repo = FlakyRepository();
    await tester.pumpWidget(prodLikeApp(const PoemScreen(id: 2130), prefs, repo));
    await tester.pumpAndSettle();
    repo
      ..online = true
      ..gate = Completer<void>();
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('که عشق آسان نمود اوّل ولی افتاد مشکل‌ها'), findsOneWidget);
  });

  for (final (name, size, keyboard) in [
    ('phone with keyboard up', const Size(360, 640), 260.0),
    ('landscape phone', const Size(640, 360), 0.0),
  ]) {
    testWidgets('home does not overflow: $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      final prefs = await mockPrefs();
      await tester.pumpWidget(testApp(const HomeScreen(), prefs: prefs, repo: FixtureRepository()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RTL chevrons point the reading direction', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 77000), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    // Icons.chevron_* mirror in RTL: chevron_right renders pointing left (= forward/next in Persian).
    expect(
      find.descendant(of: find.byKey(const ValueKey('nav-next')), matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('nav-prev')), matching: find.byIcon(Icons.chevron_left)),
      findsOneWidget,
    );
  });
}
