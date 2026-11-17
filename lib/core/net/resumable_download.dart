import 'dart:io';

import 'package:dio/dio.dart';

/// Downloads [url] into [part], continuing what is already there with an HTTP Range request, so
/// a download that was paused (its [cancel] token cancelled) or cut off picks up where it stopped.
/// The file is left in place on any failure; delete it to discard. Completes when [part] holds the
/// whole file; a server that ignores Range (200) starts it over.
Future<void> resumableDownload(
  Dio dio,
  String url,
  File part, {
  CancelToken? cancel,
  Map<String, Object>? headers,
  void Function(int got, int total)? onBytes,
}) async {
  var have = part.existsSync() ? part.lengthSync() : 0;
  final res = await dio.get<ResponseBody>(
    url,
    cancelToken: cancel,
    options: Options(
      responseType: ResponseType.stream,
      headers: {...?headers, if (have > 0) 'Range': 'bytes=$have-'},
      // 416: nothing left after [have] (the file was complete, or the part is bad).
      validateStatus: (s) => s == 200 || s == 206 || s == 416,
    ),
  );
  if (res.statusCode == 416) {
    await res.data?.stream.drain<void>();
    final size = int.tryParse(res.headers.value('content-range')?.split('/').last ?? '');
    if (size != null && size == have) return; // already whole
    if (part.existsSync()) part.deleteSync();
    return resumableDownload(dio, url, part, cancel: cancel, headers: headers, onBytes: onBytes);
  }
  final resumed = res.statusCode == 206 && have > 0;
  if (!resumed) have = 0;
  final length = int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '') ?? -1;
  final total = length < 0 ? -1 : have + length;
  final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
  var got = have;
  try {
    onBytes?.call(got, total);
    await for (final chunk in res.data!.stream) {
      if (cancel?.isCancelled ?? false) {
        throw DioException.requestCancelled(requestOptions: res.requestOptions, reason: cancel!.cancelError?.error);
      }
      sink.add(chunk);
      got += chunk.length;
      onBytes?.call(got, total);
    }
  } finally {
    await sink.close();
  }
  if (total >= 0 && got != total) {
    throw DioException(requestOptions: res.requestOptions, message: 'incomplete download: $got of $total bytes');
  }
}
