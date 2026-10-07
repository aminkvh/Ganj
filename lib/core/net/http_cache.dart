import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import '../../data/db/app_db.dart';

/// TTL cache over the app DB. The Ganjoor API sends no cache headers, so freshness is ours to decide.
class HttpCache {
  HttpCache(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDb _db;
  final DateTime Function() _clock;

  /// Fresh hit → cached body. Otherwise [network] (stored on success);
  /// if that throws, a stale body is returned, else the error is rethrown.
  Future<String> fetch(String key, Duration ttl, Future<String> Function() network) async {
    final row = await (_db.select(_db.apiCache)..where((t) => t.key.equals(key))).getSingleOrNull();
    final cached = row == null ? null : utf8.decode(gzip.decode(row.body));
    if (row != null && _clock().difference(row.fetchedAt) < ttl) return cached!;
    try {
      final body = await network();
      await _db
          .into(_db.apiCache)
          .insertOnConflictUpdate(
            ApiCacheCompanion.insert(
              key: key,
              body: Uint8List.fromList(gzip.encode(utf8.encode(body))),
              fetchedAt: _clock(),
            ),
          );
      return body;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }
}
