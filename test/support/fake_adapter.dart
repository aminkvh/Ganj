import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'fixtures.dart';

/// Like i.ganjoor.net: non-JSON files refuse a JSON-only Accept header (HTTP 406).
final _nonJsonFile = RegExp(r'\.(mp3|xml|zip)$');

/// Serves bodies by request path; records every request; can simulate being offline.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  final Map<String, String> routes;

  /// Binary bodies (zips, mp3s) by path.
  final binary = <String, List<int>>{};

  /// Extra response headers by path (e.g. paging-headers).
  final headers = <String, Map<String, String>>{};
  final requests = <Uri>[];
  bool offline = false;

  /// Simulated latency (a slow or hanging network).
  Duration delay = Duration.zero;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o.uri);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (offline) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    final accept = '${o.headers['Accept'] ?? ''}';
    if (_nonJsonFile.hasMatch(o.uri.path) && accept.contains('application/json')) {
      return ResponseBody.fromString('', 406);
    }
    final bin = binary[o.uri.path];
    if (bin != null) return ResponseBody.fromBytes(bin, 200);
    final body = routes[o.uri.path];
    if (body == null) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        for (final e in (headers[o.uri.path] ?? const {}).entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, String> fixtureRoutes() => {
  '/api/ganjoor/centuries': fx('centuries'),
  '/api/ganjoor/poet/2': fx('poet_2'),
  '/api/ganjoor/cat/24': fx('cat_24'),
  '/api/ganjoor/poem/2130': fx('poem_2130'),
  '/api/ganjoor/poem/77000': fx('poem_77000'),
};
