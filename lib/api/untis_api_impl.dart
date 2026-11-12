/// WebUntis client implementing the [UntisApi] contract.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/absence_details.dart';
import '../core/class_register.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import 'class_register_parsers.dart';
import 'json_rpc.dart';
import 'parsers.dart';
import 'rest_teachers.dart';

class UntisApiImpl implements FullUntisApi {
  /// [interceptors] are added to the default client (e.g. the web proxy
  /// rewrite); ignored when [dio] is given.
  UntisApiImpl({
    Dio? dio,
    DateTime Function()? now,
    bool isIos = false,
    List<Interceptor> interceptors = const [],
  }) : this._(
         dio ??
             (Dio(
               BaseOptions(
                 connectTimeout: const Duration(seconds: 15),
                 receiveTimeout: const Duration(seconds: 30),
               ),
             )..interceptors.addAll(interceptors)),
         now,
         isIos,
       );

  UntisApiImpl._(Dio dio, DateTime Function()? now, this.isIos)
    : _dio = dio,
      _now = now ?? DateTime.now,
      _rpc = JsonRpcClient(dio: dio, now: now);

  final Dio _dio;
  final DateTime Function() _now;

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
    checkTarget(target);
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
    final missingTeachers = res.periods.any(
      (p) => p.ofType(ElementType.teacher).isEmpty,
    );
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

  /// Untis answers an unknown `type` with "request.type is null" (seen for
  /// parent accounts, whose own element isn't a timetable). Such a request
  /// is never sent; this throws a clear error instead.
  static void checkTarget(TimetableTarget target) {
    if (!timetableElementTypes.contains(target.type) || target.id <= 0) {
      throw UntisException(
        -1,
        'No timetable for this element '
        '(${target.type.apiName}#${target.id}). Open a class, teacher or '
        'room via "Browse timetables" instead.',
      );
    }
  }

  final _tokens = <String, ({String token, DateTime at})>{};

  /// Bearer token for REST calls, cached for a few minutes per account.
  Future<String> _token(
    String host,
    String school,
    UntisCredentials auth,
  ) async {
    final key = '$host|$school|${auth.username}';
    final cached = _tokens[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
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
    final type = target.type == ElementType.student
        ? 'MY_TIMETABLE'
        : 'STANDARD';

    Future<Response<String>> get(int format) async {
      final url =
          'https://$host/WebUntis/api/rest/view/v1/timetable/entries'
          '?start=${formatDate(start)}&end=${formatDate(end)}&format=$format'
          '&resourceType=${target.type.apiName}&resources=${target.id}'
          '&periodTypes=&timetableType=$type';
      final resp = await _dio.get<String>(
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
      _rpc.record(
        'REST timetable/entries ${target.type.apiName}#${target.id} '
        '${formatDate(start)}..${formatDate(end)} format=$format [HTTP ${resp.statusCode}]',
        resp.data ?? '',
      );
      if (resp.statusCode == 401) {
        _tokens.remove('$host|$school|${auth.username}');
      }
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
        _rpc.record(
          'PROBE $label [no response]',
          '{"_requestFailed": "${e.type.name}"}',
        );
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
  ) {
    checkTarget(target);
    return {
      'id': target.id,
      'type': target.type.apiName,
      'startDate': formatDate(start),
      'endDate': formatDate(end),
      'auth': _rpc.auth(auth),
    };
  }

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

  /// [studentId] (parent accounts) is sent as `studentId`. That parameter is
  /// a guess (docs/API.md): if the server rejects the call with it, the call
  /// is repeated once without it.
  @override
  Future<List<RawAbsence>> rawAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  }) async {
    Future<Object?> call({required bool withStudent}) =>
        _rpc.call(rpcUrl(host, school), 'getStudentAbsences2017', {
          'startDate': formatDate(start),
          'endDate': formatDate(end),
          'includeExcused': true,
          'includeUnExcused': true,
          if (withStudent) 'studentId': studentId,
          'auth': _rpc.auth(auth),
        });
    if (studentId == null) {
      return parseRawAbsences(await call(withStudent: false));
    }
    try {
      return parseRawAbsences(await call(withStudent: true));
    } on UntisException catch (e) {
      if (e.isNetwork || e.isTimeout) rethrow;
      return parseRawAbsences(await call(withStudent: false));
    }
  }

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
    int? studentId,
  }) async {
    final raw = await rawAbsences(
      host: host,
      school: school,
      auth: auth,
      start: start,
      end: end,
      studentId: studentId,
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

  // ---- Reporting absences ----------------------------------------------------
  //
  // The WebUntis web client reports an absence with
  // `POST /WebUntis/api/classreg/absences/students/self` and loads reasons and
  // defaults from `GET /WebUntis/api/classreg/absences/meta`. These endpoints
  // ignore the bearer token (2026-11-12: 302 to index.do / 403 at two
  // schools); they need a browser session. We open one the way the WebUntis
  // JS library's secret login does: getUserData2017 on jsonrpc_intern.do with
  // the OTP answers with a JSESSIONID cookie, sent along with
  // `schoolname="_<base64 school>"`. See [_webSession].

  static String classregUrl(String host, String path) =>
      'https://$host/WebUntis/api/classreg/$path';

  /// Reasons/defaults from `absences/meta` plus the `showCreateAbsence` flag
  /// of today's absence list. Either may fail; throws only when both fail.
  @override
  Future<AbsenceReportOptions> absenceReportOptions({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
  }) async {
    AbsenceReportOptions? meta;
    ({bool? allowed, List<AbsenceReason> reasons})? list;
    UntisException? firstError;
    try {
      meta = parseAbsenceMeta(
        await _classic(
          host,
          school,
          auth,
          'GET',
          classregUrl(host, 'absences/meta'),
          'REST classreg absences/meta',
        ),
      );
    } on UntisException catch (e) {
      firstError = e;
    }
    final today = ymdNumber(_now());
    try {
      list = parseAbsenceListFlags(
        await _classic(
          host,
          school,
          auth,
          'GET',
          classregUrl(
            host,
            'absences/students?startDate=$today&endDate=$today'
            '&studentId=$studentId&excuseStatusId=-1',
          ),
          'REST classreg absences/students studentId=$studentId $today',
        ),
      );
    } on UntisException catch (e) {
      firstError ??= e;
    }
    if (meta == null && list == null) throw firstError!;
    return AbsenceReportOptions(
      reasons: (meta?.reasons.isNotEmpty ?? false)
          ? meta!.reasons
          : list?.reasons ?? const [],
      defaultReasonId: meta?.defaultReasonId,
      allowed: list?.allowed ?? meta?.allowed,
      defaultStartMinutes: meta?.defaultStartMinutes,
      defaultEndMinutes: meta?.defaultEndMinutes,
    );
  }

  @override
  Future<void> reportAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required AbsenceReport report,
  }) async {
    checkAbsenceReport(report);
    final body = absenceReportPayload(report);
    // The body has no credentials; it is logged so a failed report can be
    // compared with what the web client sends.
    _rpc.record(
      'REST classreg absences/students/self request body',
      jsonEncode(body),
    );
    checkAbsenceWriteResult(
      await _classic(
        host,
        school,
        auth,
        'POST',
        classregUrl(host, 'absences/students/self'),
        'REST classreg absences/students/self studentId=${report.studentId}',
        body: body,
      ),
    );
  }

  @override
  Future<List<AbsenceRecord>> absenceRecords({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) async => parseAbsenceRecords(
    await _classic(
      host,
      school,
      auth,
      'GET',
      classregUrl(
        host,
        'absences/students?startDate=${ymdNumber(start)}'
        '&endDate=${ymdNumber(end)}&studentId=$studentId&excuseStatusId=-1',
      ),
      'REST classreg absences/students studentId=$studentId '
          '${ymdNumber(start)}..${ymdNumber(end)}',
    ),
  );

  /// `DELETE /WebUntis/api/classreg/absences/students` with
  /// `{absenceIds:[…]}`, as the web client sends it (seen 2026-11-12).
  @override
  Future<void> deleteAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) return;
    checkAbsenceDeleteResult(
      await _classic(
        host,
        school,
        auth,
        'DELETE',
        classregUrl(host, 'absences/students'),
        'REST classreg DELETE absences/students ids=${ids.join(',')}',
        body: absenceDeletePayload(ids),
      ),
    );
  }

  // ---- Class register (teachers) -----------------------------------------
  // Method names and params follow the Untis Mobile teacher API as other
  // clients use it; not yet confirmed against a real teacher account
  // (docs/API.md "Class register (teachers)"). Request bodies of the writes
  // carry no credentials and are logged, so a failure can be compared.

  void _recordRequest(String method, Map<String, Object?> params) =>
      _rpc.record('$method request body', jsonEncode(params));

  @override
  Future<PeriodRegisterData> periodData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) async {
    if (ttIds.isEmpty) return const PeriodRegisterData();
    return parsePeriodData(
      await _rpc.call(rpcUrl(host, school), 'getPeriodData2017', {
        'ttIds': ttIds,
        'auth': _rpc.auth(auth),
      }),
    );
  }

  @override
  Future<void> submitLessonTopic({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required String topic,
  }) async {
    final params = {'lessonTopic': topic, 'ttId': ttId};
    _recordRequest('submitLessonTopic', params);
    await _rpc.call(rpcUrl(host, school), 'submitLessonTopic', {
      ...params,
      'auth': _rpc.auth(auth),
    });
  }

  @override
  Future<void> createAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) async {
    final params = {
      'periodId': ttId,
      'studentId': studentId,
      'startTime': formatUntisTime(start),
      'endTime': formatUntisTime(end),
    };
    _recordRequest('createImmediateAbsence2017', params);
    await _rpc.call(rpcUrl(host, school), 'createImmediateAbsence2017', {
      ...params,
      'auth': _rpc.auth(auth),
    });
  }

  @override
  Future<void> deleteAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int absenceId,
  }) async {
    final params = {'absenceId': absenceId};
    _recordRequest('deleteAbsence2017', params);
    await _rpc.call(rpcUrl(host, school), 'deleteAbsence2017', {
      ...params,
      'auth': _rpc.auth(auth),
    });
  }

  @override
  Future<void> submitAbsencesChecked({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) async {
    if (ttIds.isEmpty) return;
    final params = {'ttIds': ttIds};
    _recordRequest('submitAbsencesChecked2017', params);
    await _rpc.call(rpcUrl(host, school), 'submitAbsencesChecked2017', {
      ...params,
      'auth': _rpc.auth(auth),
    });
  }

  /// Client-side checks before anything is sent.
  static void checkAbsenceReport(AbsenceReport r) {
    if (r.studentId <= 0) {
      throw const UntisException(-1, 'No pupil selected.');
    }
    if (!r.end.isAfter(r.start)) {
      throw const UntisException(-1, 'The end must be after the start.');
    }
  }

  /// Web session request headers per `host|school|user`, with when the
  /// session was opened.
  final _webSessions = <String, ({Map<String, String> headers, DateTime at})>{};

  /// Opens (or reuses, for 10 minutes) a WebUntis browser session for the
  /// classic `/WebUntis/api/...` endpoints and returns the headers to send:
  /// `Cookie`, plus `X-CSRF-TOKEN` / `Tenant-Id` when `api/app/config` has
  /// them (the browser sends both). Null when the server sent no JSESSIONID;
  /// the caller then falls back to the bearer token alone. Only names are
  /// logged, never values.
  Future<Map<String, String>?> _webSession(
    String host,
    String school,
    UntisCredentials auth, {
    bool refresh = false,
  }) async {
    final key = '$host|$school|${auth.username}';
    final cached = _webSessions[key];
    if (!refresh &&
        cached != null &&
        _now().difference(cached.at) < const Duration(minutes: 10)) {
      return cached.headers;
    }
    _webSessions.remove(key);
    Headers? loginHeaders;
    try {
      await _rpc.call(
        '${rpcUrl(host, school)}&m=getUserData2017&v=i2.2',
        'getUserData2017',
        {'auth': _rpc.auth(auth)},
        onHeaders: (h) => loginHeaders = h,
      );
    } on UntisException catch (e) {
      _rpc.record(
        'web session: login failed',
        jsonEncode({'code': e.code, 'message': e.message}),
      );
      return null;
    }
    final cookies = parseSetCookies(loginHeaders?['set-cookie'] ?? const []);
    _rpc.record(
      'web session: cookies received',
      jsonEncode({'names': cookies.keys.toList()}),
    );
    if (!cookies.containsKey('JSESSIONID')) return null;
    // What the browser sends (seen 2026-11-12): cookies, X-CSRF-TOKEN,
    // Tenant-Id, Origin and Referer, and no Authorization header.
    final headers = <String, String>{
      'Cookie': sessionCookieHeader(cookies, school),
      'Origin': 'https://$host',
      'Referer': 'https://$host/WebUntis/embedded.do?showSidebar=false',
      'X-XSRF-TOKEN': ?cookies['XSRF-TOKEN'],
      'Tenant-Id': ?cookies['Tenant-Id'],
    };
    // The web client's own config; best effort, the session works without.
    try {
      final resp = await _bearerRequest(
        host,
        school,
        auth,
        'GET',
        'https://$host/WebUntis/api/app/config',
        'web session: api/app/config',
        followRedirects: false,
        headers: headers,
        logBody: false,
        sendToken: false,
      );
      Object? config;
      try {
        config = jsonDecode(resp.data ?? '');
      } on FormatException {
        config = null;
      }
      final found = findSessionValues(config);
      _rpc.record(
        'web session: api/app/config [HTTP ${resp.statusCode}] values found',
        jsonEncode({
          'topLevelKeys': config is Map
              ? [
                  ...config.keys.map((k) => '$k'),
                  if (config['data'] case final Map d)
                    ...d.keys.map((k) => 'data.$k'),
                ]
              : null,
          'csrfAt': found.csrfPath,
          'csrfHeader': found.csrfHeader,
          'tenantIdAt': found.tenantPath,
        }),
      );
      if (found.csrf case final csrf?) {
        headers[found.csrfHeader ?? 'X-CSRF-TOKEN'] = csrf;
      }
      if (found.tenantId case final t?) headers['Tenant-Id'] = t;
    } on UntisException {
      // Logged by _bearerRequest.
    }
    _webSessions[key] = (headers: headers, at: _now());
    return headers;
  }

  /// CSRF token, the header name to send it in, and the tenant id, found
  /// anywhere in [json] (WebUntis `api/app/config` has `data.csrfToken`,
  /// `data.csrfHeader` and `data.tenantId`), with the token's and tenant's
  /// key paths.
  static ({
    String? csrf,
    String? csrfPath,
    String? csrfHeader,
    String? tenantId,
    String? tenantPath,
  })
  findSessionValues(Object? json) {
    String? csrf, csrfPath, header, tenant, tenantPath;
    final tokenKey = RegExp(r'^_?csrf(_?token)?$', caseSensitive: false);
    final headerKey = RegExp(r'^csrf_?header(_?name)?$', caseSensitive: false);
    final headerName = RegExp(r'^[A-Za-z][A-Za-z0-9-]*$');
    final tenantKey = RegExp(r'^tenant_?id$', caseSensitive: false);
    void walk(Object? v, String path) {
      if (v is Map) {
        for (final e in v.entries) {
          final k = '${e.key}';
          final p = path.isEmpty ? k : '$path.$k';
          final val = e.value;
          final scalar = val is String || val is num;
          if (csrf == null && scalar && tokenKey.hasMatch(k)) {
            csrf = '$val';
            csrfPath = p;
          } else if (header == null &&
              val is String &&
              headerKey.hasMatch(k) &&
              headerName.hasMatch(val)) {
            header = val;
          } else if (tenant == null && scalar && tenantKey.hasMatch(k)) {
            tenant = '$val';
            tenantPath = p;
          } else if (tenant == null &&
              scalar &&
              k == 'id' &&
              path.toLowerCase().endsWith('tenant')) {
            tenant = '$val';
            tenantPath = p;
          }
          walk(val, p);
        }
      } else if (v is List) {
        for (var i = 0; i < v.length && i < 50; i++) {
          walk(v[i], '$path[$i]');
        }
      }
    }

    walk(json, '');
    return (
      csrf: csrf,
      csrfPath: csrfPath,
      csrfHeader: header,
      tenantId: tenant,
      tenantPath: tenantPath,
    );
  }

  /// `name=value` pairs of `Set-Cookie` headers (attributes dropped).
  static Map<String, String> parseSetCookies(List<String> setCookies) => {
    for (final line in setCookies)
      if (line.split(';').first case final pair when pair.contains('='))
        pair.substring(0, pair.indexOf('=')).trim(): pair
            .substring(pair.indexOf('=') + 1)
            .trim(),
  };

  /// `Cookie` header for a web session: its cookies plus the
  /// `schoolname="_<base64>"` cookie the web client sets.
  static String sessionCookieHeader(
    Map<String, String> cookies,
    String school,
  ) {
    final all = {
      'schoolname': '"_${base64.encode(utf8.encode(school))}"',
      ...cookies,
    };
    return all.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Request to a classic `/WebUntis/api/...` endpoint with the web session
  /// headers like the browser (no bearer token), or with only the bearer
  /// token when no session could be opened. Redirects are
  /// not followed: a 3xx (or an HTML page) means the server wants a browser
  /// login. A cached session that gets one is reopened once.
  Future<Object?> _classic(
    String host,
    String school,
    UntisCredentials auth,
    String method,
    String url,
    String label, {
    Object? body,
  }) async {
    final key = '$host|$school|${auth.username}';
    final wasCached = _webSessions.containsKey(key);
    var session = await _webSession(host, school, auth);
    late Response<String> resp;
    for (var attempt = 0; attempt < 2; attempt++) {
      resp = await _bearerRequest(
        host,
        school,
        auth,
        method,
        url,
        session == null ? label : '$label (web session)',
        body: body,
        followRedirects: false,
        headers: session ?? const {},
        sendToken: session == null,
      );
      final s = resp.statusCode ?? 0;
      final rejected = (s >= 300 && s < 400) || s == 403;
      if (!rejected || session == null || !wasCached || attempt > 0) break;
      session = await _webSession(host, school, auth, refresh: true);
      if (session == null) break;
    }
    final status = resp.statusCode ?? 0;
    final text = resp.data ?? '';
    final looksHtml = text.trimLeft().startsWith('<');
    if ((status >= 300 && status < 400) || (looksHtml && status < 400)) {
      throw const UntisException(
        sessionRequired,
        "The school's server didn't accept the app's sign-in for this "
        'function (it asked for a browser login). Please report the absence '
        'on the WebUntis website for now, and send the Debug log so this '
        'can be fixed.',
      );
    }
    Object? decoded;
    try {
      decoded = text.trim().isEmpty ? null : jsonDecode(text);
    } on FormatException {
      if (status >= 200 && status < 300) {
        throw const UntisException(-1, 'Invalid JSON response');
      }
    }
    if (status == 403) {
      throw UntisException(
        UntisException.noRight,
        parseRestErrorMessage(decoded) ??
            "Your school doesn't allow reporting absences for this account "
                '(HTTP 403).',
      );
    }
    if (status == 404 || status == 405) {
      throw UntisException(
        -1,
        "This school's WebUntis doesn't offer this function (HTTP $status).",
      );
    }
    if (status < 200 || status >= 300) throw restError(status, decoded);
    return decoded;
  }

  /// [UntisException.code] of [_classic] when the server answered with a
  /// login redirect / page instead of JSON.
  static const sessionRequired = -8530;

  /// Sends one bearer-authenticated request; every answer is recorded in the
  /// debug log (the token never is). A 401 drops the cached token and retries
  /// once.
  Future<Response<String>> _bearerRequest(
    String host,
    String school,
    UntisCredentials auth,
    String method,
    String url,
    String label, {
    Object? body,
    bool followRedirects = true,
    Map<String, String> headers = const {},
    bool logBody = true,
    bool sendToken = true,
  }) async {
    final tokenKey = '$host|$school|${auth.username}';
    late Response<String> resp;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = sendToken ? await _token(host, school, auth) : null;
      try {
        resp = await _dio.request<String>(
          url,
          data: body == null ? null : jsonEncode(body),
          options: Options(
            method: method,
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
            followRedirects: followRedirects,
            maxRedirects: followRedirects ? 5 : 0,
            contentType: body == null ? null : 'application/json',
            headers: {
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
              ...headers,
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
      final location = resp.headers.value('location');
      final raw = resp.data ?? '';
      // logBody false: the body may hold session values (a CSRF token).
      final data = logBody ? raw : '<not logged, ${raw.length} chars>';
      _rpc.record(
        '$label [HTTP ${resp.statusCode}]',
        location == null
            ? data
            : jsonEncode({'_redirectTo': _stripQuery(location), '_body': data}),
      );
      if (!sendToken || resp.statusCode != 401) break;
      _tokens.remove(tokenKey);
    }
    return resp;
  }

  /// [url] without its query (a login redirect may carry session ids).
  static String _stripQuery(String url) {
    final i = url.indexOf(RegExp('[?;]'));
    return i < 0 ? url : url.substring(0, i);
  }

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
