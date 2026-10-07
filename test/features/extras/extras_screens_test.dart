import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:ganj/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/data/repo/poetry_repository.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/extras/faal_screen.dart';
import 'package:ganj/features/extras/random_poem.dart';
import 'package:ganj/features/extras/url_screen.dart';
import 'package:go_router/go_router.dart';

import '../../data/extras_test.dart' show ex;
import '../../support/fake_adapter.dart';
import '../../support/fake_audio_backend.dart';
import '../../support/test_app.dart';

/// Router harness: the screen under test at '/', poems render as `poem <id>`.
Future<void> pumpRouted(WidgetTester tester, Widget screen, FakeAdapter adapter, {PoetryRepository? repo}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDb(NativeDatabase.memory());
  final prefs = await mockPrefs();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/poem/:id',
        builder: (_, s) => Scaffold(body: Text('poem ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/similar',
        builder: (_, s) =>
            Scaffold(body: Text('similar ${s.uri.queryParameters['metre']} | ${s.uri.queryParameters['rhyme']}')),
      ),
      GoRoute(
        path: '/url',
        builder: (_, s) => UrlScreen(url: s.uri.queryParameters['u'] ?? ''),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        appDbProvider.overrideWithValue(db),
        if (repo != null) poetryRepositoryProvider.overrideWithValue(repo),
        audioBackendProvider.overrideWithValue(FakeAudioBackend()),
        ganjoorApiProvider.overrideWithValue(
          GanjoorApi(
            dio: createDio(adapter: adapter),
            cache: HttpCache(db),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: buildGanjTheme(Brightness.light),
        locale: const Locale('fa'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('faal: invocation first, then opens the faal poem', (tester) async {
    await pumpRouted(tester, const FaalScreen(), FakeAdapter({'/api/ganjoor/hafez/faal': ex('faal.json')}));
    expect(find.textContaining('حافظ شیرازی'), findsWidgets);
    await tester.tap(find.text('گشودن فال'));
    await settle(tester);
    expect(find.text('poem 2445'), findsOneWidget);
  });

  testWidgets('random poem opens the fetched poem', (tester) async {
    await pumpRouted(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(onPressed: () => openRandomPoem(context, ref, poetId: 2), child: const Text('تصادفی')),
        ),
      ),
      FakeAdapter({'/api/ganjoor/poem/random': ex('random.json')}),
    );
    await tester.tap(find.text('تصادفی'));
    await settle(tester);
    expect(find.text('poem 2177'), findsOneWidget);
  });

  testWidgets('url route resolves a site path to a poem', (tester) async {
    await pumpRouted(
      tester,
      const UrlScreen(url: '/ebnehesam/ghazalebn/sh1'),
      FakeAdapter({'/api/ganjoor/poem': '{"id":64590,"title":"غزل","fullUrl":"/ebnehesam/ghazalebn/sh1"}'}),
    );
    await settle(tester);
    expect(find.text('poem 64590'), findsOneWidget);
  });

  testWidgets('unresolvable url shows a message, not a crash', (tester) async {
    await pumpRouted(tester, const UrlScreen(url: '/nowhere'), FakeAdapter({}));
    await settle(tester);
    expect(find.text('این شعر پیدا نشد'), findsOneWidget);
  });
}
