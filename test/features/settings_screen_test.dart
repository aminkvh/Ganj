import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/settings/licenses.dart';
import 'package:ganj/features/settings/settings_controller.dart';
import 'package:ganj/features/settings/settings_screen.dart';

import '../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('theme, IranNastaliq and meanings controls update settings', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const SettingsScreen(), prefs: prefs));
    await settle(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    await tester.tap(find.text('تیره'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
    await tester.tap(find.text('نمایش معنی ابیات به‌طور پیش‌فرض'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).showMeaning, isTrue);
    await tester.tap(find.text('استفاده از قلم ایران‌نستعلیق (اگر نصب است)'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).iranNastaliq, isTrue);
    expect(prefs.getBool('iranNastaliq'), isTrue);
  });

  testWidgets('clearing the cache keeps packs and user data', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.customStatement("INSERT INTO api_cache (key, body, fetched_at) VALUES ('k', x'0011', 1)");
      await db.customStatement(
        "INSERT INTO packs (poet_id, cat_id, name, pub_date, size, installed_at) VALUES (2, 9, 'حافظ', 'x', 1, 1)",
      );
      await UserRepository(db).toggleBookmark(2130, 'a', 'A');
    });
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const SettingsScreen(), prefs: prefs, db: db));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('پاک‌کردن حافظهٔ موقت'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('پاک‌کردن حافظهٔ موقت'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('پاک‌کردن حافظهٔ موقت'));
    await settle(tester);
    Future<int> count(String t) async =>
        (await db.customSelect('SELECT count(*) AS c FROM $t').getSingle()).read<int>('c');
    expect(await tester.runAsync(() => count('api_cache')), 0);
    expect(await tester.runAsync(() => count('packs')), 1);
    expect(await tester.runAsync(() => UserRepository(db).isBookmarked(2130)), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('about credits Ganjoor', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const SettingsScreen(), prefs: prefs));
    await settle(tester);
    await tester.scrollUntilVisible(find.textContaining('گنجور'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('گنجور'), findsWidgets);
  });

  test('licenses for the app and both fonts are registered', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerLicenses();
    final packages = <String>{};
    await for (final l in LicenseRegistry.licenses) {
      packages.addAll(l.packages);
    }
    expect(packages, containsAll(['گنج (Ganj)', 'Vazirmatn', 'Noto Nastaliq Urdu']));
  });

  test('IranNastaliq preference changes the heading font with a bundled fallback', () {
    final light = buildGanjTheme(Brightness.light, iranNastaliq: true);
    final s = nastaliqStyleFor(light, 30);
    expect(s.fontFamily, 'IranNastaliq');
    expect(s.fontFamilyFallback, contains(kNastaliqFont));
    expect(nastaliqStyleFor(buildGanjTheme(Brightness.light), 30).fontFamily, kNastaliqFont);
  });
}
