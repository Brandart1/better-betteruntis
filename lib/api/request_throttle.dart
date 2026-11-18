/// Limits parallel requests to the school's server and retries refused ones.
///
/// A real teacher account hit the server's rate limit in the class register
/// (2026-11-17). This interceptor lets at most [maxParallel] requests per
/// host run at a time and repeats a request the server answered with HTTP
/// 429 (or 503 with a `Retry-After`) up to [maxRetries] times after waiting.
///
/// Requests started inside [inBackground] (lib/core/request_priority.dart;
/// pupil photos, colleagues' lessons, refreshing cached weeks) wait behind
/// everything else and never take more than [maxBackground] slots, so what the user
/// is looking at is never stuck behind them (the +134 throttle queued all
/// requests in one line, which made every screen slow).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../core/request_priority.dart';

class RequestThrottle extends Interceptor {
  RequestThrottle(
    this._dio, {
    this.maxParallel = 6,
    this.maxBackground = 3,
    this.minGap = Duration.zero,
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
       _now = now ?? DateTime.now;

  final Dio _dio;
  final int maxParallel;

  /// Most background requests running at once per host (of [maxParallel]).
  final int maxBackground;
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
    final bg = isBackgroundRequest;
    if (!h.canStart(bg, maxParallel, maxBackground)) {
      final turn = Completer<void>();
      (bg ? h.backgroundQueue : h.queue).add(turn);
      await turn.future; // _pump started it (counted it already).
    } else {
      h.start(bg);
    }
    options.extra[_slotKey] = bg ? 'background' : 'foreground';
    final gap = h.lastStart == null
        ? Duration.zero
        : minGap - _now().difference(h.lastStart!);
    if (gap > Duration.zero) await _sleep(gap);
    h.lastStart = _now();
    handler.next(options);
  }

  void _release(RequestOptions o) {
    final slot = o.extra.remove(_slotKey);
    if (slot == null) return;
    final h = _host(o);
    h.finish(slot == 'background');
    h.pump(maxParallel, maxBackground);
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
  var runningBackground = 0;
  final queue = <Completer<void>>[];
  final backgroundQueue = <Completer<void>>[];
  DateTime? lastStart;

  bool canStart(bool background, int max, int maxBackground) {
    if (running >= max) return false;
    if (!background) return true;
    // Foreground waiting goes first; background keeps slots free.
    return queue.isEmpty && runningBackground < maxBackground;
  }

  void start(bool background) {
    running++;
    if (background) runningBackground++;
  }

  void finish(bool background) {
    running--;
    if (background) runningBackground--;
  }

  /// Starts waiting requests while slots are free, foreground first.
  void pump(int max, int maxBackground) {
    while (queue.isNotEmpty && running < max) {
      start(false);
      queue.removeAt(0).complete();
    }
    while (backgroundQueue.isNotEmpty && canStart(true, max, maxBackground)) {
      start(true);
      backgroundQueue.removeAt(0).complete();
    }
  }
}
