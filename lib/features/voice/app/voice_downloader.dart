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

String _in(Directory dir, String name) => '${dir.path}${Platform.pathSeparator}$name';

/// The marker [VoiceDownloader.finishSwap] keeps in the new folder while it moves files out of the old one.
const _kSwapping = 'swapping.json';

/// Finishes a swap that was killed half way: for each folder under [root] holding `swapping.json`, moves the files
/// it still lists from the old folder (rename only), then writes `installed.json` and drops the marker. A folder
/// whose files can't all be found or moved is left as it is; nothing here throws. Call it before [installedDir] at
/// startup: an interrupted swap leaves the old folder installed but missing files.
void resumeInterruptedSwap(Directory root) {
  try {
    if (!root.existsSync()) return;
    for (final dir in root.listSync().whereType<Directory>()) {
      try {
        final marker = File(_in(dir, _kSwapping));
        if (!marker.existsSync()) continue;
        final j = jsonDecode(marker.readAsStringSync()) as Map;
        final fromName = j['from'] as String;
        if (fromName.isEmpty || fromName.contains('..') || fromName.contains('/') || fromName.contains(r'\')) {
          continue;
        }
        final from = Directory(_in(root, fromName));
        final files = [for (final f in (j['files'] as List)) VoiceFile.fromJson((f as Map).cast<String, dynamic>())];
        final move = {for (final n in (j['move'] as List)) n as String};
        // Look before moving anything, so a missing file leaves the folders untouched.
        if (!files.every((f) => _hasSize(dir, f) || (move.contains(f.name) && _hasSize(from, f)))) continue;
        if (!files.every((f) => !move.contains(f.name) || _moveSync(from, dir, f))) continue;
        _completeSwap(dir, from, j['version'] as String, j['variant'] as String, files);
      } catch (_) {
        // Left for the next start or the next swap.
      }
    }
  } catch (_) {
    // As above.
  }
}

bool _hasSize(Directory dir, VoiceFile f) {
  final file = File(_in(dir, f.name));
  return file.existsSync() && file.lengthSync() == f.size;
}

/// Puts [f] into [dir] by renaming it from [from], unless it is already there with its size; a wrong-sized leftover
/// (an interrupted copy) is replaced. False when it is in neither place or the rename fails (e.g. across volumes).
bool _moveSync(Directory from, Directory dir, VoiceFile f) {
  if (_hasSize(dir, f)) return true;
  if (!_hasSize(from, f)) return false;
  try {
    final target = File(_in(dir, f.name));
    if (target.existsSync()) target.deleteSync();
    File(_in(from, f.name)).renameSync(target.path);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// [from]'s file record: `installed.json`, or `installed.json.old` once a swap has retired it.
Map? _recordOf(Directory from) {
  for (final n in ['installed.json', 'installed.json.old']) {
    try {
      return jsonDecode(File(_in(from, n)).readAsStringSync()) as Map;
    } catch (_) {
      // Try the next one.
    }
  }
  return null;
}

Map<String, dynamic> _installedJson(String version, String variant, List<VoiceFile> files, DateTime at) => {
  'version': version,
  'variant': variant,
  'installedAt': at.toUtc().toIso8601String(),
  'files': [for (final f in files) f.toJson()],
};

/// The last step of a swap, once every file is in [dir]: writes its `installed.json` (tmp + rename) stamped after
/// [from]'s, so [installedDir] picks [dir] even with a clock behind that stamp; then retires [from]'s record to
/// `installed.json.old` and drops the swap and stage markers and leftover `.swap` copies. Every step is safe to
/// repeat.
void _completeSwap(Directory dir, Directory from, String version, String variant, List<VoiceFile> files) {
  var at = DateTime.now().toUtc();
  final old = _recordOf(from)?['installedAt'];
  final oldAt = old is String ? DateTime.tryParse(old) : null;
  if (oldAt != null && !at.isAfter(oldAt)) at = oldAt.add(const Duration(milliseconds: 1));
  final tmp = File(_in(dir, 'installed.json.tmp'));
  tmp.writeAsStringSync(jsonEncode(_installedJson(version, variant, files, at)), flush: true);
  tmp.renameSync(_in(dir, 'installed.json'));
  if (from.path != dir.path) {
    final rec = File(_in(from, 'installed.json'));
    if (rec.existsSync()) rec.renameSync(_in(from, 'installed.json.old'));
  }
  // The markers, and any half copy left by a fallback copy that was killed.
  for (final n in [_kSwapping, 'staged.json', for (final f in files) '${f.name}.swap']) {
    final f = File(_in(dir, n));
    if (f.existsSync()) f.deleteSync();
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
    await _writeInstalled(dir, m, variant);
    return primary;
  }

  /// Writes `installed.json` (version, variant, installedAt and [m]'s files for [variant]) via a tmp file and a
  /// rename, so the folder counts as installed only once everything in it is in place.
  Future<void> _writeInstalled(Directory dir, VoiceManifest m, String variant) =>
      _writeJson(dir, 'installed.json', _installedJson(m.version, variant, m.filesFor(variant), DateTime.now()));

  Future<void> _writeJson(Directory dir, String name, Map<String, dynamic> j) async {
    try {
      final tmp = File(_in(dir, '$name.tmp'));
      await tmp.writeAsString(jsonEncode(j), flush: true);
      await tmp.rename(_in(dir, name));
    } on FileSystemException catch (e) {
      throw _mapFs(e);
    }
  }

  Directory _dirFor(VoiceManifest m, String variant) => Directory(_in(_root, '${m.version}-$variant'));

  /// [m]'s files for [variant] split by whether [from]'s record (`installed.json`, or `installed.json.old` after a
  /// swap) lists the same name, size and sha256. Those shas were verified when [from] was installed, so they are
  /// trusted. An unreadable record means everything has changed.
  ({List<VoiceFile> changed, List<VoiceFile> unchanged}) _split(VoiceManifest m, String variant, Directory from) {
    final have = <String>{};
    try {
      for (final f in (_recordOf(from)!['files'] as List)) {
        final v = VoiceFile.fromJson((f as Map).cast<String, dynamic>());
        have.add('${v.name}\n${v.size}\n${v.sha256}');
      }
    } catch (_) {
      have.clear();
    }
    final changed = <VoiceFile>[], unchanged = <VoiceFile>[];
    for (final f in m.filesFor(variant)) {
      (have.contains('${f.name}\n${f.size}\n${f.sha256}') ? unchanged : changed).add(f);
    }
    return (changed: changed, unchanged: unchanged);
  }

  /// The bytes [stage] would download for [m] and [variant] beside [from]: the size of the files that differ.
  int changedBytes(VoiceManifest m, {required String variant, required Directory from}) =>
      _split(m, variant, from).changed.fold(0, (n, f) => n + f.size);

  /// Downloads into `<root>/<version>-<variant>` only the files of [m] that differ from [from]'s install, while
  /// [from] stays the voice in use: no `installed.json` is written, so [installedDir] keeps choosing [from].
  /// `staged.json` records what was staged once every file is verified. Returns the source key, as [install] does.
  Future<String> stage(VoiceManifest m, {required String variant, required Directory from, CancelToken? cancel}) async {
    final changed = _split(m, variant, from).changed;
    final primary = _manifestSource ?? _order().first;
    final dir = _dirFor(m, variant);
    try {
      await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw _mapFs(e);
    }
    for (final f in changed) {
      if (cancel?.isCancelled ?? false) {
        throw const VoiceDownloadError(VoiceDownloadFailure.cancelled);
      }
      await _installFile(f, dir, primary, cancel, (_) {});
    }
    await _writeJson(dir, 'staged.json', {
      'version': m.version,
      'variant': variant,
      'files': [for (final f in changed) f.toJson()],
    });
    return primary;
  }

  /// Whether [stage] finished for [m] and [variant]: `staged.json` names exactly the changed files (their shas were
  /// verified by [stage]), each is still there with its size, and every unchanged file is in [from] or already
  /// moved to the new folder.
  bool staged(VoiceManifest m, {required String variant, required Directory from}) {
    final dir = _dirFor(m, variant);
    final split = _split(m, variant, from);
    try {
      final j = jsonDecode(File(_in(dir, 'staged.json')).readAsStringSync()) as Map;
      if (j['version'] != m.version || j['variant'] != variant) return false;
      final recorded = {
        for (final f in (j['files'] as List))
          jsonEncode(VoiceFile.fromJson((f as Map).cast<String, dynamic>()).toJson()),
      };
      final want = {for (final f in split.changed) jsonEncode(f.toJson())};
      if (recorded.length != want.length || !recorded.containsAll(want)) return false;
    } catch (_) {
      return false;
    }
    return split.changed.every((f) => _hasSize(dir, f)) &&
        split.unchanged.every((f) => _hasSize(dir, f) || _hasSize(from, f));
  }

  /// Completes a [stage]: moves each unchanged file from [from] into the new folder (unless it is already there with
  /// its size), then writes `installed.json`, making the new folder the installed voice, and retires [from]'s
  /// record to `installed.json.old`. Call it when nothing reads [from]. While files move, `swapping.json` in the new
  /// folder lets [resumeInterruptedSwap] finish the job after a kill; running this again also resumes. Throws
  /// [VoiceDownloadError] (checksum, the closest kind for a file gone missing), before moving anything, when a
  /// staged file or an unchanged file can't be found. When a move fails (a locked file, say), the files already
  /// moved go back to [from], which stays whole and installed, and the error is rethrown; the stage is kept.
  Future<void> finishSwap(VoiceManifest m, {required String variant, required Directory from}) async {
    final dir = _dirFor(m, variant);
    final split = _split(m, variant, from);
    if (!split.changed.every((f) => _hasSize(dir, f)) ||
        !split.unchanged.every((f) => _hasSize(dir, f) || _hasSize(from, f))) {
      throw const VoiceDownloadError(VoiceDownloadFailure.checksum);
    }
    final files = m.filesFor(variant);
    await _writeJson(dir, _kSwapping, {
      'from': from.uri.pathSegments.where((s) => s.isNotEmpty).last,
      'version': m.version,
      'variant': variant,
      'files': [for (final f in files) f.toJson()],
      'move': [for (final f in split.unchanged) f.name],
    });
    try {
      for (final f in split.unchanged) {
        if (_moveSync(from, dir, f)) continue;
        // Another volume: copy beside the target, rename it in, then drop the original.
        final target = File(_in(dir, f.name));
        final tmp = File('${target.path}.swap');
        if (target.existsSync()) await target.delete();
        await File(_in(from, f.name)).copy(tmp.path);
        await tmp.rename(target.path);
        await File(_in(from, f.name)).delete();
      }
      _completeSwap(dir, from, m.version, variant, files);
    } catch (e) {
      // Once installed.json is written the new folder is the voice, and the marker finishes the rest at startup.
      if (!File(_in(dir, 'installed.json')).existsSync()) _rollBack(dir, from, split.unchanged);
      if (e is FileSystemException) throw _mapFs(e);
      rethrow;
    }
  }

  /// Undoes a [finishSwap] that failed before the new folder [dir] was installed: each of [moved] found in [dir] goes
  /// back to [from] (rename only), half copies are dropped, and so is the marker, so nothing finishes the swap at
  /// the next start. When a file can't go back, the marker stays: [resumeInterruptedSwap] then completes the swap
  /// instead, rather than leave [from] installed with files missing.
  void _rollBack(Directory dir, Directory from, List<VoiceFile> moved) {
    try {
      final back = moved.every((f) => _moveSync(dir, from, f));
      for (final f in moved) {
        final half = File('${_in(dir, f.name)}.swap');
        if (half.existsSync()) half.deleteSync();
      }
      if (back) File(_in(dir, _kSwapping)).deleteSync();
    } on FileSystemException {
      // As above: the marker stays.
    }
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
