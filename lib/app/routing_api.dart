import '../core/interfaces.dart';
import '../core/models.dart';

/// Sends demo accounts (host `*.invalid`) to [demo] and everything else to
/// [real], so demo profiles live alongside real ones in the same database.
class RoutingUntisApi implements UntisApi {
  RoutingUntisApi({required this.real, required this.demo});

  final UntisApi real;
  final UntisApi demo;

  static bool isDemoHost(String host) => host.endsWith('.invalid');
  UntisApi _for(String host) => isDemoHost(host) ? demo : real;

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
  }) => _for(host).messagesOfDay(host: host, school: school, auth: auth, date: date);

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
      [...real.debugLog, ...demo.debugLog]..sort((a, b) => a.at.compareTo(b.at));
}
