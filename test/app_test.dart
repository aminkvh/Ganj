import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ganj/app.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/router.dart';

import 'support/fake_audio_backend.dart';
import 'support/fixture_repository.dart';
import 'support/test_app.dart';

void main() {
  testWidgets('home → poet → category → poem', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
          audioBackendProvider.overrideWithValue(FakeAudioBackend()),
          appDbProvider.overrideWithValue(AppDb(NativeDatabase.memory())),
        ],
        child: const GanjApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('poet-filter')), 'حافظ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('poet-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('غزلیات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('غزل شمارهٔ ۱'));
    await tester.pumpAndSettle();
    expect(find.text('که عشق آسان نمود اوّل ولی افتاد مشکل‌ها'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(Scaffold).last)), TextDirection.rtl);

    // Playing a recitation shows the app-wide mini-player, and it stays when navigating back.
    await tester.tap(find.textContaining('خوانش‌ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rec-play-2840')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(GanjApp))).read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
  });
}
