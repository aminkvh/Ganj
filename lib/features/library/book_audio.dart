import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dto/recitation.dart';
import '../../data/api/ganjoor_api.dart';
import '../../data/providers.dart';
import '../player/audio_store.dart';
import 'library_providers.dart';
import 'poet_audio.dart';

/// Every published recitation in a book: the poems in [catId] and in its sub-books, in book order.
Future<List<Recitation>> listBookRecitations(
  GanjoorApi api,
  int catId, {
  CancelToken? cancel,
  void Function(int found)? onProgress,
}) async {
  const size = 200;
  final out = <Recitation>[];
  final queue = [catId];
  final seen = <int>{};
  while (queue.isNotEmpty) {
    if (cancel?.isCancelled ?? false) break;
    final id = queue.removeAt(0);
    if (!seen.add(id)) continue;
    final cat = await api.cat(id);
    if (cat.cat.poems.isNotEmpty) {
      for (var page = 1; ; page++) {
        if (cancel?.isCancelled ?? false) break;
        final rows = await api.catRecitationsPage(id, page, size: size);
        out.addAll(rows);
        onProgress?.call(out.length);
        if (rows.length < size) break;
      }
    }
    queue.insertAll(0, cat.cat.children.map((c) => c.id));
  }
  return out;
}

/// One way to download a book's recitations: the top one of each poem, all of them, or one reciter's.
class BookAudioChoice {
  const BookAudioChoice(this.recitations, {this.artist});

  final List<Recitation> recitations;

  /// The reciter, or null for the top-of-each-poem / everything choices.
  final String? artist;

  int get totalBytes => recitations.fold(0, (s, r) => s + r.mp3Size);

  /// How many poems it covers.
  int get poems => recitations.map((r) => r.poemId).toSet().length;
}

/// The top recitation of each poem: the one Ganjoor lists first.
BookAudioChoice topOfEach(List<Recitation> all) {
  final best = <int, Recitation>{};
  for (final r in all) {
    final b = best[r.poemId];
    if (b == null || r.audioOrder < b.audioOrder) best[r.poemId] = r;
  }
  return BookAudioChoice([
    for (final r in all)
      if (identical(best[r.poemId], r)) r,
  ]);
}

/// Each reciter's recitations, the most prolific first.
List<BookAudioChoice> byReciter(List<Recitation> all) {
  final m = <String, List<Recitation>>{};
  for (final r in all) {
    (m[r.artist.trim()] ??= []).add(r);
  }
  return [for (final e in m.entries) BookAudioChoice(e.value, artist: e.key)]..sort(
    (a, b) => b.recitations.length != a.recitations.length
        ? b.recitations.length.compareTo(a.recitations.length)
        : a.artist!.compareTo(b.artist!),
  );
}

/// A running book download: one at a time, app-wide, so it carries on when its sheet is closed.
class BookAudioJob {
  const BookAudioJob({
    required this.catId,
    required this.label,
    required this.done,
    required this.total,
    required this.cancel,
  });

  final int catId;
  final String label;
  final int done, total;
  final CancelToken cancel;

  BookAudioJob progress(int done) => BookAudioJob(catId: catId, label: label, done: done, total: total, cancel: cancel);
}

/// How a finished book download ended.
enum BookAudioResult { done, stopped, someFailed }

class BookAudioJobs extends Notifier<BookAudioJob?> {
  @override
  BookAudioJob? build() => null;

  /// Downloads [choice] (already-downloaded files are skipped); null if another download is running.
  Future<BookAudioResult?> start(int catId, String label, BookAudioChoice choice, AudioStore store) async {
    if (state != null) return null;
    final cancel = CancelToken();
    state = BookAudioJob(catId: catId, label: label, done: 0, total: choice.recitations.length, cancel: cancel);
    var failed = 0;
    try {
      await downloadPlan(
        PoetAudioPlan(choice.recitations),
        store,
        cancel: cancel,
        onItem: (done, _) => state = state?.progress(done),
        onFailure: (_) => failed++,
      );
    } finally {
      state = null;
      ref.invalidate(downloadedAudioProvider);
    }
    return cancel.isCancelled
        ? BookAudioResult.stopped
        : failed > 0
        ? BookAudioResult.someFailed
        : BookAudioResult.done;
  }

  void stop() => state?.cancel.cancel();
}

final bookAudioJobProvider = NotifierProvider<BookAudioJobs, BookAudioJob?>(BookAudioJobs.new);

/// A book's recitations, listed once per visit to its sheet.
final bookRecitationsProvider = FutureProvider.autoDispose.family<List<Recitation>, int>(
  (ref, catId) => listBookRecitations(ref.watch(ganjoorApiProvider), catId),
  retry: noAutoRetry,
);
