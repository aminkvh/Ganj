import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/api_client.dart' show kUserAgent;
import '../../../data/api/dto/poem.dart';
import '../../../data/api/dto/recitation.dart';
import '../../../data/providers.dart';
import '../../player/audio_backend.dart' show PlaylistItem;
import '../../player/player_controller.dart';
import '../engine/voice_settings.dart';
import 'start_rule.dart';
import 'steps_rule.dart';
import 'voice_cache.dart';
import 'voice_downloader.dart';
import 'voice_manifest.dart';
import 'voice_worker.dart';

final _sep = Platform.pathSeparator;

/// SharedPreferences key: the source key (`hf`, `github`) that served the last good download.
const kVoiceSourcePref = 'voice.source';

/// SharedPreferences key: how fast voice [version] reads on this device, as t8: wall seconds per audio second,
/// normalized to 8 flow steps (see [t8From]). It chooses each poem's steps, and lets the next poem start streaming
/// before its own speed is measured.
String voiceT8Pref(String version) => 'voice.t8.$version';

/// The most flow steps the voice in [dir] may use: its phone.json's `num_steps` (the default without one).
int _maxSteps(String dir) {
  try {
    return VoiceSettings.load('$dir${_sep}phone.json').numSteps;
  } catch (_) {
    return const VoiceSettings().numSteps; // a damaged phone.json
  }
}

/// Wall time, for measuring how fast the voice reads. Tests override it.
final voiceClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ---------------------------------------------------------------------------------------------------------------
// Where things live
// ---------------------------------------------------------------------------------------------------------------

/// `<app support>/voice`: holds `<version>-<variant>/` folders; the one with `installed.json` is the voice.
final voiceRootProvider = Provider<Directory>((ref) => throw UnimplementedError('override in main'));

/// `<app cache>/voice-cache`: finished readings live in `<base>/<version>-<variant>/` (see [voiceCacheProvider]).
/// Null (the default) means no cache, so nothing can be prepared.
final voiceCacheBaseProvider = Provider<Directory?>((ref) => null);

/// The installed voice, or null. [VoiceController] keeps it in step with its own state. The cache and the worker
/// derive from this rather than from [voiceProvider], so the controller may read them (Riverpod forbids a provider
/// reading one that depends on it).
final _installedVoiceProvider = NotifierProvider<_InstalledVoice, VoiceReady?>(_InstalledVoice.new);

class _InstalledVoice extends Notifier<VoiceReady?> {
  @override
  VoiceReady? build() => _readInstalled(ref.watch(voiceRootProvider));

  void set(VoiceReady? v) => state = v;
}

/// Deletes every folder under the cache [base] but [except] (best effort: it is only cache). Readings of other
/// versions or variants, or left by a switch that was interrupted, are never used again.
Future<void> _pruneCaches(Directory? base, String except) async {
  try {
    if (base == null || !base.existsSync()) return;
    for (final e in base.listSync()) {
      if (e.path.split(_sep).last == except) continue;
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // In use (the player): it is only cache.
      }
    }
  } on FileSystemException {
    // The folder went away while listing.
  }
}

/// The installed voice, from `installed.json`; null when none (or it cannot be read).
VoiceReady? _readInstalled(Directory root, {String? folder}) {
  try {
    final dir = folder == null ? installedDir(root) : Directory('${root.path}$_sep$folder');
    if (folder != null && !File('${dir!.path}${_sep}installed.json').existsSync()) {
      return null;
    }
    if (dir == null) return null;
    final m = VoiceManifest.fromJson(
      jsonDecode(File('${dir.path}${_sep}installed.json').readAsStringSync()) as Map<String, dynamic>,
    );
    return VoiceReady(dir.path, m.version, m.totalBytes, installedVariant(dir));
  } catch (_) {
    return null;
  }
}

/// The readings cache of the installed voice: `<base>/<version>-<variant>` (the two variants sound different, so
/// they never share readings), null unless a voice is installed. Derived from [voiceCacheBaseProvider] and the
/// installed voice, because they are only known at run time. To clear it, [VoiceController.remove] deletes the
/// whole base folder (every version).
final voiceCacheProvider = Provider<VoiceCache?>((ref) {
  final base = ref.watch(voiceCacheBaseProvider);
  final name = ref.watch(_installedVoiceProvider.select((s) => s == null ? null : '${s.version}-${s.variant}'));
  if (base == null || name == null) return null;
  return VoiceCache(Directory('${base.path}$_sep$name'));
});

/// Downloads the voice; the source that worked last time is tried first. Tests override it.
final voiceDownloaderProvider = Provider<VoiceDownloader>(
  (ref) => VoiceDownloader(
    dio: Dio(BaseOptions(headers: {'User-Agent': kUserAgent})),
    root: ref.watch(voiceRootProvider),
    sources: voiceSources(),
    preferred: ref.read(sharedPrefsProvider).getString(kVoiceSourcePref),
  ),
);

/// The background reader while the voice is [VoiceReady]; disposed when the voice changes. Tests override it.
final voiceWorkerProvider = Provider<VoiceWorker?>((ref) {
  final dir = ref.watch(_installedVoiceProvider.select((s) => s?.dir));
  if (dir == null) return null;
  final w = IsolateVoiceWorker(dir);
  ref.onDispose(w.dispose);
  return w;
});

// ---------------------------------------------------------------------------------------------------------------
// The voice download
// ---------------------------------------------------------------------------------------------------------------

sealed class VoiceStatus {
  const VoiceStatus();
}

/// Nothing installed. [wasCorrupt]: the voice was just deleted because its files would not load.
class VoiceAbsent extends VoiceStatus {
  const VoiceAbsent({this.wasCorrupt = false});

  final bool wasCorrupt;
}

/// The manifest is being fetched (for the download size).
class VoiceChecking extends VoiceStatus {
  const VoiceChecking();
}

class VoiceDownloading extends VoiceStatus {
  const VoiceDownloading(this.got, this.total);

  final int got;
  final int total;
}

/// Installed in [dir] (the `<root>/<version>-<variant>` folder); [bytes] is the size of the installed files.
class VoiceReady extends VoiceStatus {
  const VoiceReady(this.dir, this.version, this.bytes, this.variant, {this.lastSwitchFailed = false});

  final String dir;
  final String version;
  final int bytes;

  /// `fast` or `quality`.
  final String variant;

  /// The last attempt to switch to another voice failed; this voice is still installed and in use.
  final bool lastSwitchFailed;
}

/// The last manifest fetch or download failed (never `cancelled`: a cancel goes back to [VoiceAbsent]).
class VoiceFailed extends VoiceStatus {
  const VoiceFailed(this.kind);

  final VoiceDownloadFailure kind;
}

class VoiceController extends Notifier<VoiceStatus> {
  CancelToken? _cancel;

  /// Completes when the running [download] has stopped (installed, failed or cancelled).
  Completer<void>? _downloadEnded;

  Directory get _root => ref.read(voiceRootProvider);

  /// Read, not watched: this controller updates [_installedVoiceProvider] itself and then sets its own state
  /// (a rebuild would lose `wasCorrupt`).
  @override
  VoiceStatus build() {
    final ready = ref.read(_installedVoiceProvider);
    if (ready != null) {
      _pruneCaches(ref.read(voiceCacheBaseProvider), '${ready.version}-${ready.variant}');
    }
    return ready ?? const VoiceAbsent();
  }

  void _setInstalled(VoiceReady? v) => ref.read(_installedVoiceProvider.notifier).set(v);

  /// Fetches the manifest (to show the size before downloading). Shows [VoiceChecking] meanwhile, then returns to
  /// the previous state; on failure the state is [VoiceFailed] and the result null.
  Future<VoiceManifest?> manifest() async {
    final before = state;
    state = const VoiceChecking();
    try {
      final m = await ref.read(voiceDownloaderProvider).fetchManifest();
      if (ref.mounted && state is VoiceChecking) {
        state = before is VoiceFailed ? const VoiceAbsent() : before;
      }
      return m;
    } on VoiceDownloadError catch (e) {
      if (ref.mounted && state is VoiceChecking) state = VoiceFailed(e.kind);
      return null;
    } catch (_) {
      if (ref.mounted && state is VoiceChecking) {
        state = const VoiceFailed(VoiceDownloadFailure.offline);
      }
      return null;
    }
  }

  /// Installs [variant] (a key of [VoiceManifest.variants]); another installed voice is replaced once it is done.
  Future<void> download(VoiceManifest m, {required String variant}) async {
    if (state is VoiceDownloading) return;
    final cancel = _cancel = CancelToken();
    final ended = _downloadEnded = Completer<void>();
    state = VoiceDownloading(0, m.variants.containsKey(variant) ? m.sizeOf(variant) : 0);
    try {
      await _download(m, variant, cancel);
    } finally {
      if (identical(_downloadEnded, ended)) _downloadEnded = null;
      ended.complete();
    }
  }

  Future<void> _download(VoiceManifest m, String variant, CancelToken cancel) async {
    final name = '${m.version}-$variant';
    try {
      final source = await ref
          .read(voiceDownloaderProvider)
          .install(
            m,
            variant: variant,
            cancel: cancel,
            onProgress: (got, total) {
              if (ref.mounted && !cancel.isCancelled) {
                state = VoiceDownloading(got, total);
              }
            },
          );
      if (!ref.mounted) return;
      await ref.read(sharedPrefsProvider).setString(kVoiceSourcePref, source);
      final old = ref.read(_installedVoiceProvider);
      if (old != null && old.dir.split(_sep).last != name) {
        await _stopWorker(); // it holds the old voice's files open
        await _deleteVersions(except: name);
        await _deleteOldCaches(except: name);
      }
      if (!ref.mounted) return;
      final ready = _readInstalled(_root, folder: name);
      _setInstalled(ready);
      state = ready ?? const VoiceFailed(VoiceDownloadFailure.checksum);
    } on VoiceDownloadError catch (e) {
      if (!ref.mounted) return;
      _failed(cancelled: e.kind == VoiceDownloadFailure.cancelled, kind: e.kind);
    } catch (_) {
      if (!ref.mounted) return;
      _failed(cancelled: cancel.isCancelled, kind: VoiceDownloadFailure.offline);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  /// A download ended without installing: another installed voice stays in use (its files and readings are
  /// untouched), flagged when the switch failed; with none, the state is [VoiceAbsent] (cancelled) or [VoiceFailed].
  void _failed({required bool cancelled, required VoiceDownloadFailure kind}) {
    final old = ref.read(_installedVoiceProvider);
    if (old != null) {
      state = VoiceReady(old.dir, old.version, old.bytes, old.variant, lastSwitchFailed: !cancelled);
    } else {
      state = cancelled ? const VoiceAbsent() : VoiceFailed(kind);
    }
  }

  /// Stops a running download; the partial files stay, so the next [download] resumes.
  void cancel() => _cancel?.cancel();

  /// Deletes the voice (from Settings): stops the reader, any prepare and voice playback, clears the cache, and
  /// deletes everything under the voice root — an installed voice or a partial download alike. Works from any
  /// state and ends in [VoiceAbsent]; a running download is cancelled first and awaited, so none of its writes
  /// land after the delete.
  Future<void> remove() async {
    final downloading = _downloadEnded;
    cancel();
    if (downloading != null) await downloading.future;
    if (!ref.mounted) return;
    // Wait (briefly) for the cancelled prepare's part writes or join, or they could recreate cache files.
    final settling = ref.read(_currentPrepareProvider).cancelCurrent();
    ref.invalidate(voicePrepareProvider); // no poem keeps a Prepared that points at a deleted reading
    await settling;
    await _stopWorker();
    final player = ref.read(playerProvider);
    if (player.recitation?.id == kVoiceRecitationId) {
      await ref.read(playerProvider.notifier).stop();
    }
    final cache = ref.read(voiceCacheProvider);
    await cache?.clear();
    final base = ref.read(voiceCacheBaseProvider);
    if (base != null && base.existsSync()) {
      try {
        await base.delete(recursive: true); // older versions' readings too
      } on FileSystemException {
        // A file still open: what is left is only cache.
      }
    }
    await _deleteVersions();
    await _deleteRest();
    if (!ref.mounted) return;
    _setInstalled(null);
    state = const VoiceAbsent();
  }

  /// Deletes whatever [_deleteVersions] left under the voice root (stray files).
  Future<void> _deleteRest() async {
    final root = _root;
    if (!root.existsSync()) return;
    for (final e in root.listSync()) {
      try {
        await e.delete(recursive: true);
      } on FileSystemException {
        // Locked (Windows): nothing more can be done now.
      }
    }
  }

  /// The voice files would not load: delete them so the reader can download again.
  Future<void> markCorrupt() async {
    await _stopWorker();
    await _deleteVersions();
    if (!ref.mounted) return;
    _setInstalled(null);
    state = const VoiceAbsent(wasCorrupt: true);
  }

  Future<void> _stopWorker() async {
    final w = ref.read(voiceWorkerProvider);
    if (w == null) return;
    w.cancel();
    await w.dispose();
  }

  /// Deletes the readings of other voice versions: every `<cache base>/<version>` folder but [except].
  Future<void> _deleteOldCaches({required String except}) => _pruneCaches(ref.read(voiceCacheBaseProvider), except);

  /// Deletes every `<root>/<version>` folder (but [except]). `installed.json` goes first, so a folder that
  /// cannot be deleted completely no longer counts as installed.
  Future<void> _deleteVersions({String? except}) async {
    final root = _root;
    if (!root.existsSync()) return;
    for (final d in root.listSync().whereType<Directory>()) {
      if (except != null && d.path.split(_sep).last == except) continue;
      try {
        final marker = File('${d.path}${_sep}installed.json');
        if (marker.existsSync()) await marker.delete();
        await d.delete(recursive: true);
      } on FileSystemException {
        // Locked file (Windows): the marker is gone, so it is no longer an installed voice.
      }
    }
  }
}

final voiceProvider = NotifierProvider<VoiceController, VoiceStatus>(VoiceController.new);

// ---------------------------------------------------------------------------------------------------------------
// Preparing one poem
// ---------------------------------------------------------------------------------------------------------------

sealed class PrepareStatus {
  const PrepareStatus();
}

/// Not started, or cancelled (the beyts read so far are kept for the next start).
class PrepareIdle extends PrepareStatus {
  const PrepareIdle();
}

class Preparing extends PrepareStatus {
  const Preparing(this.done, this.total);

  final int done;
  final int total;
}

class Prepared extends PrepareStatus {
  const Prepared(this.wav, this.sync);

  final File wav;
  final List<SyncPoint> sync;
}

class PrepareFailed extends PrepareStatus {
  const PrepareFailed();
}

/// One call of [PrepareController.start].
class _Run {
  _Run(this.id, this.poemId, this.playWhenDone, this.cancel);

  final int id;

  /// The poem being prepared.
  final int poemId;

  /// Its parts folder name in the voice cache, once known.
  String? partsDir;

  /// Cleared by [PrepareController.quiet]: the run still finishes, but never plays.
  bool playWhenDone;

  final void Function() cancel;

  /// Its disk work in flight (part writes, the join).
  final List<Future<void>> _io = [];

  void track(Future<void> f) => _io.add(f);

  /// Completes when the tracked disk work has ended (errors ignored), or after [limit].
  Future<void> settle({Duration limit = const Duration(seconds: 3)}) =>
      Future.wait(List.of(_io)).then<void>((_) {}, onError: (_) {}).timeout(limit, onTimeout: () {});
}

/// The single running prepare, across all poems: a new start cancels it.
class _CurrentPrepare {
  int _id = 0;
  _Run? _running;

  /// The latest stream a prepare started, and its parts folder name (its beyt items live there).
  ({VoiceStreamToken token, String partsDir})? streamed;

  _Run? get running => _running;

  /// Cancels the running prepare (if any) and makes a new current one.
  _Run next(int poemId, bool playWhenDone, void Function() cancel) {
    cancelCurrent();
    return _running = _Run(++_id, poemId, playWhenDone, cancel);
  }

  bool isCurrent(_Run r) => r.id == _id;

  /// Lets the running prepare finish without playing, unless it is [poemId]'s.
  void quietExcept(int poemId) {
    final r = _running;
    if (r != null && r.poemId != poemId) r.playWhenDone = false;
  }

  /// Cancels the running prepare; the result completes once its disk work has settled. It is no longer current,
  /// so work of it that lands later (a part write, a stream item) starts nothing.
  Future<void> cancelCurrent() {
    final r = _running;
    _running = null;
    if (r == null) return Future.value();
    _id++;
    r.cancel();
    return r.settle();
  }

  void finished(_Run r) {
    if (identical(_running, r)) _running = null;
  }
}

final _currentPrepareProvider = Provider<_CurrentPrepare>((ref) => _CurrentPrepare());

/// The running prepare, as screens other than its own row see it. Tests override it.
final voicePreparesProvider = Provider<VoicePrepares>(
  (ref) =>
      VoicePrepares._(ref.watch(_currentPrepareProvider), (t) => ref.read(playerProvider.notifier).isCurrentStream(t)),
);

class VoicePrepares {
  VoicePrepares._(this._current, this._playing);

  final _CurrentPrepare _current;

  /// Whether the player is playing this stream.
  final bool Function(VoiceStreamToken) _playing;

  /// A poem page opened (possibly over another): the running prepare of any other poem finishes, but never plays.
  void quietExcept(int poemId) => _current.quietExcept(poemId);

  /// The running prepare's parts folder name in the voice cache (see [VoiceCache.partsName]), or null.
  String? get runningPartsDir => _current.running?.partsDir;

  /// The parts folders a cache clear must spare: the running prepare's, and that of the stream being played.
  Set<String> get keepParts {
    final s = _current.streamed;
    return {?runningPartsDir, if (s != null && _playing(s.token)) s.partsDir};
  }
}

/// Bytes on disk under the voice root (the installed voice, and any partial download's `.part` files).
/// Synchronous: the root holds a handful of files.
int voiceRootBytes(Directory root) {
  if (!root.existsSync()) return 0;
  var n = 0;
  try {
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      try {
        n += e.lengthSync();
      } on FileSystemException {
        // Vanished meanwhile.
      }
    }
  } on FileSystemException {
    // The folder went away while listing.
  }
  return n;
}

enum _Outcome { done, cancelled, loadError, failed }

class PrepareController extends Notifier<PrepareStatus> {
  PrepareController(this.poemId);

  final int poemId;

  @override
  PrepareStatus build() => const PrepareIdle();

  /// This poem's latest run.
  _Run? _mine;

  /// Reads [p] (what the cache lacks), joins it, and plays it when [playWhenDone] — unless another prepare
  /// started meanwhile, [quiet] was called, or the player moved on to something else. [artist] is the localized
  /// «خوانش ماشینی». Completes when the prepare ends (done, failed or cancelled).
  ///
  /// Where the player supports playlists, playback may start before the poem is fully read: as soon as
  /// [shouldStart] holds, the beyts read so far are streamed, and each later one is added as it is read. The
  /// reading is still joined at the end, and the joined file is used from the next play.
  ///
  /// The poem is read with 8, 6 or 4 flow steps ([chooseSteps]), chosen once from the remembered speed
  /// ([voiceT8Pref]) and recorded in its parts folder, so a resumed reading keeps them.
  Future<void> start(Poem p, {required bool playWhenDone, required String artist}) async {
    final current = ref.read(_currentPrepareProvider);
    final outcomeOf = Completer<_Outcome>();
    StreamSubscription<BeytAudio>? sub;
    VoiceWorker? worker;

    /// The voice stream this run started, if any.
    VoiceStreamToken? token;

    /// This call's run (set just below, before anything can cancel it).
    late final _Run run;

    /// Stops the player if it is still playing this run's stream.
    void stopOurStream() {
      final t = token;
      if (t == null || !ref.mounted) return;
      final pc = ref.read(playerProvider.notifier);
      if (pc.isCurrentStream(t)) unawaited(pc.stop()); // resets the player state at once
    }

    void cancelRun() {
      run.playWhenDone = false; // a write or item still in flight must not start a stream
      sub?.cancel();
      worker?.cancel();
      stopOurStream();
      if (!outcomeOf.isCompleted) outcomeOf.complete(_Outcome.cancelled);
      if (ref.mounted) state = const PrepareIdle();
    }

    run = _mine = current.next(p.id, playWhenDone, cancelRun);
    bool isCurrent() => current.isCurrent(run) && ref.mounted;

    final voice = ref.read(voiceProvider);
    final cache = ref.read(voiceCacheProvider);
    worker = ref.read(voiceWorkerProvider);
    final beyts = beytsOf(p);
    if (voice is! VoiceReady || cache == null || worker == null || beyts.isEmpty) {
      current.finished(run);
      state = const PrepareFailed();
      return;
    }
    final player = ref.read(playerProvider);
    final startPoem = player.poem?.id, startRecitation = player.recitation?.id;

    Future<void> finish(File wav) async {
      final sync = cache.syncOf(p.id, cache.keyOf(p, voice.version));
      current.finished(run);
      state = Prepared(wav, sync);
      if (token != null) return; // already playing as a stream; the joined file is for the next play
      final now = ref.read(playerProvider);
      if (run.playWhenDone && now.poem?.id == startPoem && now.recitation?.id == startRecitation) {
        await ref.read(playerProvider.notifier).playVoice(p, wav, sync, artist: artist);
      }
    }

    /// How many beyts the stream has, in order.
    var fed = 0;

    void fail() {
      current.finished(run);
      // A stream short of beyts would wait for one that never comes; one that has them all plays on.
      if (fed < beyts.length) stopOurStream();
      state = const PrepareFailed();
    }

    final key = cache.keyOf(p, voice.version);
    run.partsDir = VoiceCache.partsName(p.id, key);
    final hit = cache.done(p.id, key);
    if (hit != null) return finish(hit);

    final have = cache.partsHave(p.id, key);
    final missing = [
      for (final b in beyts)
        if (!have.contains(b.req.index)) b.req,
    ];
    var done = beyts.length - missing.length;
    state = Preparing(done, beyts.length);

    // --- Flow steps: fixed for the poem ---
    final prefs = ref.read(sharedPrefsProvider);
    final t8Key = voiceT8Pref(voice.version);
    final maxSteps = _maxSteps(voice.dir);
    final recorded = cache.partsSteps(p.id, key);
    // A resumed poem keeps the steps its parts were read with (parts from before steps were recorded used
    // phone.json's, and so does a damaged steps file); a fresh one chooses from the remembered speed and the
    // player's rate.
    final kept = recorded != null && kVoiceSteps.contains(recorded) && recorded <= maxSteps ? recorded : null;
    final steps = have.isNotEmpty
        ? kept ?? maxSteps
        : chooseSteps(t8: prefs.getDouble(t8Key), playbackRate: ref.read(playerProvider).speed, maxSteps: maxSteps);
    if (missing.isNotEmpty && recorded != steps) {
      final w = cache.setPartsSteps(p.id, key, steps).catchError((Object _) {}); // the part writes will fail too
      run.track(w);
      await w; // before the first part
      if (!isCurrent()) return; // cancelled meanwhile: it already reported PrepareIdle
    }

    // --- Early start: when to stream, and feeding the stream ---
    final n = beyts.length;
    final pc = ref.read(playerProvider.notifier);
    final clock = ref.read(voiceClockProvider);
    final chars = [for (final b in beyts) b.req.lines.join().replaceAll(RegExp(r'\s'), '').length];

    /// Audio seconds of each beyt made so far (read in this run or found in the cache), by index.
    final audioS = <int, double>{for (final i in have) i: cache.partSeconds(p.id, key, i)};

    /// The beyts on disk, ready to become stream items.
    final written = {...have};

    // The speed is a running average from the first beyt this run reads (its time may include the engine's load,
    // so only the beyts after it count): their audio over the wall time since it arrived. Silence put for an
    // unreadable beyt is left out.
    DateTime? firstAt, lastAt;
    var laterAudioS = 0.0;
    double? measured() {
      if (firstAt == null || lastAt == null || laterAudioS <= 0) return null;
      final wallUs = lastAt!.difference(firstAt!).inMicroseconds;
      return laterAudioS / (wallUs < 1000 ? 1000 : wallUs) * 1e6;
    }

    /// The measured speed as t8 (normalized to 8 steps), or null.
    double? measuredT8() {
      final m = measured();
      return m == null ? null : t8From(secondsPerAudioSecond: 1 / m, steps: steps);
    }

    /// The remembered t8, when it makes sense.
    double? rememberedT8() {
      final t8 = prefs.getDouble(t8Key);
      return t8 != null && t8.isFinite && t8 > 0 ? t8 : null;
    }

    // A stall means the device is slower than remembered: each one raises t8 by ×1/0.9.
    var stalls = 0;
    StreamSubscription<void>? stallSub;
    if (playWhenDone && pc.canStream) {
      stallSub = pc.voiceStalls.listen((_) {
        final t = token;
        if (!ref.mounted || t == null || !pc.isCurrentStream(t)) return;
        stalls++;
        final base = rememberedT8() ?? measuredT8();
        if (base != null) prefs.setDouble(t8Key, base / 0.9);
      });
    }

    void remember() {
      stallSub?.cancel();
      final t8 = measuredT8();
      if (t8 != null) prefs.setDouble(t8Key, t8 / math.pow(0.9, stalls));
    }

    /// Still free to play: not quieted, and the player has not moved on.
    bool mayPlay() {
      if (!run.playWhenDone || !pc.canStream) return false;
      final now = ref.read(playerProvider);
      return now.poem?.id == startPoem && now.recitation?.id == startRecitation;
    }

    bool startAllowed() {
      if (!mayPlay()) return false;
      if (written.length >= n || !written.contains(0)) return false; // all on disk: joined and played as in phase 1
      final now = ref.read(playerProvider);
      // The speed at this poem's own steps: measured, or predicted from the remembered t8.
      final t8 = rememberedT8();
      final speed = measured() ?? (t8 == null ? null : 1 / stepCost(t8: t8, steps: steps));
      if (speed == null) return false;
      return shouldStart(
        totalEstS: estimateTotal(chars, audioS),
        madeS: audioS.values.fold(0.0, (a, s) => a + s),
        firstBeytS: audioS[0]!,
        speed: speed,
        playbackRate: now.speed,
      );
    }

    Future<PlaylistItem> itemOf(int i) async {
      final f = await cache.beytItem(p.id, key, i, last: i == n - 1);
      final samples = (await f.length() - 44) ~/ 2;
      return PlaylistItem(
        uri: Uri.file(f.path),
        duration: Duration(microseconds: (samples * 1e6 / 24000).round()),
      );
    }

    /// Starts the stream once [startAllowed], then hands it every written beyt in order, and ends it after the
    /// last. Runs one at a time (see [kick]).
    Future<void> step() async {
      try {
        while (isCurrent()) {
          if (token == null) {
            if (!startAllowed()) return;
            final first = await itemOf(0);
            // Decided: beyts written meanwhile no longer matter, only a quiet or the player moving on.
            if (!isCurrent() || !mayPlay()) return;
            final t = token = pc.startVoiceStream(p, artist: artist, first: first, firstVOrder: beyts[0].vOrder);
            current.streamed = (token: t, partsDir: run.partsDir!); // a cache clear spares its items
            fed = 1;
            continue;
          }
          if (fed >= n || !written.contains(fed)) return;
          final item = await itemOf(fed);
          if (!isCurrent()) return;
          unawaited(pc.addVoiceBeyt(token!, item, beyts[fed].vOrder));
          fed++;
          if (fed == n) pc.endVoiceStream(token!); // at once: the last beyt has no trailing gap to cover a late end
        }
      } catch (_) {
        // An item could not be written: the stream stops growing, and the end of the run stops it.
      }
    }

    var feeding = Future<void>.value();
    void kick() {
      if (!playWhenDone || !pc.canStream) return;
      feeding = feeding.then((_) => step());
      run.track(feeding);
    }

    final writes = <Future<void>>[];
    void put(BeytAudio a, {bool silence = false}) {
      if (!silence) {
        final now = clock();
        if (firstAt == null) {
          firstAt = now;
        } else {
          lastAt = now;
          laterAudioS += a.pcm.length / a.sampleRate;
        }
      }
      audioS[a.index] = a.pcm.length / a.sampleRate;
      final w = cache.putBeyt(p.id, key, a);
      writes.add(w);
      run.track(w);
      w.then((_) {
        written.add(a.index);
        kick();
      }, onError: (Object _) {});
      done++;
      if (isCurrent()) state = Preparing(done, beyts.length);
    }

    kick(); // beyts found in the cache may be enough to start with a remembered speed

    if (missing.isEmpty) {
      outcomeOf.complete(_Outcome.done);
    } else {
      sub = worker
          .read(missing, metre: p.metre, steps: steps)
          .listen(
            put,
            onError: (Object e) {
              if (e is VoiceReadError) {
                put(BeytAudio(e.index, _silence(), 24000), silence: true);
              } else if (!outcomeOf.isCompleted) {
                sub?.cancel();
                outcomeOf.complete(e is VoiceEngineLoadError ? _Outcome.loadError : _Outcome.failed);
              }
            },
            onDone: () {
              if (!outcomeOf.isCompleted) outcomeOf.complete(_Outcome.done);
            },
          );
    }

    final outcome = await outcomeOf.future;
    remember();
    if (outcome == _Outcome.cancelled || !isCurrent()) {
      // Let the beyts already read land on disk, so a resumed prepare finds them.
      await run.settle();
      return;
    }
    try {
      await Future.wait(writes);
    } catch (_) {
      if (isCurrent()) fail();
      return;
    }
    if (!isCurrent()) return;
    // A start may be in flight: let the feeder settle before choosing between stream and phase 1. If it streams,
    // every beyt is then in the stream and the stream has ended.
    kick();
    await feeding;
    if (!isCurrent()) return;
    switch (outcome) {
      case _Outcome.loadError:
        current.finished(run);
        stopOurStream(); // as in fail(): it would wait for a beyt that never comes
        await ref.read(voiceProvider.notifier).markCorrupt();
        if (ref.mounted) state = const PrepareFailed();
        return;
      case _Outcome.failed:
        fail();
        return;
      case _Outcome.cancelled:
      case _Outcome.done:
        break;
    }
    final parts = cache.partsHave(p.id, key);
    if (!beyts.every((b) => parts.contains(b.req.index))) {
      fail();
      return;
    }
    final File wav;
    try {
      // A stream may still be playing the beyt items: they stay until eviction.
      final joining = cache.join(p.id, key, [for (final b in beyts) b.vOrder], keepItems: token != null);
      run.track(joining);
      wav = await joining;
    } catch (_) {
      if (isCurrent()) fail();
      return;
    }
    if (!isCurrent()) return;
    if (token != null && fed < n) stopOurStream(); // a beyt never made it into the stream
    await finish(wav);
  }

  /// Stops this poem's prepare, if it is the running one.
  void cancel() {
    final current = ref.read(_currentPrepareProvider);
    final mine = _mine;
    if (mine != null && identical(current.running, mine)) {
      current.cancelCurrent();
    }
  }

  /// Lets this poem's running prepare finish without playing (the reader left the poem). Other poems' prepares
  /// are untouched.
  void quiet() {
    _mine?.playWhenDone = false;
  }
}

/// `kBeytGap × 2` of silence at 24 kHz: stands in for a beyt that failed to read.
Int16List _silence() => Int16List((24000 * (kBeytGap * 2).inMicroseconds / 1000000).round());

/// One prepare state per poem id.
final voicePrepareProvider = NotifierProvider.family<PrepareController, PrepareStatus, int>(PrepareController.new);
