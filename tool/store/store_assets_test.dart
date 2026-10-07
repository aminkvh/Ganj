// Renders the Google Play images into store/play/:
//   flutter test tool/store/store_assets_test.dart --update-goldens
// Real screens, real fonts, saved Ganjoor data; portraits from store/.portraits/.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/disk_image.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/core/theme/ganj_colors.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/tajik/tajik_text.dart';

import '../../test/support/fake_adapter.dart';
import '../../test/support/test_app.dart';

String ex(String name) => File('test/fixtures/extra/$name').readAsStringSync();

Future<void> loadFonts() async {
  await loadAppFonts();
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  final roboto = File('${Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter'}/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
  await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(roboto.readAsBytesSync())))).load();
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
}

void main() {
  setUpAll(() async {
    await loadFonts();
    DiskImage.configure(
      directory: null,
      fetch: (u) async => File('store/.portraits/${u.pathSegments.last}').readAsBytes(),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  GanjoorApi api(Map<String, String> routes) => GanjoorApi(
    dio: createDio(adapter: FakeAdapter(routes)),
    cache: HttpCache(AppDb(NativeDatabase.memory())),
  );

  Future<void> shot(
    WidgetTester tester,
    String name,
    String location, {
    Map<String, Object> prefs = const {},
    double scroll = 0,
  }) async {
    phone(tester);
    final p = await mockPrefs(prefs);
    await tester.pumpWidget(
      testAppRouted(
        location,
        prefs: p,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            api({
              '/api/ganjoor/book-catalog': ex('book_catalog.json'),
              '/api/ganjoor/search/semantic': ex('semantic.json'),
            }),
          ),
          tajikSourceProvider.overrideWithValue(
            TajikSource(
              dio: createDio(
                adapter: FakeAdapter({
                  '/gh/ganjoor/ganjoor-tajik-data@main/poets/hafez/ghazal/sh1.json': ex('tajik_sh1.json'),
                }),
              ),
              cache: HttpCache(AppDb(NativeDatabase.memory())),
            ),
          ),
        ],
      ),
    );
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus(); // no text cursor in the pictures
    if (scroll > 0) {
      await tester.drag(find.byType(CustomScrollView).first, Offset(0, -scroll));
      await settle(tester);
    }
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../store/play/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('1 home', (t) => shot(t, '1-home', '/'));
  testWidgets('2 poem with meanings', (t) => shot(t, '2-poem', '/poem/2130', prefs: {'showMeaning': true}));
  testWidgets('3 poem dark', (t) => shot(t, '3-poem-dark', '/poem/2130', prefs: {'theme': 2}));
  testWidgets(
    '4 search by meaning',
    (t) => shot(
      t,
      '4-meaning-search',
      '/search?mode=meaning&q=${Uri.encodeQueryComponent('در کدام شعر حافظ از ساقی و می سخن رفته')}',
    ),
  );
  testWidgets('5 tajik', (t) => shot(t, '5-tajik', '/poem/2130', prefs: {'showTajik': true}, scroll: 420));
  testWidgets('6 english', (t) => shot(t, '6-english', '/', prefs: {'language': 'en'}));

  testWidgets('feature graphic 1024x500', (tester) async {
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = buildGanjTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Builder(
          builder: (context) {
            final c = context.ganj;
            return Material(
              color: c.page,
              child: Container(
                padding: const EdgeInsets.all(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.gold, width: 2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                  child: Row(
                    children: [
                      const SizedBox(width: 300, height: 300), // the icon is pasted in afterwards (PIL)
                      const SizedBox(width: 40),
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('گنج', style: nastaliqOf(context, 78).copyWith(color: c.brandRed, height: 1.9)),
                              Text(
                                'شعر پارسی، روی هر دستگاه — حتی بی‌اینترنت',
                                style: TextStyle(fontSize: 30, color: c.ink, height: 1.6),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Persian poetry on every device — even offline',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(fontSize: 22, color: c.muted),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'به پاس گنجور · A tribute to Ganjoor',
                                style: TextStyle(fontSize: 18, color: c.gold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../store/play/feature-graphic.png'));
  });
}
