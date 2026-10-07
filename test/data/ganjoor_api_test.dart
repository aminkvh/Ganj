import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';

import '../support/fake_adapter.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeAdapter adapter;
  late GanjoorApi api;
  late AppDb db;

  setUp(() {
    adapter = FakeAdapter(fixtureRoutes());
    db = AppDb(NativeDatabase.memory());
    api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
  });
  tearDown(() => db.close());

  test('poem request is lean and always asks for verses', () async {
    final p = await api.poem(2130);
    expect(p.verses, hasLength(14));
    final uri = adapter.requests.single;
    expect(uri.path, '/api/ganjoor/poem/2130');
    expect(uri.queryParameters['verseDetails'], 'true');
    expect(uri.queryParameters['comments'], 'false');
    expect(uri.queryParameters['images'], 'false');
  });

  test('never calls the heavy /page endpoint', () async {
    await api.centuries();
    await api.poet(2);
    await api.cat(24);
    await api.poem(2130);
    expect(adapter.requests.where((u) => u.path.contains('/api/ganjoor/page')), isEmpty);
  });

  test('second read is served from cache', () async {
    await api.cat(24);
    await api.cat(24);
    expect(adapter.requests, hasLength(1));
  });

  test('offline: cached poem still loads, unknown poem throws', () async {
    await api.poem(2130);
    adapter.offline = true;
    expect((await api.poem(2130)).id, 2130);
    expect(api.poem(77000), throwsA(isA<DioException>()));
  });

  test('a non-JSON 200 (captive portal) is not cached; next call refetches', () async {
    final real = adapter.routes['/api/ganjoor/poem/2130']!;
    adapter.routes['/api/ganjoor/poem/2130'] = '<html>Login to Wi-Fi</html>';
    await expectLater(api.poem(2130), throwsA(anything));
    adapter.routes['/api/ganjoor/poem/2130'] = real;
    expect((await api.poem(2130)).id, 2130);
  });

  test('sends identifying User-Agent', () {
    expect(createDio().options.headers['User-Agent'], kUserAgent);
  });
}
