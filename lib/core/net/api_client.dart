import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const kApiBase = 'https://api.ganjoor.net';
const kUserAgent =
    'Ganj/1.0 (+https://github.com/aminkvh/Ganj; unofficial open-source Persian poetry reader built on the Ganjoor API)';

Dio createDio({HttpClientAdapter? adapter}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      headers: {'User-Agent': kUserAgent, 'Accept': 'application/json'},
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  if (kDebugMode && adapter == null) {
    dio.interceptors.add(
      LogInterceptor(requestHeader: false, responseHeader: false, logPrint: (o) => debugPrint('[net] $o')),
    );
  }
  return dio;
}
