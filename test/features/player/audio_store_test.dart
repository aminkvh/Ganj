import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/audio_store.dart';
import 'package:ganj/features/player/download_button.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_adapter.dart';
import '../../support/fake_audio_backend.dart';
import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';
import '../../support/test_app.dart';

/// In-memory store for widget tests.
class MemoryAudioStore implements AudioStore {
  final done = <int>{};

  @override
  bool isDownloaded(int id) => done.contains(id);

  @override
  Uri mp3Uri(int id) => Uri.file('/fake/$id.mp3');

  @override
  Future<List<SyncPoint>?> savedSync(int id) async => null;

  @override
  Future<void> download(Recitation r, {void Function(double)? onProgress}) async {
    onProgress?.call(1);
    done.add(r.id);
  }

  @override
  Future<void> delete(int id) async => done.remove(id);

  @override
  Future<List<Recitation>> downloadedFor(int poemId) async => const [];

  @override
  Future<List<DownloadedRecitation>> listDownloaded() async => [
    for (final id in done)
      DownloadedRecitation(id: id, poemId: 2130, title: 'غزل شمارهٔ ۱', artist: 'فریدون فرح‌اندوز', bytes: 727452),
  ];
}

void main() {
  late Directory dir;
  late FixtureRepository repo;
  final rec = poem2130().recitations.first;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ganj_audio_');
    repo = FixtureRepository();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FileAudioStore store() =>
      FileAudioStore(dir, createDio(adapter: FakeAdapter({'/a/2130-ff.mp3': 'ID3-fake-mp3-bytes'})), repo);

  test('download writes mp3 and sync; delete removes both', () async {
    final s = store();
    expect(s.isDownloaded(rec.id), isFalse);
    double? last;
    await s.download(rec, onProgress: (v) => last = v);
    expect(s.isDownloaded(rec.id), isTrue);
    expect(File.fromUri(s.mp3Uri(rec.id)).readAsStringSync(), 'ID3-fake-mp3-bytes');
    expect((await s.savedSync(rec.id))!.firstWhere((p) => p.vOrder == 3).ms, 15486);
    expect(last, isNotNull);
    await s.delete(rec.id);
    expect(s.isDownloaded(rec.id), isFalse);
    expect(await s.savedSync(rec.id), isNull);
  });

  test('downloaded recitations of a poem come back as full records', () async {
    final s = store();
    await s.download(rec);
    final list = await s.downloadedFor(2130);
    expect(list.single.id, rec.id);
    expect(list.single.mp3Url, rec.mp3Url);
    expect(list.single.inSync, isTrue);
    expect(await s.downloadedFor(1), isEmpty);
  });

  test('lists downloads with reciter, poem and size', () async {
    final s = store();
    expect(await s.listDownloaded(), isEmpty);
    await s.download(rec);
    final list = await s.listDownloaded();
    expect(list.single.id, rec.id);
    expect(list.single.artist, 'فریدون فرح‌اندوز');
    expect(list.single.poemId, 2130);
    expect(list.single.bytes, 'ID3-fake-mp3-bytes'.length);
  });

  test('downloaded recitation plays from file with saved sync while offline', () async {
    final s = store();
    await s.download(rec);
    repo.fail = true; // API unreachable
    final backend = FakeAudioBackend();
    final c = ProviderContainer(
      overrides: [
        audioBackendProvider.overrideWithValue(backend),
        poetryRepositoryProvider.overrideWithValue(repo),
        audioStoreProvider.overrideWithValue(s),
      ],
    );
    addTearDown(c.dispose);
    await c.read(playerProvider.notifier).play(poem2130(), rec);
    expect(backend.loaded.single.scheme, 'file');
    expect(await c.read(playerProvider.notifier).seekToVOrder(3), isTrue);
    expect(backend.seeks.last, const Duration(milliseconds: 15486));
  });

  test('a download saved without timings still highlights once the API is reachable', () async {
    final s = store();
    repo.fail = true; // sync fetch fails during download → empty timings saved
    await s.download(rec);
    expect(await s.savedSync(rec.id), isEmpty);
    repo.fail = false;
    final c = ProviderContainer(
      overrides: [
        audioBackendProvider.overrideWithValue(FakeAudioBackend()),
        poetryRepositoryProvider.overrideWithValue(repo),
        audioStoreProvider.overrideWithValue(s),
      ],
    );
    addTearDown(c.dispose);
    await c.read(playerProvider.notifier).play(poem2130(), rec);
    expect(await c.read(playerProvider.notifier).seekToVOrder(3), isTrue);
  });

  testWidgets('download button toggles between download and downloaded', (tester) async {
    final prefs = await mockPrefs();
    final mem = MemoryAudioStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioStoreProvider.overrideWithValue(mem)],
        child: testApp(
          Scaffold(
            body: Center(child: DownloadButton(recitation: rec)),
          ),
          prefs: prefs,
        ),
      ),
    );
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('rec-dl-${rec.id}')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('rec-dl-${rec.id}')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });
}
