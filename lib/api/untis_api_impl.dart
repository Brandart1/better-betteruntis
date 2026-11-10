/// WebUntis client implementing the [UntisApi] contract.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/absence_details.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import 'json_rpc.dart';
import 'parsers.dart';
import 'rest_teachers.dart';

class UntisApiImpl implements FullUntisApi {
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
    final login = parseLoginResult(result, secret: secret);
    _rememberLookups(host, school.loginName, login.masterData);
    return login;
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
    _rememberLookups(host, school, res.masterDataDelta);

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

  /// Working `format` id per `host|school|timetableType`. The id is
  /// school-specific: e.g. 4 works for MY_TIMETABLE while STANDARD (class)
  /// timetables answer 404 "Timetable format not found". `null` value = no
  /// format works; REST is skipped for that key this session.
  final _formats = <String, Future<int?>>{};

  /// Format ids tried in order, the default first.
  static List<int> formatCandidates(String timetableType) => [
    if (timetableType == 'MY_TIMETABLE') 4,
    for (var i = 1; i <= 12; i++)
      if (!(timetableType == 'MY_TIMETABLE' && i == 4)) i,
  ];

  static bool _isFormatNotFound(int? status, String body) =>
      status == 404 && body.toLowerCase().contains('format not found');

  Future<List<RestEntry>> _restEntries({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async {
    final token = await _token(host, school, auth);
    final type = target.type == ElementType.student ? 'MY_TIMETABLE' : 'STANDARD';

    Future<Response<String>> get(int format) async {
      final url = 'https://$host/WebUntis/api/rest/view/v1/timetable/entries'
          '?start=${formatDate(start)}&end=${formatDate(end)}&format=$format'
          '&resourceType=${target.type.apiName}&resources=${target.id}'
          '&periodTypes=&timetableType=$type';
      final resp = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
        ),
      );
      _rpc.record(
        'REST timetable/entries ${target.type.apiName}#${target.id} '
        '${formatDate(start)}..${formatDate(end)} format=$format [HTTP ${resp.statusCode}]',
        resp.data ?? '',
      );
      if (resp.statusCode == 401) _tokens.remove('$host|$school|${auth.username}');
      return resp;
    }

    final key = '$host|$school|$type';
    Response<String>? first;
    // Only one request discovers the format; concurrent ones wait for it.
    final format = await (_formats[key] ??= () async {
      for (final f in formatCandidates(type)) {
        final r = await get(f);
        if (_isFormatNotFound(r.statusCode, r.data ?? '')) continue;
        if ((r.statusCode ?? 0) >= 300) {
          // Some other failure (permissions, auth): don't cache a verdict.
          _formats.remove(key);
          first = r;
          return null;
        }
        first = r;
        return f;
      }
      return null; // No format works: skip REST for this key this session.
    }());
    if (format == null) return const [];

    // The discovering call already holds this target's response.
    final resp = first ?? await get(format);
    if (_isFormatNotFound(resp.statusCode, resp.data ?? '')) {
      _formats.remove(key); // School changed its formats; rediscover next time.
      return const [];
    }
    if ((resp.statusCode ?? 0) >= 300) return const [];
    return parseRestEntries(jsonDecode(resp.data ?? ''));
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

  // ---- Info center ----------------------------------------------------------

  /// Absence lookups seen this session per `host|school` (from login, timetable
  /// deltas and [absenceLookups]). Used by the contract [absences]; the data
  /// layer persists its own copy.
  final _lookups = <String, AbsenceLookups>{};

  void _rememberLookups(String host, String school, MasterData? md) {
    if (md is! MasterDataWithLookups || md.lookups.isEmpty) return;
    final key = '$host|$school';
    _lookups[key] = (_lookups[key] ?? const AbsenceLookups()).merge(md.lookups);
  }

  Map<String, Object?> _rangeParams(
    TimetableTarget target,
    DateTime start,
    DateTime end,
    UntisCredentials auth,
  ) => {
    'id': target.id,
    'type': target.type.apiName,
    'startDate': formatDate(start),
    'endDate': formatDate(end),
    'auth': _rpc.auth(auth),
  };

  @override
  Future<List<HomeworkItem>> homework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async => parseHomeworkItems(
    await _rpc.call(
      rpcUrl(host, school),
      'getHomeWork2017',
      _rangeParams(target, start, end, auth),
    ),
  );

  @override
  Future<List<ExamItem>> exams({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) async => parseExamItems(
    await _rpc.call(
      rpcUrl(host, school),
      'getExams2017',
      _rangeParams(target, start, end, auth),
    ),
  );

  @override
  Future<List<RawAbsence>> rawAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  }) async => parseRawAbsences(
    await _rpc.call(rpcUrl(host, school), 'getStudentAbsences2017', {
      'startDate': formatDate(start),
      'endDate': formatDate(end),
      'includeExcused': true,
      'includeUnExcused': true,
      'auth': _rpc.auth(auth),
    }),
  );

  /// One getUserData2017 call (the only known source of the full master data).
  @override
  Future<AbsenceLookups> absenceLookups({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async {
    final result = await _rpc.call(rpcUrl(host, school), 'getUserData2017', {
      'elementId': 0,
      'deviceOs': isIos ? 'IOS' : 'AND',
      'deviceOsVersion': '',
      'auth': _rpc.auth(auth),
    });
    final lookups = parseAbsenceLookups(
      result is Map ? result['masterData'] : null,
    );
    _lookups['$host|$school'] =
        (_lookups['$host|$school'] ?? const AbsenceLookups()).merge(lookups);
    return lookups;
  }

  /// Resolves names with the lookups seen this session; loads them once via
  /// [absenceLookups] when an id is unknown (failures leave names empty).
  @override
  Future<List<AbsenceItem>> absences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  }) async {
    final raw = await rawAbsences(
      host: host,
      school: school,
      auth: auth,
      start: start,
      end: end,
    );
    final key = '$host|$school';
    if (!_lookups.containsKey(key) &&
        raw.any((a) => a.needsLookup(const AbsenceLookups()))) {
      try {
        await absenceLookups(host: host, school: school, auth: auth);
      } on UntisException {
        _lookups[key] = const AbsenceLookups(); // don't retry this session
      }
    }
    final lookups = _lookups[key] ?? const AbsenceLookups();
    return [for (final a in raw) a.resolve(lookups)];
  }

  @override
  Future<List<OfficeHourItem>> officeHours({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
  }) async => parseOfficeHourItems(
    await _rpc.call(rpcUrl(host, school), 'getOfficeHours2017', {
      'klasseId': klasseId,
      'startDate': formatDate(start),
      'auth': _rpc.auth(auth),
    }),
  );

  @override
  Future<List<InboxMessage>> inbox({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) async => parseInbox(
    await _restGet(host, school, auth, 'view/v1/messages', 'REST messages'),
  );

  @override
  Future<InboxMessageDetail> inboxMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  }) async => parseInboxMessageDetail(
    await _restGet(
      host,
      school,
      auth,
      'view/v1/messages/$id',
      'REST messages/$id',
    ),
    id,
  );

  /// Authenticated REST GET returning decoded JSON. Every response is recorded
  /// in the debug log. A 401 drops the cached token and retries once; other
  /// non-2xx answers map to [restError].
  Future<Object?> _restGet(
    String host,
    String school,
    UntisCredentials auth,
    String path,
    String label,
  ) async {
    final url = 'https://$host/WebUntis/api/rest/$path';
    final tokenKey = '$host|$school|${auth.username}';
    Response<String>? resp;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _token(host, school, auth);
      try {
        resp = await _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          ),
        );
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
        _rpc.record(
          '$label [no response]',
          jsonEncode({'_requestFailed': msg}),
        );
        throw UntisException(timedOut ? UntisException.timeout : 0, msg);
      }
      _rpc.record('$label [HTTP ${resp.statusCode}]', resp.data ?? '');
      if (resp.statusCode != 401) break;
      _tokens.remove(tokenKey);
    }
    final status = resp!.statusCode ?? 0;
    final body = resp.data ?? '';
    Object? decoded;
    try {
      decoded = body.trim().isEmpty ? null : jsonDecode(body);
    } on FormatException {
      if (status >= 200 && status < 300) {
        throw const UntisException(-1, 'Invalid JSON response');
      }
    }
    if (status < 200 || status >= 300) throw restError(status, decoded);
    return decoded;
  }

  /// Maps a non-2xx REST answer: 403 -> [UntisException.noRight], 401 -> -8520
  /// (authentication), anything else -> -1 (not "no connection").
  static UntisException restError(int status, Object? body) {
    final msg = parseRestErrorMessage(body) ?? 'HTTP $status';
    final code = switch (status) {
      403 => UntisException.noRight,
      401 => -8520,
      _ => -1,
    };
    return UntisException(code, msg);
  }
}
