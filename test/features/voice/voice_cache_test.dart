import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/voice/app/voice_cache.dart';
import 'package:ganj/features/voice/app/voice_worker.dart';
import 'package:ganj/features/voice/app/wav.dart';

Verse _v(int o, int pos, String t, int? c) => Verse(vOrder: o, position: pos, text: t, coupletIndex: c);

Poem _poem(List<Verse> vs, {int id = 1, String? metre = 'm'}) =>
    Poem(id: id, title: 't', fullTitle: 't', fullUrl: '/t', plainText: '', verses: vs, metre: metre);

Poem _mixed() => _poem([
  _v(1, VersePosition.right, 'a1', 0),
  _v(2, VersePosition.left, 'a2', 0),
  _v(3, VersePosition.centered1, 'b1', 1),
  _v(4, VersePosition.centered2, 'b2', 1),
  _v(5, VersePosition.comment, 'note', 2),
  _v(6, VersePosition.paragraph, 'prose', 3),
  _v(7, VersePosition.right, 'c1', 4),
  _v(8, VersePosition.left, '  ', 4),
]);

BeytAudio _audio(int i, {int samples = 12000}) =>
    BeytAudio(i, Int16List.fromList(List.filled(samples, 100 + i)), 24000);

void main() {
  late Directory dir;
  late VoiceCache cache;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('voice_cache_');
    cache = VoiceCache(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('beytsOf skips prose and empty lines', () {
    final p = _mixed();
    final r = beytsOf(p);
    expect(r.length, 3);
    expect(r[0].req.lines, ['a1', 'a2']);
    expect(r[1].req.lines, ['b1', 'b2']);
    expect(r[2].req.lines, ['c1']);
    expect([for (final e in r) e.req.index], [0, 1, 2]);
    final orders = p.verses.map((v) => v.vOrder).toSet();
    for (final e in r) {
      expect(orders, contains(e.vOrder));
    }
    expect([for (final e in r) e.vOrder], [1, 3, 7]);
  });

  test('voiceCanRead false for prose only', () {
    expect(
      voiceCanRead(_poem([_v(1, VersePosition.paragraph, 'x', 0), _v(2, VersePosition.comment, 'y', 1)])),
      isFalse,
    );
    expect(voiceCanRead(_poem([_v(1, VersePosition.single, 'x', 0)])), isFalse);
    expect(voiceCanRead(_mixed()), isTrue);
  });

  Verse lv(int o, int pos, String t, int c, int? lang) =>
      Verse(vOrder: o, position: pos, text: t, coupletIndex: c, languageId: lang);

  test('an Arabic hemistich in a beyt: only the Persian one is read', () {
    final p = _poem([lv(1, VersePosition.right, 'ar', 0, 2), lv(2, VersePosition.left, 'fa', 0, 1)]);
    final r = beytsOf(p);
    expect(r.length, 1);
    expect(r[0].req.lines, ['fa']);
    expect(r[0].vOrder, 2);
  });

  test('a null languageId counts as Persian', () {
    final r = beytsOf(_poem([lv(1, VersePosition.right, 'a', 0, null), lv(2, VersePosition.left, 'b', 0, 1)]));
    expect(r[0].req.lines, ['a', 'b']);
  });

  test('an untagged poem (offline pack) whose first hemistich is Arabic reads only the Persian one', () {
    final p = _poem([
      lv(1, VersePosition.right, 'اَلا یا اَیُّهَا السّاقی اَدِرْ کَأساً و ناوِلْها', 0, null),
      lv(2, VersePosition.left, 'که عشق آسان نمود اول ولی افتاد مشکل‌ها', 0, null),
    ]);
    final r = beytsOf(p);
    expect(r.length, 1);
    expect(r[0].req.lines, ['که عشق آسان نمود اول ولی افتاد مشکل‌ها']);
    expect(r[0].vOrder, 2);
  });

  test('a tagged Persian hemistich is read even when it looks Arabic', () {
    final p = _poem([
      lv(1, VersePosition.right, 'اَلا یا اَیُّهَا السّاقی اَدِرْ کَأساً و ناوِلْها', 0, 1),
      lv(2, VersePosition.left, 'که عشق آسان نمود اول ولی افتاد مشکل‌ها', 0, 1),
    ]);
    expect(beytsOf(p)[0].req.lines.length, 2);
  });

  test('an all-Arabic beyt is skipped and the next keeps its vOrder', () {
    final p = _poem([
      lv(1, VersePosition.right, 'a1', 0, 1),
      lv(2, VersePosition.left, 'a2', 0, 1),
      lv(3, VersePosition.right, 'ar1', 1, 2),
      lv(4, VersePosition.left, 'ar2', 1, 2),
      lv(5, VersePosition.right, 'c1', 2, 1),
      lv(6, VersePosition.left, 'c2', 2, 1),
    ]);
    final r = beytsOf(p);
    expect([for (final e in r) e.vOrder], [1, 5]);
    expect([for (final e in r) e.req.index], [0, 1]);
  });

  test('voiceCanRead is false for an all-Arabic poem, and the key ignores skipped lines', () {
    final p = _poem([lv(1, VersePosition.right, 'x', 0, 2), lv(2, VersePosition.left, 'y', 0, 2)]);
    expect(voiceCanRead(p), isFalse);
    expect(beytsOf(p), isEmpty);
    final one = _poem([lv(1, VersePosition.right, 'x', 0, 2), lv(2, VersePosition.left, 'y', 0, 1)]);
    expect(voiceCanRead(one), isTrue); // a molamma' beyt: its Persian hemistich is read
    final molamma = _poem([
      for (var b = 0; b < 3; b++) ...[
        lv(b * 2 + 1, VersePosition.right, 'ar$b', b, 2),
        lv(b * 2 + 2, VersePosition.left, 'fa$b', b, 1),
      ],
    ]);
    expect(voiceCanRead(molamma), isTrue);
    expect([for (final x in beytsOf(molamma)) x.req.lines], [
      ['fa0'],
      ['fa1'],
      ['fa2'],
    ]);
    final a = _poem([
      lv(1, VersePosition.right, 'a', 0, 1),
      lv(2, VersePosition.left, 'b', 0, 1),
      lv(3, VersePosition.right, 'zz', 1, 2),
    ]);
    final b = _poem([
      lv(1, VersePosition.right, 'a', 0, 1),
      lv(2, VersePosition.left, 'b', 0, 1),
      lv(3, VersePosition.right, 'qq', 1, 2),
    ]);
    expect(cache.keyOf(a, 'v1'), cache.keyOf(b, 'v1'));
  });

  test('key changes with text, metre and version', () {
    final base = cache.keyOf(_mixed(), 'v1');
    expect(base.length, 16);
    expect(cache.keyOf(_mixed(), 'v1'), base);
    expect(cache.keyOf(_mixed(), 'v2'), isNot(base));
    expect(cache.keyOf(_poem(_mixed().verses, metre: 'other'), 'v1'), isNot(base));
    final changed = _poem([..._mixed().verses.take(7), _v(8, VersePosition.left, 'zz', 4)]);
    expect(cache.keyOf(changed, 'v1'), isNot(base));
  });

  test('join makes one wav with gaps and sync', () async {
    for (var i = 0; i < 3; i++) {
      await cache.putBeyt(1, 'k', _audio(i));
    }
    expect(cache.partsHave(1, 'k'), {0, 1, 2});
    expect(cache.done(1, 'k'), isNull);
    final f = await cache.join(1, 'k', [11, 22, 33]);
    expect(f.existsSync(), isTrue);
    final bytes = f.readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    final dataLen = bd.getUint32(40, Endian.little);
    expect(dataLen, ((1.5 + 0.5) * 24000).round() * 2);
    expect(bytes.length, 44 + dataLen);
    expect(bd.getUint32(24, Endian.little), 24000);
    final sync = cache.syncOf(1, 'k');
    expect([for (final s in sync) (s.vOrder, s.ms)], [(11, 0), (22, 750), (33, 1500), (-2, 2000)]);
    expect(Directory('${dir.path}/1-k.parts').existsSync(), isFalse);
    expect(cache.done(1, 'k')?.path, f.path);
  });

  test('evicts oldest over cap', () async {
    final c = VoiceCache(dir, capBytes: 100 * 1024);
    final base = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 1; i <= 3; i++) {
      final w = File('${dir.path}/$i-k.wav')..writeAsBytesSync(Uint8List(60 * 1024));
      File('${dir.path}/$i-k.sync.json').writeAsStringSync('[]');
      w.setLastModifiedSync(base.add(Duration(minutes: i)));
    }
    await c.evict();
    expect(File('${dir.path}/1-k.wav').existsSync(), isFalse);
    expect(File('${dir.path}/1-k.sync.json').existsSync(), isFalse);
    expect(File('${dir.path}/2-k.wav').existsSync(), isFalse);
    expect(File('${dir.path}/3-k.wav').existsSync(), isTrue);
    expect(await c.sizeBytes(), lessThanOrEqualTo(100 * 1024));
  });

  test('evict removes stale parts folders only', () async {
    final old = Directory('${dir.path}/5-k.parts')..createSync();
    File('${old.path}/0.pcm')
      ..writeAsBytesSync([1, 2])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final fresh = Directory('${dir.path}/6-k.parts')..createSync();
    File('${fresh.path}/0.pcm').writeAsBytesSync([1, 2]);
    await cache.evict();
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
  });

  test('partsHave lets a prepare resume', () async {
    expect(cache.partsHave(2, 'k'), isEmpty);
    await cache.putBeyt(2, 'k', _audio(0));
    await cache.putBeyt(2, 'k', _audio(2));
    expect(cache.partsHave(2, 'k'), {0, 2});
    await cache.putBeyt(2, 'k', _audio(1));
    final f = await cache.join(2, 'k', [1, 2, 3]);
    expect(f.existsSync(), isTrue);
  });

  test('clear removes everything it can', () async {
    await cache.putBeyt(1, 'k', _audio(0));
    await cache.join(1, 'k', [1]);
    await cache.clear();
    expect(await cache.sizeBytes(), 0);
  });

  test('clear spares the folders named in keep', () async {
    await cache.putBeyt(1, 'k', _audio(0));
    await cache.join(1, 'k', [1]);
    await cache.putBeyt(2, 'r', _audio(0));
    await cache.putBeyt(3, 's', _audio(0));
    await cache.clear(keep: {'2-r.parts'});
    expect(cache.done(1, 'k'), isNull);
    expect(cache.partsHave(3, 's'), isEmpty);
    expect(cache.partsHave(2, 'r'), {0});
  });

  test('join is byte for byte the in-memory join (parts of different lengths)', () async {
    final parts = [
      Int16List.fromList([for (var i = 0; i < 1000; i++) (i * 37) - 18000]),
      Int16List.fromList([for (var i = 0; i < 1; i++) -32768]),
      Int16List.fromList([for (var i = 0; i < 777; i++) 32767 - i * 3]),
    ];
    for (var i = 0; i < parts.length; i++) {
      await cache.putBeyt(9, 'g', BeytAudio(i, parts[i], 24000));
    }
    final f = await cache.join(9, 'g', [1, 3, 5]);
    // The reference: every sample in one buffer, kBeytGap of zeros between parts.
    final gap = (24000 * kBeytGap.inMilliseconds / 1000).round();
    final all = <int>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) all.addAll(List.filled(gap, 0));
      all.addAll(parts[i]);
    }
    expect(f.readAsBytesSync(), pcm16Wav(Int16List.fromList(all), 24000));
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('pcm16Wav header', () {
    final w = pcm16Wav(Int16List.fromList([1, -2]), 24000);
    expect(w.length, 48);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
  });
}
