import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'api_client.dart';

/// A network image kept on disk: poet portraits and manuscript images are fetched once and
/// then read from the app's cache folder, also offline and after a restart.
/// (Flutter's NetworkImage keeps pictures in memory only, so they were fetched every launch.)
@immutable
class DiskImage extends ImageProvider<DiskImage> {
  const DiskImage(this.url);

  final String url;

  static Directory? _dir;
  static Future<Uint8List> Function(Uri)? _fetch;

  /// Set once at start-up (and by tests). Without a folder, pictures are only kept in memory.
  static void configure({required Directory? directory, Future<Uint8List> Function(Uri)? fetch}) {
    _dir = directory;
    _fetch = fetch;
  }

  /// Deletes every stored picture (Settings → clear cache).
  static Future<void> clear() async {
    final d = _dir;
    if (d == null || !d.existsSync()) return;
    for (final f in d.listSync()) {
      await f.delete(recursive: true);
    }
  }

  static final Dio _dio = createDio();

  static Future<Uint8List> _download(Uri u) async {
    final r = await _dio.getUri<List<int>>(
      u,
      options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
    );
    return Uint8List.fromList(r.data!);
  }

  File? get _file {
    final d = _dir;
    if (d == null) return null;
    // A short, filesystem-safe name from the url.
    final name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return File('${d.path}${Platform.pathSeparator}${name.length > 120 ? name.substring(name.length - 120) : name}');
  }

  Future<Uint8List> _bytes() async {
    final f = _file;
    if (f != null && f.existsSync()) {
      final b = await f.readAsBytes();
      if (b.isNotEmpty) return b;
    }
    final b = await (_fetch ?? _download)(Uri.parse(url));
    if (b.isEmpty) throw StateError('empty image');
    if (f != null) {
      try {
        await f.parent.create(recursive: true);
        await f.writeAsBytes(b, flush: true);
      } catch (_) {
        // A full or read-only disk only costs us the cache.
      }
    }
    return b;
  }

  @override
  Future<DiskImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1, debugLabel: url);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async =>
      decode(await ui.ImmutableBuffer.fromUint8List(await _bytes()));

  @override
  bool operator ==(Object other) => other is DiskImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskImage($url)';
}
