import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/text/persian_normalize.dart';
import '../../data/packs/pack_catalog.dart';
import '../../data/packs/pack_importer.dart';
import '../../data/packs/pack_installer.dart';
import '../../data/providers.dart';
import '../player/audio_store.dart';

final packCatalogProvider = FutureProvider<List<PackInfo>>(
  (ref) => ref.watch(ganjoorApiProvider).packCatalog(),
  retry: noAutoRetry,
);

/// Total download size of the installed packs; refreshes with [installedPacksProvider].
final installedPacksBytesProvider = FutureProvider<int>((ref) async {
  await ref.watch(installedPacksProvider.future);
  return installedPacksBytes(ref.watch(appDbProvider));
});

/// poetId → installed pack date.
final installedPacksProvider = FutureProvider<Map<int, String>>(
  (ref) => installedPackDates(ref.watch(appDbProvider)),
  retry: noAutoRetry,
);

final packInstallerProvider = Provider<PackInstaller>(
  (ref) => PackInstaller(ref.watch(appDbProvider), createDio(), Directory.systemTemp),
);

final downloadedAudioProvider = FutureProvider<List<DownloadedRecitation>>(
  (ref) async => await ref.watch(audioStoreProvider)?.listDownloaded() ?? const [],
  retry: noAutoRetry,
);

/// «۳۳۹ ک‌ب» / «۲٫۴ م‌ب».
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${localDigits((bytes / 1024).round())} ${latinNumbers ? 'KB' : 'ک‌ب'}';
  return '${localDecimal((bytes / (1024 * 1024)).toStringAsFixed(1))} ${latinNumbers ? 'MB' : 'م‌ب'}';
}
