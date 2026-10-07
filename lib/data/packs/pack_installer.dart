import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';

import '../../core/net/request_pool.dart';
import '../db/app_db.dart';
import 'pack_catalog.dart';
import 'pack_importer.dart';

/// Downloads a poet pack from Ganjoor, extracts its `.gdb` to disk and imports it.
/// Installs run one at a time (the import ATTACHes the pack under a fixed alias).
/// A failure never removes a previously installed version; temp files are always removed.
class PackInstaller {
  PackInstaller(this._db, this._dio, this._tmpRoot);

  final AppDb _db;
  final Dio _dio;
  final Directory _tmpRoot;
  static final _oneAtATime = RequestPool(1);

  Future<ImportResult> install(PackInfo pack, {void Function(double)? onProgress}) =>
      _oneAtATime.run(() => _install(pack, onProgress));

  Future<ImportResult> _install(PackInfo pack, void Function(double)? onProgress) async {
    await _tmpRoot.create(recursive: true);
    final work = await _tmpRoot.createTemp('pack_');
    final wasInstalled = (await installedPoets(_db)).contains(pack.poetId);
    try {
      final zip = File('${work.path}${Platform.pathSeparator}${pack.poetId}.zip');
      await _dio.download(
        pack.url,
        zip.path,
        options: Options(headers: {'Accept': '*/*'}),
        onReceiveProgress: (got, total) => onProgress?.call(total > 0 ? got / total : 0),
      );
      final out = Directory('${work.path}${Platform.pathSeparator}x');
      await extractFileToDisk(zip.path, out.path); // streams entries to disk
      File? gdb;
      await for (final e in out.list(recursive: true)) {
        if (e is File && e.path.toLowerCase().endsWith('.gdb')) gdb = e;
      }
      if (gdb == null) throw const FormatException('pack has no .gdb file');
      return await importGdb(_db, gdb, pack);
    } catch (_) {
      // The import is atomic, so an update that fails leaves the old pack in place.
      if (!wasInstalled) await uninstall(_db, pack.poetId);
      rethrow;
    } finally {
      await work.delete(recursive: true);
    }
  }
}
