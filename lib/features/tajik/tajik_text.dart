import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/http_cache.dart';
import '../../data/providers.dart';

/// Tajik (Cyrillic) text of Ganjoor's poems, from Ganjoor's own public Tajik data
/// (github.com/ganjoor/ganjoor-tajik-data, served as static files by jsDelivr) — the same
/// text tj.ganjoor.net shows. Only some poems have it; the rest simply have none.
class TajikSource {
  TajikSource({required this._dio, required this._cache});

  final Dio _dio;
  final HttpCache _cache;

  static const _base = 'https://cdn.jsdelivr.net/gh/ganjoor/ganjoor-tajik-data@main/poets';
  static const _ttl = Duration(days: 30);

  /// vOrder → Tajik text for the poem at [fullUrl] (e.g. `/hafez/ghazal/sh1`); empty when
  /// the poem has no Tajik text.
  Future<Map<int, String>> poem(String fullUrl) async {
    final url = '$_base$fullUrl.json';
    final String body;
    try {
      body = await _cache.fetch('tajik:$fullUrl', _ttl, () async => (await _dio.get<String>(url)).data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const {};
      rethrow;
    }
    final verses = (jsonDecode(body) as Map<String, dynamic>)['Verses'] as List? ?? const [];
    return {
      for (final v in verses.cast<Map<String, dynamic>>())
        if (v['VOrder'] is int && v['TajikText'] is String) v['VOrder'] as int: (v['TajikText'] as String).trim(),
    };
  }
}

final tajikSourceProvider = Provider<TajikSource>(
  (ref) => TajikSource(dio: createDio(), cache: HttpCache(ref.watch(appDbProvider))),
);

/// The open poem's Tajik text (fetched only while the Tajik script option is on).
final tajikPoemProvider = FutureProvider.family<Map<int, String>, String>(
  (ref, fullUrl) => ref.watch(tajikSourceProvider).poem(fullUrl),
);
