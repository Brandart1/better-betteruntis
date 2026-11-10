/// Minimal JSON-RPC 2.0 transport over dio for the WebUntis internal API.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/interfaces.dart';
import 'totp.dart';

typedef DebugEntry = ({String method, DateTime at, String json});

class JsonRpcClient {
  JsonRpcClient({Dio? dio, DateTime Function()? now, this.debugCapacity = 30})
    : _dio = dio ?? Dio(),
      _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;
  final int debugCapacity;
  final _log = ListQueue<DebugEntry>();
  var _nextId = 0;

  /// Most recent raw responses, oldest first.
  List<DebugEntry> get debugLog => List.unmodifiable(_log);

  /// Builds the `auth` object: clientTime and otp share one timestamp.
  Map<String, Object> auth(UntisCredentials creds) {
    final ms = _now().millisecondsSinceEpoch;
    return {
      'user': creds.username,
      'otp': creds.anonymous ? 0 : totp(creds.secret, ms),
      'clientTime': ms,
    };
  }

  /// Calls [method] with a single params object and returns `result`.
  Future<Object?> call(
    String url,
    String method,
    Map<String, Object?> params,
  ) async {
    final body = jsonEncode({
      'id': 'bbu-${++_nextId}',
      'jsonrpc': '2.0',
      'method': method,
      'params': [params],
    });
    final String raw;
    try {
      final resp = await _dio.post<String>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.plain,
          contentType: 'application/json',
          headers: {'Accept': 'application/json, application/json-rpc'},
          validateStatus: (_) => true,
        ),
      );
      raw = resp.data ?? '';
      _record(method, raw);
      final status = resp.statusCode ?? 0;
      if (raw.trim().isEmpty && (status < 200 || status >= 300)) {
        throw UntisException(0, 'HTTP $status');
      }
    } on DioException catch (e) {
      throw UntisException(0, 'Network error: ${e.message ?? e.type.name}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw UntisException(0, 'Invalid JSON response: ${e.message}');
    }
    if (decoded is! Map) {
      throw const UntisException(0, 'Unexpected JSON-RPC response');
    }
    final error = decoded['error'];
    if (error != null) {
      if (error is Map) {
        final code = error['code'];
        final data = error['data'];
        var message = error['message']?.toString() ?? '';
        if (message.isEmpty && data is Map) {
          message = data['message']?.toString() ?? '';
        }
        throw UntisException(
          code is num ? code.toInt() : int.tryParse('$code') ?? -1,
          message.isEmpty ? 'Unknown error' : message,
        );
      }
      throw UntisException(-1, error.toString());
    }
    if (!decoded.containsKey('result')) {
      throw const UntisException(0, 'JSON-RPC response without result');
    }
    return decoded['result'];
  }

  void _record(String method, String raw) {
    _log.addLast((method: method, at: _now(), json: raw));
    while (_log.length > debugCapacity) {
      _log.removeFirst();
    }
  }
}
