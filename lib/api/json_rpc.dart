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
  final _log = ListQueue<(int, DebugEntry)>();

  /// Latest entry per sticky method ([_sticky]); never pushed out by
  /// [debugCapacity], so the login response is still there later.
  final _pinned = <String, (int, DebugEntry)>{};
  var _nextId = 0;
  var _seq = 0;

  /// Methods whose latest response stays in the log regardless of capacity.
  static const _sticky = {'getUserData2017', 'getOfficeHours2017'};

  /// Methods whose `result` is a secret (the app secret, a bearer token):
  /// only its shape is recorded.
  static const _secretResults = {'getAppSharedSecret', 'getAuthToken'};

  /// Most recent raw responses, oldest first. Requests (and so passwords,
  /// OTPs and secrets) are never recorded, only responses and a label.
  List<DebugEntry> get debugLog {
    final all = [..._pinned.values, ..._log]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return List.unmodifiable(all.map((e) => e.$2));
  }

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
      _recordResponse(
        method,
        params['klasseId'] == null ? method : '$method|${params['klasseId']}',
        _label(method, params, resp.statusCode),
        raw,
      );
      final status = resp.statusCode ?? 0;
      if (raw.trim().isEmpty && (status < 200 || status >= 300)) {
        throw UntisException(0, 'HTTP $status');
      }
    } on DioException catch (e) {
      final timedOut = switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => true,
        _ => false,
      };
      final msg = timedOut
          ? 'Timeout (${e.type.name})'
          : 'Network error: ${e.message ?? e.type.name}';
      _record(_label(method, params, null), jsonEncode({'_requestFailed': msg}));
      throw UntisException(timedOut ? UntisException.timeout : 0, msg);
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

  /// "getTimetable2017 STUDENT#123 2026-11-09..2026-11-15 [HTTP 200]" — enough
  /// to tell entries apart, without credentials.
  static String _label(String method, Map<String, Object?> p, int? status) {
    final parts = <String>[method];
    if (p['type'] != null || p['id'] != null) parts.add('${p['type']}#${p['id']}');
    if (p['klasseId'] != null) parts.add('klasseId=${p['klasseId']}');
    if (p['studentId'] != null) parts.add('studentId=${p['studentId']}');
    if (p['startDate'] != null) {
      parts.add(
        p['endDate'] == null
            ? '${p['startDate']}'
            : '${p['startDate']}..${p['endDate']}',
      );
    }
    if (p['date'] != null) parts.add('${p['date']}');
    parts.add(status == null ? '[no response]' : '[HTTP $status]');
    return parts.join(' ');
  }

  /// Records a non-JSON-RPC request (e.g. REST probes) in the debug log.
  void record(String label, String raw) => _record(label, raw);

  /// [pinKey] tells sticky entries apart (e.g. office hours per klasseId).
  void _recordResponse(String method, String pinKey, String label, String raw) {
    if (_secretResults.contains(method)) {
      _record(label, redactResult(raw));
      return;
    }
    if (!_sticky.contains(method)) {
      _record(label, raw);
      return;
    }
    final at = _now();
    final json = redactSecretKeys(raw);
    _pinned[pinKey] = (_seq++, (method: label, at: at, json: json));
    if (method == 'getUserData2017') {
      final summary = userDataSummary(json);
      if (summary != null) {
        _pinned['$method/userData'] = (
          _seq++,
          (
            method: label.replaceFirst(
              method,
              '$method userData only (master data left out)',
            ),
            at: at,
            json: summary,
          ),
        );
      }
    }
  }

  /// [raw] with `result` replaced by a placeholder that keeps only its type
  /// and length, e.g. for getAppSharedSecret. Errors are kept as they are.
  static String redactResult(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is Map && j.containsKey('result')) {
        final r = j['result'];
        final shape = switch (r) {
          String s => '<redacted string, ${s.length} chars>',
          Map m => {for (final k in m.keys) '$k': '<redacted>'},
          null => null,
          _ => '<redacted ${r.runtimeType}>',
        };
        return jsonEncode({...j, 'result': shape});
      }
      return raw;
    } on FormatException {
      return '<redacted, ${raw.length} bytes>';
    }
  }

  static final _secretKey = RegExp(
    r'token|secret|password|passwd|otp|jwt',
    caseSensitive: false,
  );

  /// [raw] with the values of keys that look like credentials (`token`,
  /// `secret`, `password`, …) replaced, at any depth.
  static String redactSecretKeys(String raw) {
    Object? walk(Object? v) => switch (v) {
      Map m => {
        for (final e in m.entries)
          '${e.key}': _secretKey.hasMatch('${e.key}') && e.value is String
              ? '<redacted>'
              : walk(e.value),
      },
      List l => [for (final x in l) walk(x)],
      _ => v,
    };
    try {
      return jsonEncode(walk(jsonDecode(raw)));
    } on FormatException {
      return raw;
    }
  }

  /// getUserData2017 without the (large, school-wide) master data: the full
  /// `userData` plus the keys of every other part, so a parent account's
  /// `elemType`/`children` can be pasted on its own. Null if not JSON.
  static String? userDataSummary(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final r = j['result'];
      if (r is! Map) return null;
      final md = r['masterData'];
      return jsonEncode({
        'result': {
          for (final e in r.entries)
            if (e.key != 'masterData') '${e.key}': e.value,
          if (md is Map)
            'masterData': {
              for (final e in md.entries)
                '${e.key}': e.value is List
                    ? '<${(e.value as List).length} entries>'
                    : e.value is Map
                    ? '<object>'
                    : e.value,
            },
        },
      });
    } on FormatException {
      return null;
    }
  }

  void _record(String method, String raw) {
    _log.addLast((_seq++, (method: method, at: _now(), json: raw)));
    while (_log.length > debugCapacity) {
      _log.removeFirst();
    }
  }
}
