import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/voice_downloader.dart';
import 'package:ganj/features/voice/app/voice_manifest.dart';

Uint8List _bytes(int seed, int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + seed) & 0xff]);

class _Source {
  _Source(this.files, this.manifest);

  final Map<String, Uint8List> files;
  final String manifest;
  late HttpServer server;
  final hits = <String, int>{};
  final ranges = <String, String?>{};
  bool hangManifest = false;
  String? dieMidFile;
  String? corrupt;
  String? stallMidFile;
  final held = <Socket>[];

  String get base => 'http://127.0.0.1:${server.port}/';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      hits[name] = (hits[name] ?? 0) + 1;
      ranges[name] = req.headers.value('range');
      final res = req.response;
      if (name == 'voice.json') {
        if (hangManifest) return;
        res.write(manifest);
        await res.close();
        return;
      }
      var data = files[name];
      if (data == null) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      if (corrupt == name) {
        data = Uint8List.fromList(data.map((b) => b ^ 1).toList());
      }
      var start = 0;
      final r = req.headers.value('range');
      if (r != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(r)!.group(1)!);
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $start-${data.length - 1}/${data.length}');
      }
      final body = data.sublist(start);
      res.contentLength = body.length;
      if (stallMidFile == name) {
        // Send half, then keep the connection open and silent.
        final s = await res.detachSocket(writeHeaders: false);
        held.add(s);
        s.add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: ${body.length}\r\n\r\n'));
        s.add(body.sublist(0, body.length ~/ 2));
        await s.flush();
        return;
      }
      if (dieMidFile == name) {
        // Raw response: promise the full length, send half, kill the socket.
        final s = await res.detachSocket(writeHeaders: false);
        s.add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: ${body.length}\r\n\r\n'));
        s.add(body.sublist(0, body.length ~/ 2));
        await s.flush();
        s.destroy();
        return;
      }
      res.add(body);
      await res.close();
    });
  }
}

void main() {
  late Directory root;
  late Map<String, Uint8List> files;
  late VoiceManifest manifest;
  late _Source hf;
  late _Source gh;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice_dl');
    files = {'a.bin': _bytes(1, 3000), 'b.bin': _bytes(2, 4000), 'c.bin': _bytes(3, 2500)};
    manifest = VoiceManifest(
      version: 'v1',
      files: [
        for (final e in files.entries)
          VoiceFile(name: e.key, size: e.value.length, sha256: sha256.convert(e.value).toString()),
      ],
    );
    hf = _Source(files, jsonEncode(manifest.toJson()));
    gh = _Source(files, jsonEncode(manifest.toJson()));
    await hf.start();
    await gh.start();
  });

  tearDown(() async {
    for (final s in [...hf.held, ...gh.held]) {
      s.destroy();
    }
    await hf.server.close(force: true);
    await gh.server.close(force: true);
    await root.delete(recursive: true);
  });

  VoiceDownloader make({Duration timeout = const Duration(seconds: 10)}) => VoiceDownloader(
    dio: Dio(),
    root: root,
    sources: {'hf': hf.base, 'github': gh.base},
    preferred: 'hf',
    timeout: timeout,
  );

  File out(String n) => File('${root.path}/v1-quality/$n');

  void expectAllPresent() {
    for (final e in files.entries) {
      expect(out(e.key).readAsBytesSync(), e.value, reason: e.key);
    }
  }

  test('fetches manifest from hf when it answers', () async {
    final m = await make().fetchManifest();
    expect(m.version, 'v1');
    expect(m.files.length, 3);
    expect(hf.hits['voice.json'], 1);
    expect(gh.hits['voice.json'], isNull);
  });

  test('uses github when hf times out', () async {
    hf.hangManifest = true;
    final d = make(timeout: const Duration(milliseconds: 400));
    final m = await d.fetchManifest();
    expect(m.version, 'v1');
    expect(gh.hits['voice.json'], 1);
    expect(await d.install(m, variant: 'quality'), 'github');
    expectAllPresent();
    expect(installedDir(root), isNotNull);
  });

  test('falls back per file when hf dies mid-file', () async {
    hf.dieMidFile = 'b.bin';
    final d = make();
    final m = await d.fetchManifest();
    expect(await d.install(m, variant: 'quality'), 'hf');
    expectAllPresent();
    expect(gh.hits['b.bin'], 1);
    // The half hf sent is kept; github resumes it (identical bytes, sha256 is the guard).
    expect(gh.ranges['b.bin'], matches(RegExp(r'^bytes=[1-9]\d*-$')));
    expect(gh.hits['a.bin'], isNull);
    expect(installedDir(root)!.uri.pathSegments.where((s) => s.isNotEmpty).last, 'v1-quality');
  });

  test('falls back per file when hf stalls mid-file', () async {
    hf.stallMidFile = 'b.bin';
    final d = make(timeout: const Duration(milliseconds: 500));
    final m = await d.fetchManifest();
    await d.install(m, variant: 'quality');
    expectAllPresent();
    expect(gh.hits['b.bin'], 1);
    expect(gh.ranges['b.bin'], 'bytes=2000-');
  });

  test('hf unreachable, github stalls mid-file: the .part survives and the next install resumes it', () async {
    gh.stallMidFile = 'b.bin';
    final d = VoiceDownloader(
      dio: Dio(),
      root: root,
      sources: {'hf': 'http://127.0.0.1:1/', 'github': gh.base},
      preferred: 'hf',
      timeout: const Duration(milliseconds: 500),
    );
    final m = await d.fetchManifest();
    await expectLater(
      d.install(m, variant: 'quality'),
      throwsA(isA<VoiceDownloadError>().having((e) => e.kind, 'kind', VoiceDownloadFailure.offline)),
    );
    final part = File('${root.path}/v1-quality/b.bin.part');
    expect(part.existsSync(), isTrue);
    expect(part.lengthSync(), 2000);
    expect(installedDir(root), isNull);

    gh.stallMidFile = null;
    gh.ranges.clear();
    await d.install(m, variant: 'quality');
    expect(gh.ranges['b.bin'], 'bytes=2000-');
    expectAllPresent();
    expect(part.existsSync(), isFalse);
  });

  test('a complete .part is verified and renamed without any request', () async {
    final dir = Directory('${root.path}/v1-quality')..createSync(recursive: true);
    File('${dir.path}/b.bin.part').writeAsBytesSync(files['b.bin']!);
    final d = make();
    await d.install(await d.fetchManifest(), variant: 'quality');
    expect(hf.hits['b.bin'], isNull);
    expect(gh.hits['b.bin'], isNull);
    expectAllPresent();
    expect(File('${dir.path}/b.bin.part').existsSync(), isFalse);
  });

  test('a complete but corrupt .part is refetched from zero', () async {
    final dir = Directory('${root.path}/v1-quality')..createSync(recursive: true);
    File('${dir.path}/b.bin.part').writeAsBytesSync(Uint8List(files['b.bin']!.length));
    final d = make();
    await d.install(await d.fetchManifest(), variant: 'quality');
    expect(hf.hits['b.bin'], 1);
    expect(hf.ranges['b.bin'], isNull);
    expectAllPresent();
  });

  test('manifest with an unsafe version or file name is rejected', () {
    for (final bad in ['', '.', '..', 'a/b', r'a\b', '../x', 'x..y']) {
      expect(
        () => VoiceManifest.fromJson({
          'version': 'v1',
          'files': [
            {'name': bad, 'size': 1, 'sha256': 'ab'},
          ],
        }),
        throwsFormatException,
        reason: 'name "$bad"',
      );
      expect(
        () => VoiceManifest.fromJson({'version': bad, 'files': []}),
        throwsFormatException,
        reason: 'version "$bad"',
      );
    }
  });

  test('unsafe manifest on hf is treated as a failed source', () async {
    final evil = jsonEncode({
      'version': 'v1',
      'files': [
        {'name': '../evil.bin', 'size': 1, 'sha256': 'ab'},
      ],
    });
    final bad = _Source(files, evil);
    await bad.start();
    addTearDown(() => bad.server.close(force: true));
    final d = VoiceDownloader(dio: Dio(), root: root, sources: {'bad': bad.base, 'github': gh.base}, preferred: 'bad');
    final m = await d.fetchManifest();
    expect(m.files.first.name, 'a.bin');
    expect(bad.hits['voice.json'], 1);
    expect(gh.hits['voice.json'], 1);
  });

  test('resumes a .part with Range', () async {
    final dir = Directory('${root.path}/v1-quality')..createSync(recursive: true);
    File('${dir.path}/b.bin.part').writeAsBytesSync(files['b.bin']!.sublist(0, 2000));
    final d = make();
    final m = await d.fetchManifest();
    await d.install(m, variant: 'quality');
    expect(hf.ranges['b.bin'], 'bytes=2000-');
    expectAllPresent();
    expect(File('${dir.path}/b.bin.part').existsSync(), isFalse);
  });

  test('restarts when the server ignores Range and answers 200', () async {
    final dir = Directory('${root.path}/v1-quality')..createSync(recursive: true);
    // A bogus part: if it were kept and appended to, the checksum would fail.
    File('${dir.path}/c.bin.part').writeAsBytesSync(Uint8List(100));
    final plain = _Source(files, jsonEncode(manifest.toJson()));
    await plain.start();
    addTearDown(() => plain.server.close(force: true));
    // Wrap: a server that never honors Range.
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => srv.close(force: true));
    srv.listen((req) async {
      final n = req.uri.pathSegments.last;
      req.response.write(n == 'voice.json' ? plain.manifest : '');
      if (n != 'voice.json') req.response.add(files[n]!);
      await req.response.close();
    });
    final d = VoiceDownloader(dio: Dio(), root: root, sources: {'x': 'http://127.0.0.1:${srv.port}/'});
    await d.install(await d.fetchManifest(), variant: 'quality');
    expectAllPresent();
  });

  test('checksum mismatch on both sources throws checksum', () async {
    hf.corrupt = 'b.bin';
    gh.corrupt = 'b.bin';
    final d = make();
    final m = await d.fetchManifest();
    await expectLater(
      d.install(m, variant: 'quality'),
      throwsA(isA<VoiceDownloadError>().having((e) => e.kind, 'kind', VoiceDownloadFailure.checksum)),
    );
    expect(installedDir(root), isNull);
  });

  test('half-finished download is not installed', () async {
    final cancel = CancelToken();
    final d = make();
    final m = await d.fetchManifest();
    await expectLater(
      d.install(
        m,
        variant: 'quality',
        cancel: cancel,
        onProgress: (got, total) {
          if (got >= files['a.bin']!.length) cancel.cancel();
        },
      ),
      throwsA(isA<VoiceDownloadError>().having((e) => e.kind, 'kind', VoiceDownloadFailure.cancelled)),
    );
    expect(installedDir(root), isNull);
    expect(out('a.bin').existsSync(), isTrue);

    hf.hits.clear();
    await d.install(m, variant: 'quality');
    expect(hf.hits['a.bin'], isNull);
    expect(hf.hits['b.bin'], 1);
    expect(hf.hits['c.bin'], 1);
    expectAllPresent();
    expect(installedDir(root), isNotNull);
  });

  group('variants', () {
    late Map<String, Uint8List> all;
    late VoiceManifest v2;
    late _Source src;

    VoiceFile vf(String n) => VoiceFile(name: n, size: all[n]!.length, sha256: sha256.convert(all[n]!).toString());

    setUp(() async {
      all = {...files, 'enc_fast.bin': _bytes(4, 1000), 'enc_q.bin': _bytes(5, 2000)};
      v2 = VoiceManifest(
        version: 'v2',
        files: [vf('a.bin'), vf('b.bin')],
        variants: {
          'fast': [vf('enc_fast.bin')],
          'quality': [vf('enc_q.bin')],
        },
      );
      src = _Source(all, jsonEncode(v2.toJson()));
      await src.start();
    });

    tearDown(() => src.server.close(force: true));

    VoiceDownloader one() => VoiceDownloader(dio: Dio(), root: root, sources: {'x': src.base});

    test('v2 manifest sizes per variant', () async {
      final m = await one().fetchManifest();
      expect(m.variants.keys, containsAll(['fast', 'quality']));
      expect(m.sizeOf('fast'), 3000 + 4000 + 1000);
      expect(m.sizeOf('quality'), 3000 + 4000 + 2000);
      expect(m.filesFor('fast').map((f) => f.name), ['a.bin', 'b.bin', 'enc_fast.bin']);
      expect(() => m.filesFor('nope'), throwsArgumentError);
    });

    test('v1 manifest reads as quality', () {
      final m = VoiceManifest.fromJson({'version': 'v1', 'files': manifest.toJson()['files']});
      expect(m.variants.keys, ['quality']);
      expect(m.variants['quality'], isEmpty);
      expect(m.filesFor('quality').length, 3);
      expect(m.sizeOf('quality'), m.totalBytes);
    });

    test('unsafe variant file name is rejected', () {
      for (final bad in ['', '..', 'a/b', r'a\b', 'x..y']) {
        expect(
          () => VoiceManifest.fromJson({
            'version': 'v2',
            'files': [],
            'variants': {
              'fast': [
                {'name': bad, 'size': 1, 'sha256': 'ab'},
              ],
            },
          }),
          throwsFormatException,
          reason: 'file "$bad"',
        );
      }
    });

    test('only the keys fast and quality are accepted in variants', () {
      final m = VoiceManifest.fromJson({
        'version': 'v2',
        'files': [],
        'variants': {
          'fast': [
            {'name': 'f.bin', 'size': 1, 'sha256': 'ab'},
          ],
          'turbo': [
            {'name': 't.bin', 'size': 1, 'sha256': 'ab'},
          ],
          '..': [],
        },
      });
      expect(m.variants.keys, ['fast']);
      expect(kFastVariant, 'fast');
    });

    test('variants absent or without a usable key read as quality with the shared files only', () {
      for (final v in <Object?>[
        null,
        <String, Object?>{},
        {'turbo': []},
        {'a/b': []},
      ]) {
        final m = VoiceManifest.fromJson({'version': 'v2', 'files': manifest.toJson()['files'], 'variants': ?v});
        expect(m.variants.keys, ['quality'], reason: '$v');
        expect(m.variants['quality'], isEmpty);
        expect(m.sizeOf('quality'), m.totalBytes);
      }
    });

    test('installedDir prefers the newest installedAt over the lexicographic last', () {
      void mark(String name, Map<String, dynamic> j) {
        final d = Directory('${root.path}/$name')..createSync(recursive: true);
        File('${d.path}/installed.json').writeAsStringSync(jsonEncode(j));
      }

      mark('v2-quality', {
        'version': 'v2',
        'variant': 'quality',
        'files': [],
        'installedAt': '2026-11-01T10:00:00.000Z',
      });
      mark('v2-fast', {'version': 'v2', 'variant': 'fast', 'files': [], 'installedAt': '2026-11-08T10:00:00.000Z'});
      expect(installedDir(root)!.path.endsWith('v2-fast'), isTrue);
    });

    test('installedDir without installedAt keeps the lexicographic rule; a stamped folder beats an unstamped one', () {
      void mark(String name, [String? at]) {
        final d = Directory('${root.path}/$name')..createSync(recursive: true);
        File('${d.path}/installed.json').writeAsStringSync(jsonEncode({'version': 'v', 'installedAt': ?at}));
      }

      mark('v1');
      mark('v2-fast');
      expect(installedDir(root)!.path.endsWith('v2-fast'), isTrue);
      mark('v1', '2026-11-08T10:00:00.000Z');
      expect(installedDir(root)!.path.endsWith('v1'), isTrue);
    });

    test('install records installedAt', () async {
      final d = one();
      await d.install(await d.fetchManifest(), variant: 'fast');
      final j = jsonDecode(File('${root.path}/v2-fast/installed.json').readAsStringSync()) as Map<String, dynamic>;
      expect(DateTime.tryParse(j['installedAt'] as String), isNotNull);
    });

    test('install fast puts shared + fast files in version-fast and records the variant', () async {
      final d = one();
      final m = await d.fetchManifest();
      var total = 0;
      await d.install(m, variant: 'fast', onProgress: (g, t) => total = t);
      expect(total, 8000);
      final dir = Directory('${root.path}/v2-fast');
      expect(dir.existsSync(), isTrue);
      expect(File('${dir.path}/enc_fast.bin').readAsBytesSync(), all['enc_fast.bin']);
      expect(File('${dir.path}/a.bin').existsSync(), isTrue);
      expect(File('${dir.path}/enc_q.bin').existsSync(), isFalse);
      expect(src.hits['enc_q.bin'], isNull);
      final j = jsonDecode(File('${dir.path}/installed.json').readAsStringSync()) as Map<String, dynamic>;
      expect(j['variant'], 'fast');
      expect(j['version'], 'v2');
      expect(installedDir(root)!.uri.pathSegments.where((s) => s.isNotEmpty).last, 'v2-fast');
    });

    test('phase-1 install reads as quality', () async {
      final d = Directory('${root.path}/v1')..createSync(recursive: true);
      File('${d.path}/installed.json').writeAsStringSync(jsonEncode(manifest.toJson()));
      expect(installedDir(root)!.uri.pathSegments.where((s) => s.isNotEmpty).last, 'v1');
      expect(installedVariant(installedDir(root)!), 'quality');
    });

    test('installedVariant reads the recorded variant', () async {
      final d = one();
      await d.install(await d.fetchManifest(), variant: 'fast');
      expect(installedVariant(installedDir(root)!), 'fast');
    });
  });

  test('all sources offline throws offline', () async {
    final d = VoiceDownloader(
      dio: Dio(),
      root: root,
      sources: const {'x': 'http://127.0.0.1:1/'},
      timeout: const Duration(milliseconds: 500),
    );
    await expectLater(
      d.fetchManifest(),
      throwsA(isA<VoiceDownloadError>().having((e) => e.kind, 'kind', VoiceDownloadFailure.offline)),
    );
  });
}
