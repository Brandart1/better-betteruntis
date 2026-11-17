/// Paces requests to the school's server and retries refused ones.
///
/// A real teacher account hit the server's rate limit in the class register
/// (2026-11-17): one screen loads the lesson, the history, homework, reasons
/// and pupil photos at once. This interceptor lets at most [maxParallel]
/// requests per host run at a time, keeps [minGap] between their starts, and
/// repeats a request the server answered with HTTP 429 (or 503 with a
/// `Retry-After`) up to [maxRetries] times after waiting.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

class RequestThrottle extends Interceptor {
  RequestThrottle(
    this._dio, {
    this.maxParallel = 3,
    this.minGap = const Duration(milliseconds: 120),
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
       _now = now ?? DateTime.now;

  final Dio _dio;
  final int maxParallel;
  final Duration minGap;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  final _hosts = <String, _Host>{};

  static const _slotKey = 'bbuThrottleSlot';
  static const _retryKey = 'bbuThrottleRetry';

  /// Longest wait for one retry, whatever `Retry-After` says.
  static const maxWait = Duration(seconds: 10);

  _Host _host(RequestOptions o) =>
      _hosts.putIfAbsent(o.uri.host, () => _Host());

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final h = _host(options);
    if (h.running >= maxParallel) {
      final turn = Completer<void>();
      h.queue.add(turn);
      await turn.future; // The finishing request handed over its slot.
    } else {
      h.running++;
    }
    final gap = h.lastStart == null
        ? Duration.zero
        : minGap - _now().difference(h.lastStart!);
    if (gap > Duration.zero) await _sleep(gap);
    h.lastStart = _now();
    options.extra[_slotKey] = true;
    handler.next(options);
  }

  void _release(RequestOptions o) {
    if (o.extra.remove(_slotKey) != true) return;
    final h = _host(o);
    if (h.queue.isNotEmpty) {
      h.queue.removeAt(0).complete();
    } else {
      h.running--;
    }
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final o = response.requestOptions;
    _release(o);
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

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _release(err.requestOptions);
    handler.next(err);
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

class _Host {
  var running = 0;
  final queue = <Completer<void>>[];
  DateTime? lastStart;
}
