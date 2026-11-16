import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../api/dto/cat.dart';
import '../api/dto/poem.dart';
import '../api/dto/poet.dart';
import '../api/dto/recitation.dart';
import '../api/ganjoor_api.dart';
import '../api/ganjoor_static.dart';
import '../packs/local_poetry.dart';

/// The only data entry point for the UI: API + TTL cache (+ bundled seed),
/// with installed poet packs as the offline fallback and Ganjoor's static data copy as the
/// backup when Ganjoor's server fails.
class PoetryRepository {
  PoetryRepository(
    this._api, {
    this._local,
    this._offlineRecitations,
    this._staticCopy,
    this.packTimeout = const Duration(seconds: 4),
    Future<String> Function()? loadSeed,
  }) : _loadSeed = loadSeed ?? (() => rootBundle.loadString('assets/seed/centuries.json'));

  final GanjoorApi _api;
  final LocalPoetry? _local;
  final GanjoorStatic? _staticCopy;

  /// With a pack installed, how long the API gets before the pack answers instead.
  final Duration packTimeout;

  /// Recitations downloaded on this device, merged into poems served offline from packs.
  final Future<List<Recitation>> Function(int poemId)? _offlineRecitations;
  final Future<String> Function() _loadSeed;

  /// True when the last poet list came from the bundled copy (no network on first start).
  bool centuriesFromSeed = false;

  Future<List<Century>> centuries() async {
    try {
      final live = await _api.centuries();
      centuriesFromSeed = false;
      return live;
    } catch (_) {
      centuriesFromSeed = true;
      final list = jsonDecode(await _loadSeed()) as List;
      return [for (final c in list) Century.fromJson(c as Map<String, dynamic>)];
    }
  }

  /// API (cache-first) for full detail. When the item is in an installed pack, the API
  /// only gets [packTimeout] — a dead or hanging network falls back to the pack quickly.
  /// When Ganjoor's server fails and no pack has the item, the static copy answers; if that
  /// fails too (offline), the API's error stands.
  Future<T> _withPack<T>(
    Future<T> Function() api,
    Future<T?> Function(LocalPoetry l) pack,
    Future<T> Function(GanjoorStatic s) fromCopy,
  ) async {
    final l = _local;
    final fromPack = l == null ? null : await pack(l);
    try {
      final online = api();
      return await (fromPack == null ? online : online.timeout(packTimeout));
    } catch (e, st) {
      if (fromPack != null) return fromPack;
      final copy = _staticCopy;
      if (copy == null || !_serverTrouble(e)) rethrow;
      try {
        return await fromCopy(copy);
      } catch (_) {
        Error.throwWithStackTrace(e, st); // the API's error, as without a copy
      }
    }
  }

  /// A failed connection, timeout or server error; not a «no such item» answer.
  static bool _serverTrouble(Object e) {
    if (e is! DioException) return e is FormatException || e is TimeoutException;
    final code = e.response?.statusCode;
    return code == null || code >= 500 || code == 408 || code == 429;
  }

  Future<PoetCat> poet(int id) => _withPack(() => _api.poet(id), (l) => l.poet(id), (s) => s.poet(id));
  Future<PoetCat> cat(int id) => _withPack(() => _api.cat(id), (l) => l.cat(id), (s) => s.cat(id));
  Future<Poem> poem(int id) => _withPack(() => _api.poem(id), (l) async {
    final p = await l.poem(id);
    final recs = p == null ? const <Recitation>[] : await _offlineRecitations?.call(id) ?? const <Recitation>[];
    return p == null || recs.isEmpty ? p : p.copyWith(recitations: recs);
  }, (s) => s.poem(id));
  Future<List<SyncPoint>> recitationSync(int recitationId) => _api.recitationSync(recitationId);
}
