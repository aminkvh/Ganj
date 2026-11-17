import 'package:dio/dio.dart' as dio;

import '../../data/api/dto/recitation.dart';
import '../../data/api/ganjoor_api.dart';
import '../player/audio_store.dart';

/// Every poem's top recitation for one poet, with the total download size.
class PoetAudioPlan {
  const PoetAudioPlan(this.recitations);

  final List<Recitation> recitations;

  int get totalBytes => recitations.fold(0, (s, r) => s + r.mp3Size);
}

/// Stops a running download job at once, the file in progress included (its part is kept,
/// so starting again continues it).
class CancelToken {
  bool _cancelled = false;

  /// Hands the stop to the file being fetched.
  final http = dio.CancelToken();

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    if (!http.isCancelled) http.cancel('stopped');
  }
}

/// Walks the category tree from [rootCatId]; `/api/audio/cattop1` is per category, not recursive.
Future<PoetAudioPlan> planPoetAudio(GanjoorApi api, int rootCatId) async {
  final out = <Recitation>[];
  final seen = <int>{};
  final queue = [rootCatId];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    if (!seen.add(id)) continue;
    final cat = await api.cat(id);
    queue.addAll(cat.cat.children.map((c) => c.id));
    out.addAll(await api.catTopRecitations(id));
  }
  return PoetAudioPlan(out);
}

/// Downloads one recitation at a time (polite to Ganjoor's servers); already-downloaded ones are skipped.
Future<void> downloadPlan(
  PoetAudioPlan plan,
  AudioStore store, {
  CancelToken? cancel,
  void Function(int done, int total)? onItem,
  void Function(Recitation failed)? onFailure,
  void Function(Recitation saved)? onSaved,
}) async {
  var done = 0;
  for (final r in plan.recitations) {
    if (cancel?.isCancelled ?? false) return;
    // One unreachable file must not abort a poet-wide download.
    try {
      if (!store.isDownloaded(r.id)) {
        await store.download(r, cancel: cancel?.http);
        onSaved?.call(r);
      }
    } catch (_) {
      if (cancel?.isCancelled ?? false) return; // stopped mid-file: not a failure
      onFailure?.call(r);
    }
    onItem?.call(++done, plan.recitations.length);
  }
}

/// Undoes a stopped job that is to be thrown away: deletes the files it saved and any part left
/// of the file it was fetching. Recitations that were on the device before the job stay.
Future<void> discardJob(AudioStore store, List<Recitation> plan, Iterable<int> saved) async {
  for (final id in saved) {
    await store.delete(id);
  }
  for (final r in plan) {
    await store.discardPartial(r.id);
  }
}
