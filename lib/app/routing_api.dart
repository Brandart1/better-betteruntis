import '../core/absence_details.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// Sends demo accounts (host `*.invalid`) to [demo] and everything else to
/// [real], so demo profiles live alongside real ones in the same database.
class RoutingUntisApi implements FullUntisApi {
  RoutingUntisApi({required this.real, required this.demo});

  final FullUntisApi real;
  final FullUntisApi demo;

  static bool isDemoHost(String host) => host.endsWith('.invalid');
  FullUntisApi _for(String host) => isDemoHost(host) ? demo : real;

  @override
  Future<List<School>> searchSchools(String query) => real.searchSchools(query);

  @override
  Future<LoginResult> login({
    required School school,
    required String username,
    required String passwordOrKey,
    bool anonymous = false,
    String? twoFactorToken,
    bool skipAppSecret = false,
    String? hostOverride,
  }) => _for(hostOverride ?? school.host).login(
    school: school,
    username: username,
    passwordOrKey: passwordOrKey,
    anonymous: anonymous,
    twoFactorToken: twoFactorToken,
    skipAppSecret: skipAppSecret,
    hostOverride: hostOverride,
  );

  @override
  Future<TimetableResponse> timetable({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
    required int masterDataTimestamp,
  }) => _for(host).timetable(
    host: host,
    school: school,
    auth: auth,
    target: target,
    start: start,
    end: end,
    masterDataTimestamp: masterDataTimestamp,
  );

  @override
  Future<List<Message>> messagesOfDay({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime date,
  }) =>
      _for(host)
          .messagesOfDay(host: host, school: school, auth: auth, date: date);

  @override
  Future<void> probeTeacherSources({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime weekStart,
  }) => _for(host).probeTeacherSources(
    host: host,
    school: school,
    auth: auth,
    target: target,
    weekStart: weekStart,
  );

  @override
  List<({String method, DateTime at, String json})> get debugLog =>
      [...real.debugLog, ...demo.debugLog]
        ..sort((a, b) => a.at.compareTo(b.at));

  @override
  Future<List<HomeworkItem>> homework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) => _for(host).homework(
    host: host,
    school: school,
    auth: auth,
    target: target,
    start: start,
    end: end,
  );

  @override
  Future<List<ExamItem>> exams({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  }) => _for(host).exams(
    host: host,
    school: school,
    auth: auth,
    target: target,
    start: start,
    end: end,
  );

  @override
  Future<List<AbsenceItem>> absences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  }) => _for(host).absences(
    host: host,
    school: school,
    auth: auth,
    start: start,
    end: end,
    studentId: studentId,
  );

  @override
  Future<List<RawAbsence>> rawAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  }) => _for(host).rawAbsences(
    host: host,
    school: school,
    auth: auth,
    start: start,
    end: end,
    studentId: studentId,
  );

  @override
  Future<AbsenceLookups> absenceLookups({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _for(host).absenceLookups(host: host, school: school, auth: auth);

  @override
  Future<List<OfficeHourItem>> officeHours({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
  }) => _for(host).officeHours(
    host: host,
    school: school,
    auth: auth,
    klasseId: klasseId,
    start: start,
  );

  @override
  Future<List<InboxMessage>> inbox({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _for(host).inbox(host: host, school: school, auth: auth);

  @override
  Future<InboxMessageDetail> inboxMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  }) => _for(host).inboxMessage(host: host, school: school, auth: auth, id: id);
}
