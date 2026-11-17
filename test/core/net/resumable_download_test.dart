import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/resumable_download.dart';
import 'package:ganj/features/player/audio_store.dart';

import '../../support/fixture_repository.dart';
import '../../support/fixtures.dart';

/// Serves one file in small chunks, honouring Range like a real file server (or not).
class _FileServer implements HttpClientAdapter {
  _FileServer(this.body, {this.honourRange = true});

  final List<int> body;
  final bool honourRange;
  final ranges = <String?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? cancelFuture) async {
    final range = o.headers['Range'] as String?;
    ranges.add(range);
    var start = 0;
    if (range != null && honourRange) {
      start = int.parse(range.substring('bytes='.length, range.length - 1));
      if (start >= body.length) {
        return ResponseBody.fromString(
          '',
          416,
          headers: {
            'content-range': ['bytes */${body.length}'],
          },
        );
      }
    }
    final rest = body.sublist(start);
    Stream<Uint8List> chunks() async* {
      for (var i = 0; i < rest.length; i += 4) {
        yield Uint8List.fromList(rest.sublist(i, math.min(i + 4, rest.length)));
        await Future<void>.delayed(Duration.zero);
      }
    }

    return ResponseBody(
      chunks(),
      range != null && honourRange ? 206 : 200,
      headers: {
        Headers.contentLengthHeader: ['${rest.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final body = List<int>.generate(40, (i) => i);
  late Directory dir;
  late File part;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ganj_dl_');
    part = File('${dir.path}/x.part');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Dio dioFor(_FileServer s) => Dio()..httpClientAdapter = s;

  Future<void> pausedAt(Dio dio, int bytes) async {
    final cancel = CancelToken();
    await expectLater(
      resumableDownload(
        dio,
        'https://i.ganjoor.net/x.mp3',
        part,
        cancel: cancel,
        onBytes: (got, _) {
          if (got >= bytes && !cancel.isCancelled) cancel.cancel('paused');
        },
      ),
      throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
    );
  }

  test('a paused download keeps its part, and the next one continues from it', () async {
    final server = _FileServer(body);
    final dio = dioFor(server);
    await pausedAt(dio, 12);
    final kept = part.lengthSync();
    expect(kept, inInclusiveRange(12, 39), reason: 'what was fetched stays on disk');
    final seen = <int>[];
    await resumableDownload(dio, 'https://i.ganjoor.net/x.mp3', part, onBytes: (got, total) => seen.add(total));
    expect(server.ranges.last, 'bytes=$kept-');
    expect(part.readAsBytesSync(), body);
    expect(seen.toSet(), {40}, reason: 'progress counts the whole file, not just the rest');
  });

  test('a server that ignores Range sends the whole file, which starts over', () async {
    final dio = dioFor(_FileServer(body, honourRange: false));
    await pausedAt(dio, 8);
    await resumableDownload(dio, 'https://i.ganjoor.net/x.mp3', part);
    expect(part.readAsBytesSync(), body);
  });

  test('a part that is already whole is done (416)', () async {
    part.writeAsBytesSync(body);
    await resumableDownload(dioFor(_FileServer(body)), 'https://i.ganjoor.net/x.mp3', part);
    expect(part.readAsBytesSync(), body);
  });

  test('a part longer than the file is thrown away and fetched again', () async {
    part.writeAsBytesSync(List.filled(60, 7));
    final server = _FileServer(body);
    await resumableDownload(dioFor(server), 'https://i.ganjoor.net/x.mp3', part);
    expect(part.readAsBytesSync(), body);
    expect(server.ranges, ['bytes=60-', null]);
  });

  test('a recitation paused mid-way can be resumed, or discarded', () async {
    final rec = poem2130().recitations.first;
    final store = FileAudioStore(dir, dioFor(_FileServer(body)), FixtureRepository());
    final cancel = CancelToken();
    await expectLater(
      store.download(
        rec,
        cancel: cancel,
        onProgress: (v) {
          if (v > 0.3 && !cancel.isCancelled) cancel.cancel('paused');
        },
      ),
      throwsA(isA<DioException>()),
    );
    expect(store.isDownloaded(rec.id), isFalse);
    expect(store.partialBytes(rec.id), greaterThan(0));

    await store.discardPartial(rec.id);
    expect(store.partialBytes(rec.id), 0);

    await store.download(rec);
    expect(store.isDownloaded(rec.id), isTrue);
    expect(File.fromUri(store.mp3Uri(rec.id)).readAsBytesSync(), body);
    expect(store.partialBytes(rec.id), 0);
  });
}
