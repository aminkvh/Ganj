import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/net/api_client.dart';
import '../core/net/http_cache.dart';
import 'api/dto/cat.dart';
import 'api/dto/poem.dart';
import 'api/dto/poet.dart';
import 'api/ganjoor_api.dart';
import 'db/app_db.dart';
import 'packs/local_poetry.dart';
import '../features/player/audio_store.dart';
import 'repo/poetry_repository.dart';
import '../core/text/content_en.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final appDbProvider = Provider<AppDb>((ref) => throw UnimplementedError('override in main'));

/// English poet names, centuries and genre words for the English interface (loaded at start).
final englishContentProvider = Provider<EnglishContent?>((ref) => null);

final ganjoorApiProvider = Provider<GanjoorApi>(
  (ref) => GanjoorApi(dio: createDio(), cache: HttpCache(ref.watch(appDbProvider))),
);
final poetryRepositoryProvider = Provider<PoetryRepository>(
  (ref) => PoetryRepository(
    ref.watch(ganjoorApiProvider),
    local: LocalPoetry(ref.watch(appDbProvider)),
    // Read lazily: the audio store itself depends on this repository.
    offlineRecitations: (poemId) async => await ref.read(audioStoreProvider)?.downloadedFor(poemId) ?? const [],
  ),
);

/// Riverpod 3 retries failed providers ~10× with backoff by default, which hides the
/// offline «تلاش دوباره» screen for tens of seconds; the UI offers a manual retry instead.
Duration? noAutoRetry(int retryCount, Object error) => null;

final centuriesProvider = FutureProvider<List<Century>>(
  (ref) => ref.watch(poetryRepositoryProvider).centuries(),
  retry: noAutoRetry,
);
final poetProvider = FutureProvider.autoDispose.family<PoetCat, int>(
  (ref, id) => ref.watch(poetryRepositoryProvider).poet(id),
  retry: noAutoRetry,
);
final catProvider = FutureProvider.autoDispose.family<PoetCat, int>(
  (ref, id) => ref.watch(poetryRepositoryProvider).cat(id),
  retry: noAutoRetry,
);
final poemProvider = FutureProvider.autoDispose.family<Poem, int>(
  (ref, id) => ref.watch(poetryRepositoryProvider).poem(id),
  retry: noAutoRetry,
);
