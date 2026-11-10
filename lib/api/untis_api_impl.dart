/// WebUntis client implementing the [UntisApi] contract.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import 'json_rpc.dart';
import 'parsers.dart';
import 'rest_teachers.dart';

class UntisApiImpl implements UntisApi {
  UntisApiImpl({Dio? dio, DateTime Function()? now, bool isIos = false})
    : this._(
        dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              ),
            ),
        now,
        isIos,
      );

  UntisApiImpl._(Dio dio, DateTime Function()? now, this.isIos)
    : _dio = dio,
      _rpc = JsonRpcClient(dio: dio, now: now);

  final Dio _dio;

  static const schoolSearchUrl =
      'https://schoolsearch.webuntis.com/schoolquery2';

  /// Selects the iOS mobileServiceUrl flag and deviceOs "IOS".
  final bool isIos;
  final JsonRpcClient _rpc;

  static String rpcUrl(String host, String school) =>
      'https://$host/WebUntis/jsonrpc_intern.do'
      '?school=${Uri.encodeQueryComponent(school)}';

  @override
  List<({String method, DateTime at, String json})> get debugLog =>
      _rpc.debugLog;

  @override
  Future<List<School>> searchSchools(String query) async {
    final q = query.trim();
    final params = RegExp(r'^\d+$').hasMatch(q)
        ? <String, Object?>{'schoolid': int.parse(q)}
        : <String, Object?>{'search': q};
    final result = await _rpc.call(schoolSearchUrl, 'searchSchool', params);
    return parseSchools(result, isIos: isIos);
  }

  @override
  Future<LoginResult> login({
    required School school,
    required String username,
    required String passwordOrKey,
    bool anonymous = false,
    String? twoFactorToken,
    bool skipAppSecret = false,
    String? hostOverride,
  }) async {
    final host = hostOf(hostOverride) ?? school.host;
    final url = rpcUrl(host, school.loginName);

    var secret = anonymous ? '' : passwordOrKey;
    if (!anonymous && !skipAppSecret) {
      try {
        final result = await _rpc.call(url, 'getAppSharedSecret', {
          'userName': username,
          'password': passwordOrKey,
          if (twoFactorToken != null && twoFactorToken.isNotEmpty)
            'token': twoFactorToken,
        });
        final s = result is String ? result.trim() : '';
        secret = s.isNotEmpty ? s : passwordOrKey;
      } on UntisException catch (e) {
        if (e.code == UntisException.twoFactorRequired || e.code == 0) {
          rethrow;
        }
        secret = passwordOrKey; // QR-code key: password is the secret.
      }
    }

    final creds = anonymous
        ? const UntisCredentials.anonymous()
        : UntisCredentials.user(username, secret);
    final result = await _rpc.call(url, 'getUserData2017', {
      'elementId': 0,
      'deviceOs': isIos ? 'IOS' : 'AND',
      'deviceOsVersion': '',
      'auth': _rpc.auth(creds),
    });
    return parseLoginResult(result, secret: secret);
  }

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) async {
    final result = await _rpc.call(rpcUrl(host, school), 'getTimetable2017', {
      'id': target.id,
      'type': target.type.apiName,
      'startDate': formatDate(start),
      'endDate': formatDate(end),
      'masterDataTimestamp': masterDataTimestamp,
      'timetableTimestamp': 0,
      'timetableTimestamps': <int>[],
      'auth': _rpc.auth(auth),
    });
    final res = parseTimetableResponse(result);

    // Some schools leave TEACHER elements out of the JSON-RPC timetable for
    // students, while the REST timetable (used by the official app) has them.
    final missingTeachers =
        res.periods.any((p) => p.ofType(ElementType.teacher).isEmpty);
    if (!missingTeachers || auth.anonymous) return res;
    try {
      final entries = await _restEntries(
        host: host,
        school: school,
        auth: auth,
        target: target,
        start: start,
        end: end,
      );
      return TimetableResponse(
        mergeRestTeachers(res.periods, entries),
        res.masterDataDelta,
      );
    } catch (_) {
      // Teachers are a bonus here; the timetable itself must still load.
      return res;
    }
  }

  final _tokens = <String, ({String token, DateTime at})>{};

  /// Bearer token for REST calls, cached for a few minutes per account.
  Future<String> _token(String host, String school, UntisCredentials auth) async {
    final key = '$host|$school|${auth.username}';
    final cached = _tokens[key];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return cached.token;
    }
    final r = await _rpc.call(rpcUrl(host, school), 'getAuthToken', {
      'auth': _rpc.auth(auth),
    });
    final token = r is Map ? r['token']?.toString() : r?.toString();
    if (token == null || token.isEmpty) {
      throw const UntisException(0, 'getAuthToken returned no token');
    }
    _tokens[key] = (token: token, at: DateTime.now());
    return token;
  }

  Future<List<RestEntry>> _restEntries({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async {
    final token = await _token(host, school, auth);
    final own = target.type == ElementType.student;
    final url = 'https://$host/WebUntis/api/rest/view/v1/timetable/entries'
        '?start=${formatDate(start)}&end=${formatDate(end)}&format=4'
        '&resourceType=${target.type.apiName}&resources=${target.id}'
        '&periodTypes=&timetableType=${own ? 'MY_TIMETABLE' : 'STANDARD'}';
    final resp = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      ),
    );
    final raw = resp.data ?? '';
    _rpc.record(
      'REST timetable/entries ${target.type.apiName}#${target.id} '
      '${formatDate(start)}..${formatDate(end)} [HTTP ${resp.statusCode}]',
      raw,
    );
    if ((resp.statusCode ?? 0) == 401) _tokens.remove('$host|$school|${auth.username}');
    if ((resp.statusCode ?? 0) >= 300) return const [];
    return parseRestEntries(jsonDecode(raw));
  }

  @override
  Future<List<Message>> messagesOfDay({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime date,
  }) async {
    final result = await _rpc.call(
      rpcUrl(host, school),
      'getMessagesOfDay2017',
      {'date': formatDate(date), 'auth': _rpc.auth(auth)},
    );
    return parseMessages(result);
  }

  @override
  Future<void> probeTeacherSources({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime weekStart,
  }) async {
    final start = formatDate(weekStart);
    final end = formatDate(weekStart.add(const Duration(days: 6)));
    final base = 'https://$host/WebUntis';

    String? token;
    try {
      final r = await _rpc.call(rpcUrl(host, school), 'getAuthToken', {
        'auth': _rpc.auth(auth),
      });
      token = r is Map ? r['token']?.toString() : r?.toString();
    } catch (_) {
      // Recorded in the log by the transport; continue with the other probes.
    }

    final probes = <(String, String)>[
      (
        'REST timetable/entries',
        '$base/api/rest/view/v1/timetable/entries?start=$start&end=$end'
            '&format=4&resourceType=${target.type.apiName}'
            '&resources=${target.id}&periodTypes=&timetableType=MY_TIMETABLE',
      ),
      (
        'REST timetable/filter',
        '$base/api/rest/view/v1/timetable/filter?resourceType=${target.type.apiName}'
            '&timetableType=STANDARD',
      ),
      (
        'public weekly/data',
        '$base/api/public/timetable/weekly/data?elementType=${target.type.code}'
            '&elementId=${target.id}&date=$start&formatId=1',
      ),
      ('REST app/data', '$base/api/rest/view/v1/app/data'),
    ];
    for (final (label, url) in probes) {
      try {
        final resp = await _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
            headers: {
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
              'Tenant-Id': school,
            },
          ),
        );
        _rpc.record('PROBE $label [HTTP ${resp.statusCode}]', resp.data ?? '');
      } on DioException catch (e) {
        _rpc.record('PROBE $label [no response]', '{"_requestFailed": "${e.type.name}"}');
      }
    }
  }
}
