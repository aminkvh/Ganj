import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_catalog.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/packs/pack_installer.dart';
import 'package:ganj/features/library/library_providers.dart';
import 'package:ganj/features/library/library_screen.dart';
import 'package:ganj/features/player/audio_store.dart';

import '../../data/packs/pack_importer_test.dart' show hafezPack;
import '../../support/gdb_builder.dart';
import '../../support/test_app.dart';
import '../player/audio_store_test.dart' show MemoryAudioStore;

class FakeInstaller implements PackInstaller {
  FakeInstaller(this.db);

  final AppDb db;

  @override
  Future<ImportResult> install(PackInfo pack, {void Function(double)? onProgress}) async {
    onProgress?.call(0.5);
    return importGdb(db, buildHafezGdb(Directory.systemTemp.createTempSync('lib_')), pack);
  }
}

const saadiPack = PackInfo(
  poetId: 7,
  catId: 30,
  name: 'سعدی',
  url: 'https://i.ganjoor.net/android/gdb/saadi.zip',
  imageUrl: '',
  size: 2500000,
  pubDate: '2026-09-01',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> pump(WidgetTester tester, AppDb db, MemoryAudioStore store) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const LibraryScreen(),
        prefs: prefs,
        db: db,
        overrides: [
          packCatalogProvider.overrideWith((ref) async => [saadiPack, hafezPack]),
          packInstallerProvider.overrideWithValue(FakeInstaller(db)),
          audioStoreProvider.overrideWithValue(store),
        ],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('install and remove a poet pack', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await pump(tester, db, MemoryAudioStore());
    expect(find.text('حافظ'), findsOneWidget);
    expect(find.textContaining('م‌ب'), findsWidgets); // sizes shown before downloading
    await tester.tap(find.byKey(const ValueKey('pack-get-2')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pack-del-2')), findsOneWidget);
    expect(await tester.runAsync(() => installedPoets(db)), {2});
    await tester.tap(find.byKey(const ValueKey('pack-del-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف')); // confirm
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pack-get-2')), findsOneWidget);
    await tester.runAsync(db.close);
  });

  testWidgets('audio tab lists downloads and deletes them', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final store = MemoryAudioStore()..done.add(2840);
    await pump(tester, db, store);
    await tester.tap(find.text('خوانش‌ها'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('فریدون فرح‌اندوز'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audio-del-2840')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('فریدون فرح‌اندوز'), findsNothing);
    await tester.runAsync(db.close);
  });

  test('formatBytes uses Persian digits and units', () {
    expect(formatBytes(347000), '۳۳۹ ک‌ب');
    expect(formatBytes(2500000), '۲٫۴ م‌ب');
  });
}
