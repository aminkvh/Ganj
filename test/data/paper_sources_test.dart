import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';

import '../support/fake_adapter.dart';
import 'extras_test.dart' show ex;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('paper sources: manuscripts, printed editions and the text\'s own source', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakeAdapter({'/api/ganjoor/cat/9/papersources': ex('papersources_9.json')});
    final api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
    final sources = await api.paperSources(9);
    expect(sources, hasLength(5));
    final text = sources.where((s) => s.textSource).single;
    expect(text.title, startsWith('دیوان حافظ به اهتمام محمد قزوینی'));
    expect(text.manuscript, isTrue);
    expect(text.url, startsWith('https://museum.ganjoor.net/items/'));
    final printed = sources.where((s) => !s.manuscript).toList();
    expect(printed, hasLength(2));
    expect(printed.first.url, startsWith('https://naskban.ir/'));
    expect(printed.first.thumb, startsWith('https://i.naskban.ir/'));
    expect(sources.where((s) => s.manuscript && !s.textSource), hasLength(2));
  });
}
