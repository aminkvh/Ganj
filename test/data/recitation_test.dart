import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

String audioFx(String name) => File('test/fixtures/audio/$name').readAsStringSync();

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('poem 2130 carries recitations sorted by audioOrder', () {
    final r = poem2130().recitations;
    expect(r, isNotEmpty);
    expect(r.first.id, 2840);
    expect(r.first.artist, 'فریدون فرح‌اندوز');
    expect(r.first.mp3Url, startsWith('https://'));
    expect(r.first.inSync, isTrue);
    for (var i = 1; i < r.length; i++) {
      expect(r[i].audioOrder, greaterThanOrEqualTo(r[i - 1].audioOrder));
    }
  });

  for (final id in [1, 2840, 3879]) {
    test('recitation $id: JSON and XML agree for every verse', () {
      final json = {
        for (final p in parseSyncJson(audioFx('verses_$id.json')))
          if (p.vOrder >= 1) p.vOrder: p.ms,
      };
      final xml = {
        for (final p in parseSyncXml(audioFx('sync_$id.xml')))
          if (p.vOrder >= 1) p.vOrder: p.ms,
      };
      expect(json, isNotEmpty);
      expect(xml, json);
    });
  }

  test('XML keeps the end-of-audio marker', () {
    final pts = parseSyncXml(audioFx('sync_3879.xml'));
    expect(pts.where((p) => p.vOrder == -2).single.ms, 127200);
  });

  group('GanjoorApi.recitationSync', () {
    test('uses the verses endpoint and caches it', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = FakeAdapter({'/api/audio/verses/2840': audioFx('verses_2840.json')});
      final api = GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      );
      final pts = await api.recitationSync(2840);
      await api.recitationSync(2840);
      expect(pts.firstWhere((p) => p.vOrder == 2).ms, 7386);
      expect(adapter.requests.map((u) => u.path), ['/api/audio/verses/2840']);
    });

    test('falls back to XML when the verses endpoint fails', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = FakeAdapter({'/api/audio/file/1.xml': audioFx('sync_1.xml')});
      final api = GanjoorApi(
        dio: createDio(adapter: adapter),
        cache: HttpCache(db),
      );
      final pts = await api.recitationSync(1);
      expect(pts.firstWhere((p) => p.vOrder == 1).ms, 3926);
    });
  });
}
