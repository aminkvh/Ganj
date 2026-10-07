import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/disk_image.dart';

/// A real 1×1 PNG, so the image actually decodes.
Future<Uint8List> onePixelPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = const Color(0xFFB88828));
  final image = await recorder.endRecording().toImage(1, 1);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  late Directory dir;
  late List<Uri> fetched;
  late Uint8List png;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ganj_img_');
    fetched = [];
    png = await onePixelPng();
    DiskImage.configure(
      directory: dir,
      fetch: (u) async {
        fetched.add(u);
        return png;
      },
    );
  });
  tearDown(() {
    DiskImage.configure(directory: null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {} // Windows may still hold the temp folder; it is only a temp folder
  });

  Future<void> show(WidgetTester tester, String url) async {
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // Real file and network work happens outside the test's fake clock.
    await tester.runAsync(() => precacheImage(DiskImage(url), tester.element(find.byType(SizedBox))));
    await tester.pumpWidget(Image(image: DiskImage(url)));
    await tester.pump();
  }

  testWidgets('a picture is downloaded once and then read from disk, even after a restart', (tester) async {
    const url = 'https://api.ganjoor.net/api/ganjoor/poet/image/hafez.gif';
    await show(tester, url);
    expect(fetched, [Uri.parse(url)]);
    expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1));
    // A new app run: memory cache gone, disk copy stays.
    await show(tester, url);
    expect(fetched, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed download is not stored, so it is tried again next time', (tester) async {
    var calls = 0;
    DiskImage.configure(
      directory: dir,
      fetch: (u) async {
        calls++;
        throw const HttpException('offline');
      },
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Image(image: const DiskImage('https://x/y.png'), errorBuilder: (_, _, _) => const Text('fallback')),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(calls, 1);
  });

  test('clearing removes the stored pictures', () async {
    File('${dir.path}/a').writeAsBytesSync([1, 2, 3]);
    await DiskImage.clear();
    expect(dir.listSync(), isEmpty);
  });
}
