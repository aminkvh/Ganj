import 'dart:convert';

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/api/dto/people.dart';
import 'package:ganj/data/db/app_db.dart';

import '../../support/fake_adapter.dart';
import 'sh_support.dart';

String shFixture(String name) => File('test/fixtures/shahnameh/$name').readAsStringSync();

/// The people endpoints, served from trimmed real responses.
Map<String, String> peopleRoutes() => {
  '/api/people/60/relations': shFixture('relations_60.json'),
  '/api/people/60/poems': shFixture('poems_60.json'),
  '/api/ganjoor/cat/39/geotag': shFixture('geotag_39.json'),
  '/api/locations': '[{"id":124,"name":"بیت‌المقدس","latitude":31.78,"longitude":35.21},{"id":8670,"name":"اروندرود","latitude":30.4,"longitude":48.1}]',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeAdapter adapter;
  late GanjoorApi api;
  late AppDb db;

  setUp(() {
    adapter = FakeAdapter(peopleRoutes());
    db = AppDb(NativeDatabase.memory());
    api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
  });
  tearDown(() => db.close());

  test('relations: kinship and ties with evidence couplets', () async {
    final r = await api.personRelations(60);
    expect(adapter.requests.single.queryParameters['evidenceLimit'], '3');
    final zal = r.rows.firstWhere((x) => x.otherName == 'زال');
    expect(zal.cat, 'R');
    expect(zal.type, 0);
    expect(zal.subjectIsPerson1, isFalse, reason: 'Zal is the parent: person1');
    expect(zal.evidenceCount, greaterThan(0));
    expect(zal.evidence.first.text, isNotEmpty);
    final rakhsh = r.rows.firstWhere((x) => x.otherName == 'رخش');
    expect(rakhsh.cat, 'A');
    expect(rakhsh.type, 99);
    expect(rakhsh.note, 'اسب رستم');
  });

  test('relations are cached', () async {
    await api.personRelations(60);
    await api.personRelations(60);
    expect(adapter.requests, hasLength(1));
  });

  test('tagged poems carry the couplet that names the person', () async {
    final poems = await api.personPoems(60);
    expect(adapter.requests.single.queryParameters['catId'], '33');
    expect(poems.first.poemId, 1403);
    expect(poems.first.coupletIndex, 11);
    expect(poems.first.coupletText, contains('غم آمد به سر'));
    expect(poems.first.fullUrl, '/ferdousi/shahname/manoochehr/sh26');
    expect(poems.last.coupletText, isNull);
  });

  test('section geotags keep only places', () async {
    final tags = await api.catPlaceTags(39);
    expect(tags.map((t) => t.locationId), [124, 8670, 8645]);
  });

  test('locations', () async {
    final l = await api.locations();
    expect(l.first.name, 'بیت‌المقدس');
    expect(l.first.lat, 31.78);
  });

  test('offline without a cached copy fails, so the UI can offer a retry', () async {
    adapter.offline = true;
    await expectLater(api.personRelations(60), throwsA(anything));
  });

  test('evidence says which book each couplet is from', () async {
    final r = PersonRelations.fromJson(jsonDecode(shFx('relations_60.json')) as Map<String, dynamic>);
    expect(r.rows.first.books, [33]);
    expect(r.rows.first.evidence.first.book, 33);
  });
}
