/// Repeats requests the school's server refused for the rate limit.
///
/// A real teacher account hit the server's rate limit in the class register
/// (2026-11-17). A request answered with HTTP 429 (or 503 with a
/// `Retry-After`) is repeated up to [RateLimitRetry.maxRetries] times after
/// waiting. Nothing else is held back: limiting how many requests run at
/// once (+134 to +144) made every screen slow and was removed in +145.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

class RateLimitRetry extends Interceptor {
  RateLimitRetry(
    this._dio, {
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final Dio _dio;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;

  static const _retryKey = 'bbuRateLimitRetry';

  /// Longest wait for one retry, whatever `Retry-After` says.
  static const maxWait = Duration(seconds: 10);

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final o = response.requestOptions;
    final wait = retryDelay(response.statusCode, response.headers, o);
    if (wait == null) return handler.next(response);
    o.extra[_retryKey] = ((o.extra[_retryKey] as int?) ?? 0) + 1;
    await _sleep(wait);
    try {
      handler.resolve(await _dio.fetch<dynamic>(o));
    } on DioException catch (e) {
      handler.reject(e);
    }
  }

  /// How long to wait before repeating [o], or null to pass the answer on:
  /// only 429 (and 503 with `Retry-After`), not more than [maxRetries]
  /// times, and never for a form upload (it can be sent only once).
  Duration? retryDelay(int? status, Headers headers, RequestOptions o) {
    final after = headers.value('retry-after');
    final limited = status == 429 || (status == 503 && after != null);
    if (!limited || o.data is FormData) return null;
    final tries = (o.extra[_retryKey] as int?) ?? 0;
    if (tries >= maxRetries) return null;
    final seconds = int.tryParse(after?.trim() ?? '');
    final wait = seconds != null
        ? Duration(seconds: seconds)
        : Duration(seconds: 2 * (tries + 1));
    return Duration(
      milliseconds: math.min(wait.inMilliseconds, maxWait.inMilliseconds),
    );
  }
}
