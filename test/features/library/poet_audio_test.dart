import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/features/library/poet_audio.dart';
import 'package:ganj/features/player/audio_store.dart';

import '../../support/fake_adapter.dart';

Map<String, dynamic> rec(int id, int poemId, int size) => {
  'id': id,
  'poemId': poemId,
  'audioTitle': 't$id',
  'audioArtist': 'a$id',
  'mp3Url': 'https://i.ganjoor.net/a/$id.mp3',
  'mp3SizeInBytes': size,
  'audioOrder': 1,
  'inSyncWithText': true,
};

String catJson(int id, List<int> children) => jsonEncode({
  'poet': {'id': 2, 'name': 'حافظ', 'rootCatId': 9},
  'cat': {
    'id': id,
    'title': 'c$id',
    'children': [
      for (final c in children) {'id': c, 'title': 'c$c', 'fullUrl': '/x/$c'},
    ],
  },
});

/// Records peak concurrency of downloads.
class CountingStore implements AudioStore {
  int running = 0, peak = 0;
  final done = <int>[];

  @override
  Future<void> download(Recitation r, {void Function(double)? onProgress}) async {
    running++;
    if (running > peak) peak = running;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    done.add(r.id);
    running--;
  }

  @override
  bool isDownloaded(int id) => done.contains(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('plans every category recursively and sums sizes; downloads one at a time', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakeAdapter({
      '/api/ganjoor/cat/9': catJson(9, [24, 25]),
      '/api/ganjoor/cat/24': catJson(24, []),
      '/api/ganjoor/cat/25': catJson(25, []),
      '/api/audio/cattop1/9': jsonEncode([]),
      '/api/audio/cattop1/24': jsonEncode([rec(1, 100, 1000), rec(2, 101, 2000)]),
      '/api/audio/cattop1/25': jsonEncode([rec(3, 102, 500)]),
    });
    final api = GanjoorApi(
      dio: createDio(adapter: adapter),
      cache: HttpCache(db),
    );
    final plan = await planPoetAudio(api, 9);
    expect(plan.recitations.map((r) => r.id), [1, 2, 3]);
    expect(plan.totalBytes, 3500);

    final store = CountingStore()..done.add(2); // already downloaded → skipped
    final progress = <int>[];
    await downloadPlan(plan, store, onItem: (done, total) => progress.add(done));
    expect(store.peak, 1);
    expect(store.done, containsAll([1, 2, 3]));
    expect(progress.last, 3);
  });

  test('cancel stops the queue', () async {
    final plan = PoetAudioPlan([for (var i = 1; i <= 5; i++) Recitation.fromJson(rec(i, i, 10))]);
    final store = CountingStore();
    final token = CancelToken();
    await downloadPlan(
      plan,
      store,
      cancel: token,
      onItem: (done, _) {
        if (done == 2) token.cancel();
      },
    );
    expect(store.done, hasLength(2));
  });
}
