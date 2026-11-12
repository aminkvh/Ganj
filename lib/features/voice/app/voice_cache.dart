import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../data/api/dto/poem.dart';
import '../../../data/api/dto/recitation.dart';
import '../../poem/couplets.dart';
import 'language_guess.dart';
import '../reading/g2p.dart' show kReadingRulesVersion;
import 'voice_worker.dart';
import 'wav.dart';

/// Silence between two beyts (none before the first, none after the last). To tune by ear.
const kBeytGap = Duration(milliseconds: 250);

const _kPartsMaxAge = Duration(days: 1);

/// Whether the voice can read [v]: it has text and is Persian (Ganjoor's languageId 1, or no tag and the text does
/// not look Arabic: offline packs carry no tags).
bool _readable(Verse v) {
  if (v.text.trim().isEmpty) return false;
  if (v.languageId == null) return !looksArabic(v.text);
  return v.languageId == 1;
}

/// The couplets the voice reads: beyts, bands and single lines; empty and non-Persian hemistichs are dropped
/// and a couplet left with no lines is skipped. `vOrder` is the first kept verse's vOrder, `later` those of the
/// kept verses after it (each synced at its own onset when the audio's breaks are found).
List<({BeytRequest req, int vOrder, List<int> later})> beytsOf(Poem p) {
  final out = <({BeytRequest req, int vOrder, List<int> later})>[];
  for (final c in groupCouplets(p.verses)) {
    if (c.kind != CoupletKind.beyt && c.kind != CoupletKind.band && c.kind != CoupletKind.single) continue;
    final kept = c.verses.where(_readable).toList();
    if (kept.isEmpty) continue;
    out.add((
      req: BeytRequest(out.length, [for (final v in kept) v.text]),
      vOrder: kept.first.vOrder,
      later: [for (final v in kept.skip(1)) v.vOrder],
    ));
  }
  return out;
}

/// True when at least one beyt or band has two non-empty lines (so the poem is verse) and one of them the voice
/// reads: a molamma' with a Persian and an Arabic hemistich in every beyt is read, an all-Arabic poem is not.
bool voiceCanRead(Poem p) {
  for (final c in groupCouplets(p.verses)) {
    if (c.kind != CoupletKind.beyt && c.kind != CoupletKind.band) continue;
    if (c.verses.where((v) => v.text.trim().isNotEmpty).length >= 2 && c.verses.any(_readable)) return true;
  }
  return false;
}

/// Finished readings on disk: `<poemId>-<key>.wav` + `.sync.json`, and `<poemId>-<key>.parts/<index>.pcm`
/// while a poem is still being read (with a `steps` file: the flow steps its parts are read with). A finished
/// reading is used whatever steps made it.
class VoiceCache {
  VoiceCache(this.root, {this.capBytes = 300 << 20});

  final Directory root;
  final int capBytes;

  static final _sep = Platform.pathSeparator;

  String _base(int poemId, String key) => '${root.path}$_sep$poemId-$key';
  File _wav(int poemId, String key) => File('${_base(poemId, key)}.wav');
  File _sync(int poemId, String key) => File('${_base(poemId, key)}.sync.json');
  Directory _parts(int poemId, String key) => Directory('${root.path}$_sep${partsName(poemId, key)}');

  /// The name (not the path) of a poem's parts folder inside [root].
  static String partsName(int poemId, String key) => '$poemId-$key.parts';

  String keyOf(Poem p, String voiceVersion) {
    final b = StringBuffer()
      ..write(kReadingRulesVersion)
      ..write('\u0000')
      ..write(voiceVersion)
      ..write('\u0000')
      ..write(p.metre ?? '');
    for (final e in beytsOf(p)) {
      for (final l in e.req.lines) {
        b
          ..write('\u0000')
          ..write(l);
      }
      b.write('\u0001');
    }
    return sha256.convert(utf8.encode(b.toString())).toString().substring(0, 16);
  }

  /// The joined reading when present (with its sync file); touches its mtime so eviction keeps it.
  File? done(int poemId, String key) {
    final w = _wav(poemId, key);
    if (!w.existsSync() || !_sync(poemId, key).existsSync()) return null;
    try {
      w.setLastModifiedSync(DateTime.now());
    } on FileSystemException {
      // Locked by the player: the touch is only a hint.
    }
    return w;
  }

  List<SyncPoint> syncOf(int poemId, String key) {
    final f = _sync(poemId, key);
    if (!f.existsSync()) return const [];
    return parseSyncJson(f.readAsStringSync());
  }

  Future<void> putBeyt(int poemId, String key, BeytAudio a) async {
    final dir = _parts(poemId, key);
    await dir.create(recursive: true);
    // Onsets first: a part counts once its PCM is there, and an earlier take's onsets must not outlive it.
    final on = _onsets(poemId, key, a.index);
    if (a.onsetsMs.isEmpty) {
      if (on.existsSync()) await _tryDelete(on);
    } else {
      final t = File('${on.path}.tmp');
      await t.writeAsString(jsonEncode(a.onsetsMs), flush: true);
      await t.rename(on.path);
    }
    final f = File('${dir.path}$_sep${a.index}.pcm');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(a.pcm.buffer.asUint8List(a.pcm.offsetInBytes, a.pcm.lengthInBytes), flush: true);
    await tmp.rename(f.path);
    // A stream item made from an earlier take of this beyt must never play again.
    final item = File('${dir.path}$_sep${a.index}.wav');
    if (item.existsSync()) await _tryDelete(item);
  }

  File _onsets(int poemId, String key, int index) => File('${_parts(poemId, key).path}$_sep$index.onsets.json');

  /// Where each read line after the first starts in beyt [index]'s part, in ms (empty when not known).
  List<int> partOnsetsMs(int poemId, String key, int index) {
    try {
      return List<int>.from(jsonDecode(_onsets(poemId, key, index).readAsStringSync()) as List);
    } catch (_) {
      return const []; // none, or damaged: the beyt is synced as one
    }
  }

  File _stepsFile(int poemId, String key) => File('${_parts(poemId, key).path}${_sep}steps');

  /// The flow steps a poem's parts are read with (the `steps` file in its parts folder), or null when none is
  /// recorded (or it cannot be read).
  int? partsSteps(int poemId, String key) {
    try {
      final n = int.tryParse(_stepsFile(poemId, key).readAsStringSync().trim());
      return n != null && n > 0 ? n : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Records the flow steps of a poem's parts, before the first part is written, so a resumed reading keeps them.
  Future<void> setPartsSteps(int poemId, String key, int steps) async {
    await _parts(poemId, key).create(recursive: true);
    final f = _stepsFile(poemId, key);
    // Its own name: a cancelled run's write may still be in flight.
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}-${_tmpSeq++}.tmp');
    await tmp.writeAsString('$steps', flush: true);
    await tmp.rename(f.path);
  }

  /// The audio length of beyt [index]'s part, in seconds (0 when it is missing).
  double partSeconds(int poemId, String key, int index, {int sampleRate = 24000}) {
    try {
      return File('${_parts(poemId, key).path}$_sep$index.pcm').lengthSync() / 2 / sampleRate;
    } on FileSystemException {
      return 0;
    }
  }

  Set<int> partsHave(int poemId, String key) {
    final dir = _parts(poemId, key);
    if (!dir.existsSync()) return {};
    final out = <int>{};
    for (final e in dir.listSync()) {
      if (e is! File || !e.path.endsWith('.pcm')) continue;
      final i = int.tryParse(e.uri.pathSegments.last.replaceAll('.pcm', ''));
      if (i != null) out.add(i);
    }
    return out;
  }

  /// Beyt [index] as its own playable WAV (`<index>.wav` in the parts folder), for a streamed reading: its PCM
  /// followed by [kBeytGap] of silence unless it is the [last] beyt, so the playlist of these items sounds like
  /// the joined file. Idempotent: an existing item is returned as it is.
  Future<File> beytItem(int poemId, String key, int index, {required bool last, int sampleRate = 24000}) async {
    final dir = _parts(poemId, key);
    final f = File('${dir.path}$_sep$index.wav');
    if (f.existsSync()) return f;
    final bytes = await File('${dir.path}$_sep$index.pcm').readAsBytes();
    final pcmLen = bytes.length - bytes.length % 2;
    final gapLen = last ? 0 : (sampleRate * kBeytGap.inMilliseconds / 1000).round() * 2;
    // A name of its own, so two writers of the same item never share a temp file.
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}-${_tmpSeq++}.tmp');
    final out = await tmp.open(mode: FileMode.write);
    try {
      await out.writeFrom(pcm16WavHeader(pcmLen + gapLen, sampleRate));
      await out.writeFrom(bytes, 0, pcmLen);
      if (gapLen > 0) await out.writeFrom(Uint8List(gapLen));
      await out.flush();
    } finally {
      await out.close();
    }
    try {
      await tmp.rename(f.path);
    } on FileSystemException {
      // Another writer got there first (and the player may hold it open): that item is the same audio.
      await _tryDelete(tmp);
      if (!f.existsSync()) rethrow;
    }
    return f;
  }

  static int _tmpSeq = 0;

  /// Joins the parts (index order, [kBeytGap] between) into one WAV and writes the sync file.
  /// [vOrders] holds one vOrder per beyt, by index; [later] (when given) the vOrders of each beyt's later read lines,
  /// placed at the part's onsets when there is one per line (else the beyt is synced as one). Deletes the parts
  /// afterwards and evicts old readings. With [keepItems] (a streamed reading still playing), only the PCM parts
  /// go: the [beytItem] WAVs stay for the player, and eviction removes the folder later.
  Future<File> join(
    int poemId,
    String key,
    List<int> vOrders, {
    List<List<int>> later = const [],
    int sampleRate = 24000,
    bool keepItems = false,
  }) async {
    final dir = _parts(poemId, key);
    final gap = (sampleRate * kBeytGap.inMilliseconds / 1000).round();
    // Sizes first (from the parts' lengths), so the header can be written before any sample: the audio is
    // streamed to disk one part at a time instead of being held in memory.
    final parts = [for (var i = 0; i < vOrders.length; i++) File('${dir.path}$_sep$i.pcm')];
    final sync = <SyncPoint>[];
    var total = 0; // samples
    for (var i = 0; i < parts.length; i++) {
      final samples = await parts[i].length() ~/ 2;
      if (i > 0) total += gap;
      final startMs = (total * 1000 / sampleRate).round();
      sync.add(SyncPoint(vOrders[i], startMs));
      final more = i < later.length ? later[i] : const <int>[];
      final onsets = more.isEmpty ? const <int>[] : partOnsetsMs(poemId, key, i);
      if (onsets.length == more.length) {
        for (var j = 0; j < more.length; j++) {
          sync.add(SyncPoint(more[j], startMs + onsets[j]));
        }
      }
      total += samples;
    }
    sync.add(SyncPoint(-2, (total * 1000 / sampleRate).round()));

    final wav = _wav(poemId, key);
    final syncFile = _sync(poemId, key);
    final tmpWav = File('${wav.path}.tmp');
    final out = await tmpWav.open(mode: FileMode.write);
    try {
      await out.writeFrom(pcm16WavHeader(total * 2, sampleRate));
      final silence = Uint8List(gap * 2);
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) await out.writeFrom(silence);
        // The parts are little-endian Int16 already (see [putBeyt]): copied as they are.
        final bytes = await parts[i].readAsBytes();
        await out.writeFrom(bytes, 0, bytes.length - bytes.length % 2);
      }
      await out.flush();
    } finally {
      await out.close();
    }
    final tmpSync = File('${syncFile.path}.tmp');
    await tmpSync.writeAsString(jsonEncode([for (final p in sync) p.toJson()]), flush: true);
    // Sync first: `done` needs both, and the wav is the last thing to appear.
    await tmpSync.rename(syncFile.path);
    await tmpWav.rename(wav.path);
    if (keepItems) {
      // The steps file stays with the beyt items; with no parts left it is never taken as a resume's steps.
      for (var i = 0; i < parts.length; i++) {
        await _tryDelete(parts[i]);
        final on = _onsets(poemId, key, i);
        if (on.existsSync()) await _tryDelete(on);
      }
    } else if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    await evict(keep: wav);
    return wav;
  }

  /// Deletes the oldest joined readings until the total is within the cap (never [keep]), and
  /// parts folders untouched for over a day.
  Future<void> evict({File? keep}) async {
    if (!root.existsSync()) return;
    final entries = root.listSync();
    final now = DateTime.now();
    for (final e in entries) {
      if (e is! Directory || !e.path.endsWith('.parts')) continue;
      // A folder's own mtime only moves on create/delete; files say when work last happened.
      DateTime? newest;
      for (final f in e.listSync()) {
        final m = f.statSync().modified;
        if (newest == null || m.isAfter(newest)) newest = m;
      }
      newest ??= e.statSync().modified;
      if (now.difference(newest) > _kPartsMaxAge) await _tryDelete(e);
    }
    final wavs = [
      for (final e in entries)
        if (e is File && e.path.endsWith('.wav')) e,
    ]..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var total = await sizeBytes();
    for (final w in wavs) {
      if (total <= capBytes) break;
      if (keep != null && w.path == keep.path) continue;
      final side = File('${w.path.substring(0, w.path.length - 4)}.sync.json');
      var freed = 0;
      for (final f in [w, side]) {
        if (!f.existsSync()) continue;
        final len = f.lengthSync();
        if (await _tryDelete(f)) freed += len;
      }
      total -= freed;
    }
  }

  Future<int> sizeBytes() async {
    if (!root.existsSync()) return 0;
    var n = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) {
        try {
          n += await e.length();
        } on FileSystemException {
          // Vanished meanwhile.
        }
      }
    }
    return n;
  }

  /// Deletes what it can; a file open in the player (Windows) is skipped, and so are the entries whose names are
  /// in [keep] (the running prepare's parts folder, see [partsName]).
  Future<void> clear({Set<String> keep = const {}}) async {
    if (!root.existsSync()) return;
    for (final e in root.listSync()) {
      if (keep.contains(e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) continue;
      await _tryDelete(e);
    }
  }

  Future<bool> _tryDelete(FileSystemEntity e) async {
    try {
      await e.delete(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
