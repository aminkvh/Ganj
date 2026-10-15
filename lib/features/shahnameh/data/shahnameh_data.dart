import 'dart:convert';
import 'dart:io' show gzip;

import 'package:dio/dio.dart';

import '../../../core/net/http_cache.dart';

/// Where the Shahnameh's people data is published every month (by the repository's
/// "Shahnameh data" workflow, from Ganjoor's API), so readers get Ganjoor's fixes without
/// waiting for an app release.
const kShahnamehDataUrl = 'https://github.com/aminkvh/Ganj/releases/download/shahnameh-data/shahnameh.json.gz';

/// The data format this app reads; tool/shahnameh_snapshot.dart writes it. A file in another
/// format (from a newer tool) is left alone and the app keeps what it has.
const kShahnamehDataSchema = 1;

/// The published file is checked at most this often.
const kShahnamehDataCheck = Duration(days: 7);

/// Is [text] Shahnameh data this app can use?
bool usableShahnamehData(String text) {
  try {
    final g = jsonDecode(text) as Map<String, dynamic>;
    return g['schema'] == kShahnamehDataSchema &&
        (g['sections'] as List).isNotEmpty &&
        (g['people'] as List).isNotEmpty &&
        g['builtAt'] is String;
  } catch (_) {
    return false;
  }
}

/// When the data was built (ISO date or date-time; later sorts after earlier).
String shahnamehDataBuiltAt(String text) => (jsonDecode(text) as Map<String, dynamic>)['builtAt'] as String;

class ShahnamehDataSource {
  ShahnamehDataSource({required this._dio, required this._cache});

  final Dio _dio;
  final HttpCache _cache;

  /// The last published copy downloaded, however old; null if none yet.
  Future<String?> saved() => _cache.peek(kShahnamehDataUrl);

  /// The published copy: from the cache when checked within a week, else downloaded. Only
  /// usable data is ever saved; offline with nothing saved, this throws.
  Future<String> latest() => _cache.fetch(kShahnamehDataUrl, kShahnamehDataCheck, () async {
    final r = await _dio.get<List<int>>(
      kShahnamehDataUrl,
      options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
    );
    final text = utf8.decode(gzip.decode(r.data!));
    if (!usableShahnamehData(text)) throw const FormatException('unusable Shahnameh data');
    return text;
  });
}
