import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_data.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_providers.dart';

import '../../support/fake_adapter.dart';

/// The Shahnameh's people data is published every two weeks on GitHub; the app opens with the
/// best copy it has and picks up a newer one in the background.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final bundled = File('assets/seed/shahnameh/generated.json').readAsStringSync();
  final dataPath = Uri.parse(kShahnamehDataUrl).path;

  /// The bundled data with a later date and Rostam renamed, as the published file would carry.
  List<int> published({
    String builtAt = '2099-01-01',
    int schema = kShahnamehDataSchema,
    String rostam = 'رستمِ تازه',
  }) {
    final g = jsonDecode(bundled) as Map<String, dynamic>;
    g['builtAt'] = builtAt;
    g['schema'] = schema;
    for (final p in g['people'] as List) {
      if ((p as Map)['id'] == 60) p['name'] = rostam;
    }
    return gzip.encode(utf8.encode(jsonEncode(g)));
  }

  late AppDb db;
  setUp(() => db = AppDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container(FakeAdapter adapter) {
    final c = ProviderContainer(
      overrides: [
        shahnamehDataSourceProvider.overrideWithValue(
          ShahnamehDataSource(
            dio: createDio(adapter: adapter),
            cache: HttpCache(db),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Lets the background check run.
  Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 200));

  test('a newer published file replaces the bundled data', () async {
    final adapter = FakeAdapter({})..binary[dataPath] = published();
    final c = container(adapter);
    final sub = c.listen(shahnamehWorldProvider, (_, _) {});
    addTearDown(sub.close);
    expect((await c.read(shahnamehWorldProvider.future)).people[60]!.name, 'رستم');
    await idle();
    expect(c.read(shahnamehWorldProvider).value!.people[60]!.name, 'رستمِ تازه');
  });

  test('next time, the saved copy opens straight away, even offline', () async {
    final online = FakeAdapter({})..binary[dataPath] = published();
    final first = container(online);
    final sub = first.listen(shahnamehWorldProvider, (_, _) {});
    await first.read(shahnamehWorldProvider.future);
    await idle();
    sub.close();

    final offline = FakeAdapter({})..offline = true;
    final again = container(offline);
    expect((await again.read(shahnamehWorldProvider.future)).people[60]!.name, 'رستمِ تازه');
  });

  for (final (what, bytes) in [
    ('an older file', () => published(builtAt: '2000-01-01')),
    ('a file in a format this app does not know', () => published(schema: kShahnamehDataSchema + 1)),
    ('a broken file', () => utf8.encode('not gzip')),
  ]) {
    test('$what is ignored', () async {
      final adapter = FakeAdapter({})..binary[dataPath] = bytes();
      final c = container(adapter);
      final sub = c.listen(shahnamehWorldProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(shahnamehWorldProvider.future);
      await idle();
      expect(c.read(shahnamehWorldProvider).value!.people[60]!.name, 'رستم');
    });
  }

  test('offline with nothing saved: the bundled data, no error', () async {
    final c = container(FakeAdapter({})..offline = true);
    final sub = c.listen(shahnamehWorldProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(shahnamehWorldProvider.future);
    await idle();
    expect(c.read(shahnamehWorldProvider).hasError, isFalse);
    expect(c.read(shahnamehWorldProvider).value!.people[60]!.name, 'رستم');
  });

  test('the check asks GitHub at most once a week', () async {
    final adapter = FakeAdapter({})..binary[dataPath] = published();
    for (var i = 0; i < 2; i++) {
      final c = container(adapter);
      final sub = c.listen(shahnamehWorldProvider, (_, _) {});
      await c.read(shahnamehWorldProvider.future);
      await idle();
      sub.close();
    }
    expect(adapter.requests.where((u) => u.path == dataPath), hasLength(1));
  });
}
