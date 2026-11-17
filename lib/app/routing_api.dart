import 'dart:typed_data';

import '../core/absence_details.dart';
import '../core/absence_summary.dart';
import '../core/class_lead.dart';
import '../core/class_register.dart';
import '../core/excuses.dart';
import '../core/info.dart';
import '../core/interfaces.dart';

import '../core/models.dart';
import '../core/pupil_photos.dart';
import '../core/teacher_tools.dart';

/// Sends demo accounts (host `*.invalid`) to [demo] and everything else to
/// [real], so demo profiles live alongside real ones in the same database.
class RoutingUntisApi
    implements
        FullUntisApi,
        TeacherToolsApi,
        ClassAbsencesApi,
        PupilPhotoApi,
        ExcuseApi,
        ClassLeadApi {
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
  Future<String> restAuthToken({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _for(host).restAuthToken(host: host, school: school, auth: auth);

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

  @override
  Future<AbsenceReportOptions> absenceReportOptions({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
  }) => _for(host).absenceReportOptions(
    host: host,
    school: school,
    auth: auth,
    studentId: studentId,
  );

  @override
  Future<void> reportAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required AbsenceReport report,
  }) => _for(host)
      .reportAbsence(host: host, school: school, auth: auth, report: report);

  @override
  Future<List<AbsenceRecord>> absenceRecords({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) => _for(host).absenceRecords(
    host: host,
    school: school,
    auth: auth,
    studentId: studentId,
    start: start,
    end: end,
  );

  @override
  Future<void> deleteAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ids,
  }) =>
      _for(host)
          .deleteAbsences(host: host, school: school, auth: auth, ids: ids);

  @override
  Future<PeriodRegisterData> periodData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) =>
      _for(host)
          .periodData(host: host, school: school, auth: auth, ttIds: ttIds);

  @override
  Future<void> submitLessonTopic({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required String topic,
  }) => _for(host).submitLessonTopic(
    host: host,
    school: school,
    auth: auth,
    ttId: ttId,
    topic: topic,
  );

  @override
  Future<int?> createAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required int studentId,
    required DateTime start,
    required DateTime end,
  }) => _for(host).createAbsence(
    host: host,
    school: school,
    auth: auth,
    ttId: ttId,
    studentId: studentId,
    start: start,
    end: end,
  );

  @override
  Future<void> deleteAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int absenceId,
  }) => _for(
    host,
  ).deleteAbsence(host: host, school: school, auth: auth, absenceId: absenceId);

  @override
  Future<void> editAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required ClassRegAbsence absence,
  }) => _for(host).editAbsence(
    host: host,
    school: school,
    auth: auth,
    ttId: ttId,
    absence: absence,
  );

  @override
  Future<int?> submitHomework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    required Homework homework,
  }) => _for(host).submitHomework(
    host: host,
    school: school,
    auth: auth,
    ttId: ttId,
    homework: homework,
  );

  @override
  Future<Map<int, String>> absenceReasons({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _for(host).absenceReasons(host: host, school: school, auth: auth);

  @override
  Future<void> submitAbsencesChecked({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ttIds,
  }) => _for(
    host,
  ).submitAbsencesChecked(host: host, school: school, auth: auth, ttIds: ttIds);

  @override
  Future<Map<int, String>> eventReasons({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _for(host).eventReasons(host: host, school: school, auth: auth);

  @override
  Future<void> createClassRegEvent({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int ttId,
    int? studentId,
    int? eventReasonId,
    required String text,
  }) => _for(host).createClassRegEvent(
    host: host,
    school: school,
    auth: auth,
    ttId: ttId,
    studentId: studentId,
    eventReasonId: eventReasonId,
    text: text,
  );

  // ---- Teacher tools (room changes, exams) --------------------------------

  TeacherToolsApi _tools(String host) {
    final Object a = _for(host);
    if (a is TeacherToolsApi) return a;
    throw const UntisException(-1, 'Not supported for this account.');
  }

  @override
  Future<FreeRooms> roomChangeData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
  }) => _tools(host).roomChangeData(
    host: host,
    school: school,
    auth: auth,
    periodIds: periodIds,
  );

  @override
  Future<FreeRooms> availableRooms({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
  }) => _tools(host).availableRooms(
    host: host,
    school: school,
    auth: auth,
    start: start,
    end: end,
  );

  @override
  Future<RoomChangeResult> submitRoomChange({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> periodIds,
    required int orgRoomId,
    required int roomId,
  }) => _tools(host).submitRoomChange(
    host: host,
    school: school,
    auth: auth,
    periodIds: periodIds,
    orgRoomId: orgRoomId,
    roomId: roomId,
  );

  @override
  Future<bool> submitPeriodInfo({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required String text,
  }) => _tools(host).submitPeriodInfo(
    host: host,
    school: school,
    auth: auth,
    periodId: periodId,
    text: text,
  );

  @override
  Future<StaffNotes> lessonStaffNotes({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
  }) => _tools(host).lessonStaffNotes(
    host: host,
    school: school,
    auth: auth,
    periodId: periodId,
  );

  @override
  Future<StaffNotes?> submitStaffNotes({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int periodId,
    required String text,
    bool wholeBlock = false,
  }) => _tools(host).submitStaffNotes(
    host: host,
    school: school,
    auth: auth,
    periodId: periodId,
    text: text,
    wholeBlock: wholeBlock,
  );

  @override
  Future<List<ExamType>> examTypes({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _tools(host).examTypes(host: host, school: school, auth: auth);

  @override
  Future<RoomBookingResult> createRoomBooking({
    required String host,
    required String school,
    required UntisCredentials auth,
    required RoomBookingRequest booking,
  }) => _tools(
    host,
  ).createRoomBooking(host: host, school: school, auth: auth, booking: booking);

  @override
  Future<int?> createExam({
    required String host,
    required String school,
    required UntisCredentials auth,
    required NewExam exam,
  }) =>
      _tools(host)
          .createExam(host: host, school: school, auth: auth, exam: exam);

  @override
  Future<List<ClassAbsenceRecord>> classAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
  }) {
    final Object a = _for(host);
    if (a is! ClassAbsencesApi) {
      throw const UntisException(-1, 'Not supported for this account.');
    }
    return a.classAbsences(
      host: host,
      school: school,
      auth: auth,
      klasseId: klasseId,
      start: start,
      end: end,
    );
  }

  @override
  Future<Uint8List?> pupilPhoto({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    String? imageUrl,
  }) async {
    final Object a = _for(host);
    if (a is! PupilPhotoApi) return null;
    return a.pupilPhoto(
      host: host,
      school: school,
      auth: auth,
      studentId: studentId,
      imageUrl: imageUrl,
    );
  }

  ExcuseApi _excuses(String host) {
    final Object a = _for(host);
    if (a is! ExcuseApi) {
      throw const UntisException(-1, 'Not supported for this account.');
    }
    return a;
  }

  @override
  Future<ExcuseMeta> excuseMeta({
    required String host,
    required String school,
    required UntisCredentials auth,
  }) => _excuses(host).excuseMeta(host: host, school: school, auth: auth);

  @override
  Future<List<ExcuseAbsence>> excuseAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required ExcuseMeta meta,
    required ExcuseQuery query,
  }) => _excuses(host).excuseAbsences(
    host: host,
    school: school,
    auth: auth,
    meta: meta,
    query: query,
  );

  @override
  Future<ExcuseAbsence?> saveExcuse({
    required String host,
    required String school,
    required UntisCredentials auth,
    required ExcuseMeta meta,
    required ExcuseAbsence absence,
    required ExcuseStatus status,
    required String text,
  }) => _excuses(host).saveExcuse(
    host: host,
    school: school,
    auth: auth,
    meta: meta,
    absence: absence,
    status: status,
    text: text,
  );

  @override
  Future<ClassLeadData> classLeadData({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
    required DateTime end,
    required ExcuseMeta meta,
  }) {
    final Object a = _for(host);
    if (a is! ClassLeadApi) {
      throw const UntisException(-1, 'Not supported for this account.');
    }
    return a.classLeadData(
      host: host,
      school: school,
      auth: auth,
      klasseId: klasseId,
      start: start,
      end: end,
      meta: meta,
    );
  }
}
