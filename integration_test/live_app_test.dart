import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/settings/settings_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live end-to-end check against api.ganjoor.net (M1 Task 16). Never disables
/// the network: "offline" is simulated with a client that cannot connect.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Directory('build/e2e_shots')..createSync(recursive: true);
  final boundary = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2))); // let network images land
    await tester.pumpAndSettle();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => ro.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('live: browse, read, theme, meaning, find, offline cache', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    final requests = <Uri>[];
    final dio = createDio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(o.uri);
            h.next(o);
          },
        ),
      );
    final liveApi = GanjoorApi(dio: dio, cache: HttpCache(db));

    Widget app(GanjoorApi api) => RepaintBoundary(
      key: boundary,
      child: ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          appDbProvider.overrideWithValue(db),
          ganjoorApiProvider.overrideWithValue(api),
        ],
        child: const GanjApp(),
      ),
    );

    await tester.pumpWidget(app(liveApi));
    await settle(tester, find.byKey(const ValueKey('poet-filter')));
    await shot(tester, '01_home');

    await tester.enterText(find.byKey(const ValueKey('poet-filter')), 'حافظ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('poet-2')));
    await settle(tester, find.text('غزلیات'));
    await shot(tester, '02_poet');

    await tester.tap(find.text('غزلیات'));
    await settle(tester, find.text('غزل شمارهٔ ۱'));
    await shot(tester, '03_category');

    await tester.tap(find.text('غزل شمارهٔ ۱'));
    const verse2 = 'که عشق آسان نمود اوّل ولی افتاد مشکل‌ها';
    await settle(tester, find.text(verse2));
    expect(find.text(verse2), findsOneWidget);
    expect(find.textContaining('مفاعیلن', findRichText: true), findsOneWidget);
    await shot(tester, '04_poem_wide_light');

    await tester.tap(find.byTooltip('معنی ابیات'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('جستجو در شعر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('find-field')), 'مشکلها');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('find-count'))).data, '۱ از ۱');
    await shot(tester, '05_poem_meaning_find');

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).last));
    container.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    container.read(settingsProvider.notifier).toggleMeaning();
    await tester.pumpAndSettle();
    await shot(tester, '06_poem_dark');

    // Narrow window: hemistichs stack.
    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();
    await shot(tester, '07_poem_narrow_dark');

    // Network log: only lean endpoints, never /page, verses always requested.
    for (final u in requests) {
      debugPrint('[e2e-net] $u');
    }
    expect(requests.where((u) => u.path.contains('/api/ganjoor/page')), isEmpty);
    expect(
      requests
          .where((u) => u.path.startsWith('/api/ganjoor/poem/'))
          .every((u) => u.queryParameters['verseDetails'] == 'true'),
      isTrue,
    );

    // Simulated offline: same cache, unreachable server.
    final deadDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9', connectTimeout: const Duration(seconds: 2)));
    final offlineApi = GanjoorApi(dio: deadDio, cache: HttpCache(db));
    expect((await tester.runAsync(() => offlineApi.poem(2130)))!.id, 2130);
    Object? error;
    await tester.runAsync(() async {
      try {
        await offlineApi.poem(2180);
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<DioException>());
    debugPrint('[e2e] offline: cached poem loads, unvisited poem errors as expected');
    await db.close();
  });
}
