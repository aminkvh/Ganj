// Named params can't be private initializing formals, so fields are assigned in the initializer list.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'voice_manifest.dart';

enum VoiceDownloadFailure { offline, checksum, noSpace, cancelled }

class VoiceDownloadError implements Exception {
  const VoiceDownloadError(this.kind);

  final VoiceDownloadFailure kind;

  @override
  String toString() => 'VoiceDownloadError($kind)';
}

/// The `<root>/<version>-<variant>` folder (or a phase 1 `<root>/<version>` one, which counts as quality) that holds
/// `installed.json`, or null when nothing is installed. Of several, the one installed last (`installedAt`) wins; a
/// folder without a stamp counts as older than any stamped one, and ties go to the lexicographically last path.
Directory? installedDir(Directory root) {
  if (!root.existsSync()) return null;
  final dirs = [
    for (final d in root.listSync().whereType<Directory>())
      if (File('${d.path}${Platform.pathSeparator}installed.json').existsSync()) d,
  ];
  if (dirs.isEmpty) return null;
  final at = {for (final d in dirs) d.path: _installedAt(d)};
  dirs.sort((a, b) {
    final x = at[a.path], y = at[b.path];
    if (x != y) {
      if (x == null) return -1;
      if (y == null) return 1;
      return x.compareTo(y);
    }
    return a.path.compareTo(b.path);
  });
  return dirs.last;
}

DateTime? _installedAt(Directory dir) {
  try {
    final j = jsonDecode(File('${dir.path}${Platform.pathSeparator}installed.json').readAsStringSync());
    final v = (j as Map)['installedAt'];
    return v is String ? DateTime.tryParse(v) : null;
  } catch (_) {
    return null;
  }
}

/// The variant recorded in [dir]'s `installed.json`; a folder without one (phase 1) is `quality`.
String installedVariant(Directory dir) {
  try {
    final j = jsonDecode(File('${dir.path}${Platform.pathSeparator}installed.json').readAsStringSync());
    final v = (j as Map)['variant'];
    return v is String && v.isNotEmpty ? v : kQualityVariant;
  } catch (_) {
    return kQualityVariant;
  }
}

/// Downloads the voice files from a list of mirror sources, resumable and checksummed.
class VoiceDownloader {
  VoiceDownloader({
    required Dio dio,
    required Directory root,
    required Map<String, String> sources,
    String? preferred,
    Duration timeout = const Duration(seconds: 10),
  }) : _dio = dio,
       _root = root,
       _sources = sources,
       _preferred = preferred,
       _timeout = timeout;

  final Dio _dio;
  final Directory _root;
  final Map<String, String> _sources;
  final String? _preferred;
  final Duration _timeout;

  /// The source that served the last manifest; files are fetched from it first.
  String? _manifestSource;

  List<String> _order([String? first]) {
    final head = first ?? _preferred;
    final keys = _sources.keys.toList();
    if (head != null && keys.remove(head)) keys.insert(0, head);
    return keys;
  }

  String _url(String key, String name) {
    final base = _sources[key]!;
    return base.endsWith('/') ? '$base$name' : '$base/$name';
  }

  Future<Response<T>> _get<T>(
    String url, {
    required ResponseType type,
    Map<String, dynamic>? headers,
    CancelToken? cancel,
  }) {
    return _dio.fetch<T>(
      RequestOptions(
        path: url,
        method: 'GET',
        responseType: type,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        cancelToken: cancel,
        // i.ganjoor.net-style servers dislike a JSON-only Accept; mirrors serve binary.
        headers: {'Accept': '*/*', ...?headers},
        validateStatus: (s) => s == 200 || s == 206,
      ),
    );
  }

  Future<VoiceManifest> fetchManifest() async {
    for (final key in _order()) {
      try {
        final r = await _get<String>(_url(key, 'voice.json'), type: ResponseType.plain).timeout(_timeout * 2);
        final m = VoiceManifest.fromJson(jsonDecode(r.data!) as Map<String, dynamic>);
        _manifestSource = key;
        return m;
      } catch (_) {
        // Try the next source.
      }
    }
    throw const VoiceDownloadError(VoiceDownloadFailure.offline);
  }

  /// Downloads the shared files and [variant]'s files of [m] into `<root>/<version>-<variant>`; returns the key
  /// of the source that served the manifest. `installed.json` records the version, the variant and exactly those files.
  Future<String> install(
    VoiceManifest m, {
    required String variant,
    void Function(int got, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final files = m.filesFor(variant);
    final primary = _manifestSource ?? _order().first;
    final dir = Directory('${_root.path}${Platform.pathSeparator}${m.version}-$variant');
    try {
      await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw _mapFs(e);
    }
    final total = m.sizeOf(variant);
    var done = 0;
    for (final f in files) {
      if (cancel?.isCancelled ?? false) {
        throw const VoiceDownloadError(VoiceDownloadFailure.cancelled);
      }
      final base = done;
      await _installFile(f, dir, primary, cancel, (n) => onProgress?.call(base + n, total));
      done += f.size;
    }
    try {
      final tmp = File('${dir.path}${Platform.pathSeparator}installed.json.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'version': m.version,
          'variant': variant,
          'installedAt': DateTime.now().toUtc().toIso8601String(),
          'files': [for (final f in files) f.toJson()],
        }),
        flush: true,
      );
      await tmp.rename('${dir.path}${Platform.pathSeparator}installed.json');
    } on FileSystemException catch (e) {
      throw _mapFs(e);
    }
    return primary;
  }

  Future<void> _installFile(
    VoiceFile f,
    Directory dir,
    String primary,
    CancelToken? cancel,
    void Function(int) progress,
  ) async {
    final target = File('${dir.path}${Platform.pathSeparator}${f.name}');
    final part = File('${target.path}.part');
    if (target.existsSync()) {
      if (await target.length() == f.size && await _sha(target) == f.sha256) {
        progress(f.size);
        return;
      }
      await target.delete();
    }
    // A complete .part (e.g. killed before the rename): verify instead of asking for a Range past the end.
    if (part.existsSync() && await part.length() == f.size) {
      if (await _sha(part) == f.sha256) {
        await part.rename(target.path);
        progress(f.size);
        return;
      }
      await part.delete();
    }
    VoiceDownloadError? last;
    // The .part is kept across sources and resumed with Range: every source serves the same
    // bytes, and the sha256 check below is the guard. Only a checksum mismatch deletes it.
    for (final key in _order(primary)) {
      try {
        await _fetchTo(_url(key, f.name), part, f, cancel, progress);
        if (await _sha(part) != f.sha256) {
          await part.delete();
          throw const VoiceDownloadError(VoiceDownloadFailure.checksum);
        }
        await part.rename(target.path);
        return;
      } on VoiceDownloadError catch (e) {
        if (e.kind == VoiceDownloadFailure.cancelled || e.kind == VoiceDownloadFailure.noSpace) {
          rethrow;
        }
        last = e;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw const VoiceDownloadError(VoiceDownloadFailure.cancelled);
        }
        last = const VoiceDownloadError(VoiceDownloadFailure.offline);
      } on FileSystemException catch (e) {
        throw _mapFs(e);
      } on IOException {
        last = const VoiceDownloadError(VoiceDownloadFailure.offline);
      } on TimeoutException {
        last = const VoiceDownloadError(VoiceDownloadFailure.offline);
      }
      progress(0);
    }
    throw last ?? const VoiceDownloadError(VoiceDownloadFailure.offline);
  }

  /// Streams [url] into [part], resuming from its current length when it exists.
  Future<void> _fetchTo(String url, File part, VoiceFile f, CancelToken? cancel, void Function(int) progress) async {
    var have = part.existsSync() ? await part.length() : 0;
    if (have > f.size) {
      await part.writeAsBytes(const []);
      have = 0;
    }
    final res = await _get<ResponseBody>(
      url,
      type: ResponseType.stream,
      cancel: cancel,
      headers: have > 0 ? {'Range': 'bytes=$have-'} : null,
    );
    // A 200 to a ranged request means the server ignored Range: start the file over.
    final resumed = res.statusCode == 206 && have > 0;
    if (!resumed) have = 0;
    final raf = await part.open(mode: resumed ? FileMode.append : FileMode.write);
    try {
      var got = have;
      progress(got);
      // A source that stays connected but stops sending counts as failed (TimeoutException).
      await for (final chunk in res.data!.stream.timeout(_timeout)) {
        if (cancel?.isCancelled ?? false) {
          throw const VoiceDownloadError(VoiceDownloadFailure.cancelled);
        }
        await raf.writeFrom(chunk);
        got += chunk.length;
        progress(got);
      }
      if (got != f.size) {
        throw const VoiceDownloadError(VoiceDownloadFailure.offline);
      }
    } finally {
      await raf.close();
    }
  }

  Future<String> _sha(File f) async => (await sha256.bind(f.openRead()).first).toString();

  VoiceDownloadError _mapFs(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ENOSPC: 28 on Linux/Android, ERROR_DISK_FULL 112 on Windows.
    if (code == 28 || code == 112) {
      return const VoiceDownloadError(VoiceDownloadFailure.noSpace);
    }
    throw e;
  }
}
