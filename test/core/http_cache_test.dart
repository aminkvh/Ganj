import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/db/app_db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DateTime now;
  late AppDb db;
  late HttpCache cache;
  const week = Duration(days: 7);

  setUp(() {
    now = DateTime(2026, 1, 1);
    db = AppDb(NativeDatabase.memory());
    cache = HttpCache(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('fresh entry is served without hitting the network', () async {
    var calls = 0;
    Future<String> net() async => 'v${++calls}';
    expect(await cache.fetch('k', week, net), 'v1');
    expect(await cache.fetch('k', week, net), 'v1');
    expect(calls, 1);
  });

  test('expired entry is refetched', () async {
    var calls = 0;
    Future<String> net() async => 'v${++calls}';
    await cache.fetch('k', week, net);
    now = now.add(const Duration(days: 8));
    expect(await cache.fetch('k', week, net), 'v2');
  });

  test('network failure falls back to stale entry', () async {
    await cache.fetch('k', week, () async => 'old');
    now = now.add(const Duration(days: 30));
    expect(await cache.fetch('k', week, () async => throw StateError('offline')), 'old');
  });

  test('network failure with nothing cached rethrows', () async {
    expect(cache.fetch('none', week, () async => throw StateError('offline')), throwsStateError);
  });

  test('round-trips Persian text through gzip', () async {
    await cache.fetch('fa', week, () async => '{"t":"اَلا یا اَیُّهَا السّاقی"}');
    expect(await cache.fetch('fa', week, () async => 'x'), '{"t":"اَلا یا اَیُّهَا السّاقی"}');
  });
}
