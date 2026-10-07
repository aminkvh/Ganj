import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/pack_importer.dart';
import 'package:ganj/data/packs/pack_installer.dart';

import '../../support/fake_adapter.dart';
import '../../support/gdb_builder.dart';
import 'pack_importer_test.dart' show hafezPack;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late AppDb db;
  late FakeAdapter adapter;
  late PackInstaller installer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ganj_inst_');
    db = AppDb(NativeDatabase.memory());
    adapter = FakeAdapter({});
    installer = PackInstaller(db, createDio(adapter: adapter), dir);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  List<int> zipOf(File gdb) {
    final a = Archive()
      ..add(ArchiveFile.bytes('hafez.gdb', gdb.readAsBytesSync()))
      ..add(ArchiveFile.bytes('2.png', [1, 2]));
    return ZipEncoder().encodeBytes(a);
  }

  test('downloads, unzips and imports a pack; temp files are removed', () async {
    adapter.binary['/android/gdb/hafez.zip'] = zipOf(buildHafezGdb(Directory.systemTemp.createTempSync('src_')));
    double? progress;
    await installer.install(hafezPack, onProgress: (v) => progress = v);
    expect(await installedPoets(db), {2});
    expect(progress, isNotNull);
    expect(dir.listSync().whereType<Directory>().where((d) => d.path.contains('pack_')), isEmpty);
  });

  test('a corrupt download leaves nothing half-installed', () async {
    adapter.binary['/android/gdb/hafez.zip'] = [1, 2, 3, 4, 5];
    await expectLater(installer.install(hafezPack), throwsA(anything));
    expect(await installedPoets(db), isEmpty);
  });

  test('a failed update keeps the installed pack intact', () async {
    adapter.binary['/android/gdb/hafez.zip'] = zipOf(buildHafezGdb(Directory.systemTemp.createTempSync('src_')));
    await installer.install(hafezPack);
    adapter.binary['/android/gdb/hafez.zip'] = [1, 2, 3]; // flaky network on update
    await expectLater(installer.install(hafezPack), throwsA(anything));
    expect(await installedPoets(db), {2});
    final c = await db.customSelect('SELECT count(*) AS c FROM poems').getSingle();
    expect(c.read<int>('c'), 2);
  });

  test('two installs at once both succeed (no ATTACH alias clash)', () async {
    adapter.binary['/android/gdb/hafez.zip'] = zipOf(buildHafezGdb(Directory.systemTemp.createTempSync('src_')));
    await Future.wait([installer.install(hafezPack), installer.install(hafezPack)]);
    expect(await installedPoets(db), {2});
  });

  test('a zip without a .gdb is rejected', () async {
    adapter.binary['/android/gdb/hafez.zip'] = ZipEncoder().encodeBytes(
      Archive()..add(ArchiveFile.bytes('x.txt', [65])),
    );
    await expectLater(installer.install(hafezPack), throwsA(isA<FormatException>()));
    expect(await installedPoets(db), isEmpty);
  });
}
