import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../core/net/api_client.dart';

/// Machine translation of verses. Ganjoor has no translations of its own, so:
/// - Android/iOS: Google ML Kit, on the device — free, unlimited, offline once its
///   language model (~30 MB) is downloaded, which the reader agrees to first;
/// - Windows/macOS/Linux: there is no light, free on-device translator for Persian, so the
///   free Google Translate web service is used (unofficial and best-effort; when it is
///   unreachable the reader is offered Google Translate in the browser).
abstract class Translator {
  /// True when [translate] works inside the app; false means "open in the browser".
  bool get inApp;

  /// True when language models must be downloaded first (and can be removed).
  bool get needsModel;

  /// Whether the language models for Persian → [to] are on the device.
  Future<bool> isReady(String to);

  /// Downloads the models for Persian → [to].
  Future<void> prepare(String to);

  /// Deletes the downloaded models for Persian → [to] (English is built in and stays).
  Future<void> remove(String to);

  Future<String> translate(String text, String to);
}

/// Languages offered as translation targets, each named in its own script.
const kTranslateTargets = {
  'en': 'English',
  'ar': 'العربية',
  'tr': 'Türkçe',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'ru': 'Русский',
  'ur': 'اردو',
};

/// Google Translate links are kept to this many characters of text: longer links fail.
const kMaxTranslateChars = 4000;

/// A Google Translate page for [text] (Persian → [to]); long text is cut at a line break.
Uri googleTranslateUri(String text, String to) {
  var t = text;
  if (t.length > kMaxTranslateChars) {
    final cut = t.lastIndexOf('\n', kMaxTranslateChars);
    t = t.substring(0, cut > 0 ? cut : kMaxTranslateChars);
  }
  return Uri.https('translate.google.com', '/', {'sl': 'fa', 'tl': to, 'text': t, 'op': 'translate'});
}

/// Desktop: no translation inside the app.
class BrowserTranslator implements Translator {
  const BrowserTranslator();

  @override
  bool get inApp => false;

  @override
  bool get needsModel => false;

  @override
  Future<bool> isReady(String to) async => false;

  @override
  Future<void> prepare(String to) async {}

  @override
  Future<void> remove(String to) async {}

  @override
  Future<String> translate(String text, String to) => throw UnsupportedError('translate in the browser');
}

/// Android/iOS: Google ML Kit on-device translation.
class MlKitTranslator implements Translator {
  MlKitTranslator({ModelManager? models}) : _models = models ?? OnDeviceTranslatorModelManager();

  final ModelManager _models;
  final _translators = <String, OnDeviceTranslator>{};

  static const _fa = 'fa';

  @override
  bool get inApp => true;

  @override
  bool get needsModel => true;

  // Both sides need a model on the phone. (English may already be there — checked, not assumed.)
  List<String> _needed(String to) => {_fa, to}.toList();

  @override
  Future<bool> isReady(String to) async {
    for (final m in _needed(to)) {
      if (!await _models.isModelDownloaded(m)) return false;
    }
    return true;
  }

  @override
  Future<void> prepare(String to) async {
    for (final m in _needed(to)) {
      // ML Kit reports a failed download by returning false, e.g. when Google's servers
      // can't be reached from the reader's network.
      if (!await _models.isModelDownloaded(m) && !await _models.downloadModel(m, isWifiRequired: false)) {
        throw StateError('translation model "$m" could not be downloaded');
      }
    }
  }

  @override
  Future<void> remove(String to) async {
    await _translators.remove(to)?.close();
    for (final m in _needed(to)) {
      await _models.deleteModel(m);
    }
  }

  @override
  Future<String> translate(String text, String to) => _translators
      .putIfAbsent(
        to,
        () => OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.persian,
          targetLanguage: TranslateLanguage.values.firstWhere((l) => l.bcpCode == to),
        ),
      )
      .translateText(text);
}

/// Desktop: Google Translate's free web service, inside the app. Unofficial: it can be
/// rate-limited or blocked at any time, so nothing depends on it — a failure just shows
/// "open in Google Translate". Beyts asked for in the same moment share one request, and
/// answers are remembered, to stay polite.
class GoogleWebTranslator implements Translator {
  GoogleWebTranslator({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;
  final _cache = <String, Future<String>>{};
  final _pending = <String, List<(String, Completer<String>)>>{};
  bool _flushScheduled = false;

  static const _maxBatch = 16, _maxChars = 1500;

  @override
  bool get inApp => true;

  @override
  bool get needsModel => false;

  @override
  Future<bool> isReady(String to) async => true;

  @override
  Future<void> prepare(String to) async {}

  @override
  Future<void> remove(String to) async {}

  @override
  Future<String> translate(String text, String to) {
    final key = '$to|$text';
    return _cache.putIfAbsent(key, () {
      final c = Completer<String>();
      _pending.putIfAbsent(to, () => []).add((text, c));
      if (!_flushScheduled) {
        _flushScheduled = true;
        Future(_flush);
      }
      // A failed answer is forgotten, so the next attempt asks again.
      c.future.then<void>(
        (_) {},
        onError: (Object _) {
          _cache.remove(key);
        },
      );
      return c.future;
    });
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final work = Map.of(_pending);
    _pending.clear();
    for (final MapEntry(key: to, value: items) in work.entries) {
      for (final batch in _batches(items)) {
        await _send(batch, to);
      }
    }
  }

  Iterable<List<(String, Completer<String>)>> _batches(List<(String, Completer<String>)> items) sync* {
    var batch = <(String, Completer<String>)>[];
    var chars = 0;
    for (final item in items) {
      if (batch.isNotEmpty && (batch.length >= _maxBatch || chars + item.$1.length > _maxChars)) {
        yield batch;
        batch = [];
        chars = 0;
      }
      batch.add(item);
      chars += item.$1.length;
    }
    if (batch.isNotEmpty) yield batch;
  }

  Future<void> _send(List<(String, Completer<String>)> batch, String to) async {
    try {
      final r = await _dio.get<String>(
        'https://clients5.google.com/translate_a/t',
        queryParameters: {
          'client': 'dict-chrome-ex',
          'sl': 'fa',
          'tl': to,
          'q': [for (final (t, _) in batch) t],
        },
      );
      final list = jsonDecode(r.data!) as List;
      if (list.length != batch.length) throw const FormatException('answer count');
      for (var i = 0; i < batch.length; i++) {
        final v = list[i];
        batch[i].$2.complete(v is List ? v.first as String : v as String);
      }
      return;
    } catch (_) {
      // Fall through to the second address, one beyt at a time.
    }
    for (final (text, c) in batch) {
      try {
        final r = await _dio.get<String>(
          'https://translate.googleapis.com/translate_a/single',
          queryParameters: {'client': 'gtx', 'sl': 'fa', 'tl': to, 'dt': 't', 'q': text},
        );
        final parts = (jsonDecode(r.data!) as List).first as List;
        c.complete(parts.map((p) => (p as List).first as String).join());
      } catch (e, st) {
        c.completeError(e, st);
      }
    }
  }
}

/// Phones: on-device ML Kit while it works; the moment any step of it fails (no working Google
/// Play services, model downloads blocked — common on phones in Iran), translation continues
/// online through [backup] instead of failing silently. If that fails too, the error reaches
/// the translation line, which offers Google Translate in the browser.
class ResilientTranslator implements Translator {
  ResilientTranslator({required this.primary, required this.backup});

  final Translator primary;
  final Translator backup;

  /// Set once ML Kit has failed; from then on the backup is used.
  bool _primaryBroken = false;

  @override
  bool get inApp => true;

  @override
  bool get needsModel => !_primaryBroken && primary.needsModel;

  @override
  Future<bool> isReady(String to) async {
    if (_primaryBroken) return true;
    try {
      return await primary.isReady(to);
    } catch (_) {
      _primaryBroken = true;
      return true;
    }
  }

  @override
  Future<void> prepare(String to) async {
    if (_primaryBroken) return;
    try {
      await primary.prepare(to);
    } catch (_) {
      _primaryBroken = true;
    }
  }

  @override
  Future<void> remove(String to) async {
    try {
      await primary.remove(to);
    } catch (_) {}
  }

  @override
  Future<String> translate(String text, String to) async {
    if (!_primaryBroken) {
      try {
        return await primary.translate(text, to);
      } catch (_) {
        _primaryBroken = true;
      }
    }
    return backup.translate(text, to);
  }
}

final translatorProvider = Provider<Translator>(
  (ref) => !kIsWeb && (Platform.isAndroid || Platform.isIOS)
      ? ResilientTranslator(primary: MlKitTranslator(), backup: GoogleWebTranslator())
      : GoogleWebTranslator(),
);
