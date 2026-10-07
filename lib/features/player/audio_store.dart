import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto/recitation.dart';
import '../../data/repo/poetry_repository.dart';

/// A recitation saved on this device.
class DownloadedRecitation {
  const DownloadedRecitation({
    required this.id,
    required this.poemId,
    required this.title,
    required this.artist,
    required this.bytes,
  });

  final int id;
  final int poemId;
  final String title;
  final String artist;
  final int bytes;
}

/// Offline recitations: an mp3 plus its verse timings, downloaded only from Ganjoor's servers.
abstract class AudioStore {
  /// Full records of this poem's downloaded recitations (for offline poems served from packs).
  Future<List<Recitation>> downloadedFor(int poemId);
  Future<List<DownloadedRecitation>> listDownloaded();
  bool isDownloaded(int id);
  Uri mp3Uri(int id);
  Future<List<SyncPoint>?> savedSync(int id);
  Future<void> download(Recitation r, {void Function(double)? onProgress});
  Future<void> delete(int id);
}

class FileAudioStore implements AudioStore {
  FileAudioStore(this.root, this._dio, this._repo);

  final Directory root;
  final Dio _dio;
  final PoetryRepository _repo;

  File _mp3(int id) => File('${root.path}${Platform.pathSeparator}$id.mp3');
  File _sync(int id) => File('${root.path}${Platform.pathSeparator}$id.sync.json');
  File _meta(int id) => File('${root.path}${Platform.pathSeparator}$id.meta.json');

  @override
  Future<List<DownloadedRecitation>> listDownloaded() async {
    if (!root.existsSync()) return const [];
    final out = <DownloadedRecitation>[];
    for (final f in root.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.mp3')) continue;
      final id = int.tryParse(name.substring(0, name.length - 4));
      if (id == null || !isDownloaded(id)) continue;
      final meta = _meta(id).existsSync()
          ? jsonDecode(await _meta(id).readAsString()) as Map<String, dynamic>
          : const <String, dynamic>{};
      out.add(
        DownloadedRecitation(
          id: id,
          poemId: (meta['poemId'] as int?) ?? 0,
          title: (meta['audioTitle'] as String?) ?? (meta['title'] as String?) ?? '',
          artist: (meta['audioArtist'] as String?) ?? (meta['artist'] as String?) ?? '',
          bytes: await f.length(),
        ),
      );
    }
    return out..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<List<Recitation>> downloadedFor(int poemId) async {
    final out = <Recitation>[];
    for (final d in await listDownloaded()) {
      if (d.poemId != poemId || !_meta(d.id).existsSync()) continue;
      final m = jsonDecode(await _meta(d.id).readAsString()) as Map<String, dynamic>;
      if (m.containsKey('mp3Url')) out.add(Recitation.fromJson(m));
    }
    return out;
  }

  @override
  bool isDownloaded(int id) => _mp3(id).existsSync() && _sync(id).existsSync();

  @override
  Uri mp3Uri(int id) => _mp3(id).uri;

  @override
  Future<List<SyncPoint>?> savedSync(int id) async {
    final f = _sync(id);
    return f.existsSync() ? parseSyncJson(await f.readAsString()) : null;
  }

  @override
  Future<void> download(Recitation r, {void Function(double)? onProgress}) async {
    await root.create(recursive: true);
    final part = File('${_mp3(r.id).path}.part');
    await _dio.download(
      r.mp3Url,
      part.path,
      onReceiveProgress: (got, total) => onProgress?.call(total > 0 ? got / total : 0),
      // i.ganjoor.net answers 406 to the API client's JSON-only Accept header.
      options: Options(headers: {'Accept': '*/*'}),
    );
    List<SyncPoint> sync;
    try {
      sync = await _repo.recitationSync(r.id);
    } catch (_) {
      sync = const [];
    }
    await _sync(r.id).writeAsString(jsonEncode([for (final p in sync) p.toJson()]));
    await _meta(r.id).writeAsString(jsonEncode(r.toJson()));
    await part.rename(_mp3(r.id).path);
  }

  @override
  Future<void> delete(int id) async {
    for (final f in [_mp3(id), _sync(id), _meta(id)]) {
      if (f.existsSync()) await f.delete();
    }
  }
}

/// Null in tests/platforms without a writable app directory: no offline audio.
final audioStoreProvider = Provider<AudioStore?>((ref) => null);
