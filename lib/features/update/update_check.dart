import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/net/api_client.dart';
import '../../data/providers.dart';
import '../../version.dart';

/// Only the copies published on GitHub look for a new version: the release workflow builds the APKs and the desktop
/// apps with `--dart-define=GANJ_UPDATE_CHECK=true`. Everything else (the .aab for Google Play and Cafe Bazaar, which
/// update the app themselves, and any build made by hand) never asks GitHub.
const kUpdateCheckBuild = bool.fromEnvironment('GANJ_UPDATE_CHECK');

/// The newest published release of Ganj.
const kLatestReleaseApi = 'https://api.github.com/repos/aminkvh/Ganj/releases/latest';

/// GitHub is asked at most this often.
const kUpdateCheckEvery = Duration(days: 1);

const _kCheckedAt = 'update.checkedAt', _kLatest = 'update.latest', _kUrl = 'update.url';
const _kDismissed = 'update.dismissed';

/// A newer version on GitHub, and the page to download it from.
class UpdateInfo {
  const UpdateInfo(this.version, this.url);
  final String version;
  final String url;

  @override
  bool operator ==(Object other) => other is UpdateInfo && other.version == version && other.url == url;
  @override
  int get hashCode => Object.hash(version, url);
}

/// Is [a] a later version than [b]? Both are "1.6.0"-style; a missing part counts as 0, anything unparsable as not newer.
bool isNewerVersion(String a, String b) {
  List<int>? parts(String v) {
    final p = v.split('+').first.split('.');
    final out = <int>[];
    for (final s in p) {
      final n = int.tryParse(s);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  final x = parts(a), y = parts(b);
  if (x == null || y == null) return false;
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// Reads GitHub's latest-release JSON: (version without the "v", page URL), or null if it is not a usable release.
(String, String)? parseLatestRelease(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    if (j['draft'] == true || j['prerelease'] == true) return null;
    final tag = j['tag_name'] as String;
    final url = j['html_url'] as String;
    if (!url.startsWith('https://github.com/aminkvh/Ganj/')) return null;
    return (tag.startsWith('v') ? tag.substring(1) : tag, url);
  } catch (_) {
    return null;
  }
}

/// Looks for a newer Ganj on GitHub at most once a day, remembering the answer between launches. Offline or on any
/// error it quietly keeps the last answer.
class UpdateChecker {
  UpdateChecker({
    required this.prefs,
    required this.fetch,
    this.current = kAppVersion,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SharedPreferences prefs;
  final Future<String> Function() fetch;
  final String current;
  final DateTime Function() now;

  Future<UpdateInfo?> check() async {
    final at = prefs.getInt(_kCheckedAt);
    final due = at == null || now().difference(DateTime.fromMillisecondsSinceEpoch(at)) >= kUpdateCheckEvery;
    if (due) {
      try {
        final r = parseLatestRelease(await fetch());
        if (r != null) {
          await prefs.setString(_kLatest, r.$1);
          await prefs.setString(_kUrl, r.$2);
        }
        await prefs.setInt(_kCheckedAt, now().millisecondsSinceEpoch);
      } catch (_) {
        // Offline or GitHub unavailable: try again next launch.
      }
    }
    final latest = prefs.getString(_kLatest), url = prefs.getString(_kUrl);
    if (latest == null || url == null || !isNewerVersion(latest, current)) return null;
    return UpdateInfo(latest, url);
  }
}

/// The checker, or null where the app never looks for updates (any build but GitHub's, the web; tests override it).
final updateCheckerProvider = Provider<UpdateChecker?>((ref) {
  if (!kUpdateCheckBuild || kIsWeb) return null;
  final dio = createDio();
  return UpdateChecker(
    prefs: ref.watch(sharedPrefsProvider),
    fetch: () async {
      final r = await dio.get<String>(kLatestReleaseApi, options: Options(headers: {'Accept': 'application/vnd.github+json'}));
      return r.data!;
    },
  );
});

/// A newer version to tell the reader about, or null (no checker, up to date, or not known yet).
final updateProvider = FutureProvider<UpdateInfo?>((ref) async => ref.watch(updateCheckerProvider)?.check());

/// The version whose home-screen notice the reader closed; Settings still shows it.
final updateDismissedProvider = NotifierProvider<UpdateDismissed, String?>(UpdateDismissed.new);

class UpdateDismissed extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPrefsProvider).getString(_kDismissed);

  void dismiss(String version) {
    ref.read(sharedPrefsProvider).setString(_kDismissed, version);
    state = version;
  }
}
