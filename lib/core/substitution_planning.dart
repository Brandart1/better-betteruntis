/// Substitution planning for teachers, like the official app's "Substitution
/// requests" ("Ask teacher") and "My absences" (report yourself absent).
///
/// Calls (from the decompiled official app, not yet seen with a real
/// teacher account): the request list, accept / decline and the own absence
/// list go to the Substitution Planning service
/// (`https://substitution.webuntis.com/api/`, bearer token plus header
/// `X-TenantID` = the URL-encoded school login); the absence form and
/// creating an absence are WebUntis REST
/// (`view/v1/teacher-absences/form`, `POST view/v1/teacher-absences`).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';
import 'settings.dart';

/// State of a substitution request (`SubstitutionRequestDto.state`).
enum SubstitutionRequestState {
  pending('PENDING', 'Open'),
  accepted('ACCEPTED', 'Accepted'),
  declined('DECLINED', 'Declined'),
  expired('EXPIRED', 'Expired'),
  taken('TAKEN', 'Taken by someone else'),
  aborted('ABORTED', 'Withdrawn'),
  unknown('', 'Unknown');

  const SubstitutionRequestState(this.apiName, this.label);
  final String apiName;
  final String label;

  static SubstitutionRequestState parse(Object? v) {
    final s = '$v'.trim().toUpperCase();
    // AskTeacherRequestStateDto also knows DECLINE.
    if (s == 'DECLINE') return declined;
    for (final t in values) {
      if (t != unknown && t.apiName == s) return t;
    }
    return unknown;
  }
}

/// One request asking this teacher to substitute a lesson.
class SubstitutionRequest {
  const SubstitutionRequest({
    required this.id,
    this.periodId,
    required this.start,
    required this.end,
    this.unitOfDay,
    this.subject = '',
    this.classes = const [],
    this.rooms = const [],
    this.absentTeacher = '',
    this.state = SubstitutionRequestState.pending,
  });

  /// The id accept / decline are sent for: `periodConflict.id`, else the
  /// period's `wuId` (like the official app).
  final int id;

  /// The WebUntis period (`period.wuId`).
  final int? periodId;
  final DateTime start;
  final DateTime end;

  /// Lesson number of the day (`unitOfDay`), when sent.
  final int? unitOfDay;
  final String subject;
  final List<String> classes;
  final List<String> rooms;

  /// The teacher who is absent (`periodConflict.originalTeacher`).
  final String absentTeacher;
  final SubstitutionRequestState state;

  bool get isPending => state == SubstitutionRequestState.pending;

  SubstitutionRequest withState(SubstitutionRequestState s) =>
      SubstitutionRequest(
        id: id,
        periodId: periodId,
        start: start,
        end: end,
        unitOfDay: unitOfDay,
        subject: subject,
        classes: classes,
        rooms: rooms,
        absentTeacher: absentTeacher,
        state: s,
      );
}

/// A reason a teacher can give for an absence (`form.reasons`).
class TeacherAbsenceReason {
  const TeacherAbsenceReason({required this.id, required this.name});
  final int id;
  final String name;
}

/// `view/v1/teacher-absences/form`: the reasons and the default times.
class TeacherAbsenceForm {
  const TeacherAbsenceForm({this.reasons = const [], this.start, this.end});

  final List<TeacherAbsenceReason> reasons;

  /// Suggested from / until (the server's default: today 07:00–19:00).
  final DateTime? start;
  final DateTime? end;
}

/// A lesson an own absence affects, with who substitutes it.
class AbsenceLesson {
  const AbsenceLesson({
    required this.start,
    required this.end,
    this.subject = '',
    this.classes = const [],
    this.substitute = '',
    this.cancelled = false,
    this.state = '',
  });

  final DateTime start;
  final DateTime end;
  final String subject;
  final List<String> classes;

  /// The teacher who takes it over, when planned.
  final String substitute;
  final bool cancelled;

  /// The own teacher entry's `conflictState` (e.g. SUBSTITUTION,
  /// OPEN_CONFLICT), as sent.
  final String state;
}

/// One absence of the teacher (`PeriodGroupDto.group.absence`).
class TeacherAbsence {
  const TeacherAbsence({
    required this.id,
    required this.start,
    required this.end,
    this.reason = '',
    this.note = '',
    this.missedPeriods,
    this.lessons = const [],
  });

  /// `wuAbsenceId` (0 when not sent).
  final int id;
  final DateTime start;
  final DateTime end;
  final String reason;

  /// The note for the substitute.
  final String note;
  final int? missedPeriods;
  final List<AbsenceLesson> lessons;
}

/// A new own absence (`TeacherAbsenceDto` of `POST view/v1/teacher-absences`).
class TeacherAbsenceDraft {
  const TeacherAbsenceDraft({
    required this.teacherId,
    required this.start,
    required this.end,
    this.reasonId,
    this.note = '',
  });

  final int teacherId;
  final DateTime start;
  final DateTime end;
  final int? reasonId;
  final String note;
}

/// Optional API capability: the substitution planning calls.
abstract interface class SubstitutionPlanningApi {
  /// Requests asking this teacher to substitute. HTTP 404 means the school
  /// doesn't use online substitution planning.
  Future<List<SubstitutionRequest>> substitutionRequests({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Accepts ([accept] true) or declines [request].
  Future<void> answerSubstitutionRequest({
    required String host,
    required String school,
    required UntisCredentials auth,
    required SubstitutionRequest request,
    required bool accept,
  });

  /// The teacher's own absences with their lessons.
  Future<List<TeacherAbsence>> teacherAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Reasons and default times for a new absence.
  Future<TeacherAbsenceForm> teacherAbsenceForm({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Reports [draft]; returns the server's id when it sends one.
  Future<int?> createTeacherAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TeacherAbsenceDraft draft,
  });
}

abstract interface class SubstitutionPlanningRepository {
  /// Requests, open ones first (each group by time). Throws
  /// [UntisException].
  Future<List<SubstitutionRequest>> requests(Account account);

  /// Answers [request]; after accepting, the own timetable week of the
  /// lesson is refreshed. Returns the request with its new state.
  Future<SubstitutionRequest> answer(
    Account account,
    SubstitutionRequest request, {
    required bool accept,
  });

  /// Own absences, upcoming and current first, then past ones (newest
  /// first).
  Future<List<TeacherAbsence>> absences(Account account);

  /// Cached per account for the session.
  Future<TeacherAbsenceForm> form(Account account);

  /// Reports an absence of the account's teacher; the own timetable weeks
  /// it covers are refreshed.
  Future<void> reportAbsence(
    Account account, {
    required DateTime start,
    required DateTime end,
    int? reasonId,
    String note = '',
  });
}

final substitutionPlanningRepositoryProvider =
    Provider<SubstitutionPlanningRepository>(
      (ref) => throw UnimplementedError(
        'override substitutionPlanningRepositoryProvider',
      ),
    );

/// Whether the school plans substitutions online (Settings, teachers; off by
/// default). Many schools arrange substitutions by phone with the admin: then
/// "Substitution requests" and "My absences" stay hidden from the menu and
/// no notifications for requests are checked.
final onlineSubstitutionPlanningProvider =
    NotifierProvider<OnlineSubstitutionPlanningSetting, bool>(
      OnlineSubstitutionPlanningSetting.new,
    );

class OnlineSubstitutionPlanningSetting extends Notifier<bool> {
  static const storeKey = 'onlineSubstitutionPlanning';
  bool _changed = false;

  @override
  bool build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached is bool) return cached;
    unawaited(_load(store));
    return false;
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw is! bool) return;
      state = raw;
    } catch (_) {
      // Unreadable: keep the default.
    }
  }

  void set(bool value) {
    _changed = true;
    if (value == state) return;
    state = value;
    unawaited(
      ref.read(settingsStoreProvider).write(storeKey, value).catchError((_) {}),
    );
  }
}
