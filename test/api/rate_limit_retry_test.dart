import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:better_betteruntis/api/rate_limit_retry.dart';
import 'package:better_betteruntis/core/interfaces.dart';
import 'package:better_betteruntis/data/absence_summary_repository_impl.dart'
    show isClassListRefusal;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers from [answer]; counts requests running at the same time.
class _Server implements HttpClientAdapter {
  _Server(this.answer);
  final Future<ResponseBody> Function(RequestOptions o, int n) answer;
  var calls = 0;
  var running = 0;
  var maxRunning = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      return await answer(o, calls);
    } finally {
      running--;
    }
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(
  int status, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode({'ok': status}),
  status,
  headers: headers,
);

void main() {
  final waits = <Duration>[];
  Dio dio(_Server server) {
    final d = Dio()..httpClientAdapter = server;
    d.interceptors.add(RateLimitRetry(d, sleep: (w) async => waits.add(w)));
    return d;
  }

  setUp(waits.clear);

  test('429 is repeated after Retry-After, then the answer passes', () async {
    final server = _Server(
      (o, n) async => n == 1
          ? _body(
              429,
              headers: {
                'retry-after': ['3'],
              },
            )
          : _body(200),
    );
    final r = await dio(
      server,
    ).get<String>('https://h/x', options: Options(validateStatus: (_) => true));
    expect(r.statusCode, 200);
    expect(server.calls, 2);
    expect(waits, [const Duration(seconds: 3)]);
  });

  test('gives up after two repeats and caps the wait', () async {
    final server = _Server(
      (o, n) async => _body(
        429,
        headers: {
          'retry-after': ['600'],
        },
      ),
    );
    final r = await dio(
      server,
    ).get<String>('https://h/x', options: Options(validateStatus: (_) => true));
    expect(r.statusCode, 429);
    expect(server.calls, 3);
    expect(waits, everyElement(RateLimitRetry.maxWait));
  });

  test('other errors are not repeated', () async {
    final server = _Server((o, n) async => _body(503));
    final r = await dio(
      server,
    ).get<String>('https://h/x', options: Options(validateStatus: (_) => true));
    expect(r.statusCode, 503);
    expect(server.calls, 1);
  });

  test('requests are not held back: all run at once', () async {
    final gate = Completer<void>();
    final server = _Server((o, n) async {
      await gate.future;
      return _body(200);
    });
    final d = dio(server);
    final all = [for (var i = 0; i < 10; i++) d.get<String>('https://h/$i')];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.running, 10);
    gate.complete();
    await Future.wait(all);
  });

  test('a refused class list ("invalid user role") is recognised', () {
    expect(
      isClassListRefusal(const UntisException(-1, 'invalid user role')),
      isTrue,
    );
    expect(
      isClassListRefusal(const UntisException(UntisException.noRight, 'x')),
      isTrue,
    );
    expect(isClassListRefusal(const UntisException(-1, 'HTTP 500')), isFalse);
  });
}
