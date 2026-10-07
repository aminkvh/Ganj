import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/packs/local_poetry.dart';
import 'package:ganj/data/packs/pack_installer.dart';
import 'package:ganj/data/repo/poetry_repository.dart';
import 'package:ganj/features/search/search_service.dart';
import 'package:integration_test/integration_test.dart';

/// M3 live check: real Hafez pack from i.ganjoor.net, local search vs Ganjoor's search, offline reading.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live: install Hafez pack, search offline, read offline', (tester) async {
    await tester.runAsync(() async {
      final db = AppDb(NativeDatabase.memory());
      final api = GanjoorApi(dio: createDio(), cache: HttpCache(db));
      final packs = await api.packCatalog();
      final hafez = packs.firstWhere((p) => p.poetId == 2);

      final sw = Stopwatch()..start();
      final r = await PackInstaller(db, createDio(), Directory.systemTemp).install(hafez);
      debugPrint(
        '[e2e-packs] installed ${hafez.name}: ${r.poems} poems, ${r.verses} verses in ${sw.elapsedMilliseconds} ms',
      );
      expect(r.poems, 695);
      expect(r.verses, 10607);

      final service = SearchService(db, api);
      final local = await service.searchLocal('ساقی', poetId: 2);
      var localCount = local.hits.length;
      var page = 1;
      var more = local.hasMore;
      while (more) {
        final next = await service.searchLocal('ساقی', poetId: 2, page: ++page);
        localCount += next.hits.length;
        more = next.hasMore;
      }
      final online = await service.searchOnline('ساقی', poetId: 2);
      debugPrint('[e2e-packs] «ساقی» local=$localCount online=${online.total}');
      expect(localCount, inInclusiveRange((online.total * 0.85).floor(), (online.total * 1.15).ceil()));

      // Offline: same DB, unreachable API → the pack serves poet, category and poem.
      final offline = PoetryRepository(
        GanjoorApi(
          dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9', connectTimeout: const Duration(seconds: 2))),
          cache: HttpCache(db),
        ),
        local: LocalPoetry(db),
      );
      final poem = await offline.poem(2131);
      expect(poem.verses, isNotEmpty);
      expect(poem.previous?.id, 2130);
      final apiPoem = await api.poem(2131);
      expect([for (final v in poem.verses) v.text], [for (final v in apiPoem.verses) v.text]);
      expect([for (final v in poem.verses) v.coupletIndex], [for (final v in apiPoem.verses) v.coupletIndex]);
      final cat = await offline.cat(24);
      debugPrint('[e2e-packs] offline cat ${cat.cat.title}: ${cat.cat.poems.length} poems; poem 2131 ok');
      final size = await db.customSelect('PRAGMA page_count').getSingle();
      debugPrint('[e2e-packs] db pages: ${size.read<int>('page_count')}');
      await db.close();
    });
  });
}
