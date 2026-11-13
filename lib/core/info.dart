/// Info center contract: messages, homework, exams, absences, office hours.
///
/// Implemented by lib/api (UntisApi additions in [InfoCenterApi]) and
/// lib/data ([InfoCenterRepository]); rendered by lib/ui/infocenter.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';

/// A message from the REST inbox (`/WebUntis/api/rest/view/v1/messages`).
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.subject,
    required this.preview,
    required this.sender,
    required this.sentAt,
    this.isRead = false,
    this.hasAttachments = false,
  });

  final int id;
  final String subject;

  /// Plain-text preview (`contentPreview`).
  final String preview;

  /// Display name of the sender, or '' when unknown.
  final String sender;
  final DateTime? sentAt;
  final bool isRead;
  final bool hasAttachments;
}

/// Full message body (`/messages/{id}`).
class InboxMessageDetail {
  const InboxMessageDetail({
    required this.id,
    required this.subject,
    required this.bodyHtml,
    required this.sender,
    required this.sentAt,
    this.attachments = const [],
  });

  final int id;
  final String subject;
  final String bodyHtml;
  final String sender;
  final DateTime? sentAt;
  final List<({String name, String url})> attachments;
}

/// Homework from getHomeWork2017, with its lesson resolved where possible.
class HomeworkItem {
  const HomeworkItem({
    required this.id,
    required this.lessonId,
    required this.assignedOn,
    required this.dueOn,
    required this.text,
    this.remark = '',
    this.completed = false,
    this.subjectId,
    this.teacherIds = const [],
    this.klassenIds = const [],
    this.attachments = const [],
  });

  final int id;
  final int lessonId;
  final DateTime assignedOn;
  final DateTime dueOn;
  final String text;
  final String remark;
  final bool completed;

  /// From `lessonsById[lessonId]`; resolve with the NameResolver. Teacher ids
  /// may not resolve for students (schools hide teachers) — hide those.
  final int? subjectId;
  final List<int> teacherIds;
  final List<int> klassenIds;
  final List<({String name, String url})> attachments;
}

/// Exam from getExams2017.
class ExamItem {
  const ExamItem({
    required this.id,
    required this.start,
    required this.end,
    this.examType = '',
    this.name = '',
    this.text = '',
    this.subjectId,
    this.klassenIds = const [],
    this.roomIds = const [],
    this.teacherIds = const [],
  });

  final int id;
  final DateTime start;
  final DateTime end;
  final String examType;
  final String name;
  final String text;
  final int? subjectId;
  final List<int> klassenIds;
  final List<int> roomIds;
  final List<int> teacherIds;
}

/// Absence from getStudentAbsences2017.
class AbsenceItem {
  const AbsenceItem({
    required this.id,
    required this.start,
    required this.end,
    required this.excused,
    this.reason = '',
    this.text = '',
    this.excuseStatus = '',
  });

  final int id;
  final DateTime start;
  final DateTime end;
  final bool excused;

  /// Absence reason long name (resolved from master `absenceReasons` or the
  /// inline `absenceReason` string).
  final String reason;
  final String text;

  /// Excuse status name (e.g. "entschuldigt"), '' when none.
  final String excuseStatus;
}

/// A reason a parent can pick when reporting an absence.
class AbsenceReason {
  const AbsenceReason({required this.id, required this.name});
  final int id;
  final String name;
}

/// What the "Report absence" form needs: the school's reasons and defaults.
class AbsenceReportOptions {
  const AbsenceReportOptions({
    this.reasons = const [],
    this.defaultReasonId,
    this.allowed,
    this.defaultStartMinutes,
    this.defaultEndMinutes,
    this.notice = '',
  });

  /// Selectable reasons (may be empty when the school sent none).
  final List<AbsenceReason> reasons;
  final int? defaultReasonId;

  /// Whether the school lets this account report absences: true/false when
  /// the server said so (`showCreateAbsence`), null when unknown.
  final bool? allowed;

  /// Default start/end time of day (minutes since midnight), when the server
  /// suggests one.
  final int? defaultStartMinutes;
  final int? defaultEndMinutes;

  /// Why options are incomplete (e.g. the reasons could not be loaded and
  /// come from master data instead); '' when everything loaded.
  final String notice;
}

/// A new absence reported by a parent for [studentId].
class AbsenceReport {
  const AbsenceReport({
    required this.studentId,
    required this.start,
    required this.end,
    this.reasonId,
    this.text = '',
  });

  final int studentId;
  final DateTime start;
  final DateTime end;

  /// Null when the school offers no reasons.
  final int? reasonId;
  final String text;
}

/// Server-side view of one absence from the classreg absence list (parent
/// accounts): who entered it and whether this account may still delete it.
class AbsenceRecord {
  const AbsenceRecord({
    required this.id,
    required this.start,
    required this.end,
    this.canEdit = false,
    this.createdUser = '',
    this.updatedUser = '',
    this.created,
    this.updated,
  });

  final int id;
  final DateTime start;
  final DateTime end;

  /// The school's `canEdit`: this account may still delete it.
  final bool canEdit;

  /// Teacher short name (e.g. "Fch") or a parent's login (an email).
  final String createdUser;
  final String updatedUser;
  final DateTime? created;
  final DateTime? updated;
}

/// Office hour from getOfficeHours2017 (carries names directly).
class OfficeHourItem {
  const OfficeHourItem({
    required this.id,
    required this.start,
    required this.end,
    required this.teacherName,
    this.teacherId = 0,
    this.rooms = '',
    this.email = '',
    this.phone = '',
    this.registrationPossible = false,
    this.registered = false,
  });

  final int id;
  final DateTime start;
  final DateTime end;
  final String teacherName;

  /// The teacher's element id when the response has one, else 0. Names alone
  /// aren't unique (some schools send only last names).
  final int teacherId;
  final String rooms;
  final String email;
  final String phone;
  final bool registrationPossible;
  final bool registered;
}

/// Info center calls. [UntisApi] implementations also implement this.
abstract interface class InfoCenterApi {
  Future<List<HomeworkItem>> homework({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  });

  Future<List<ExamItem>> exams({
    required String host,
    required String school,
    required UntisCredentials auth,
    required TimetableTarget target,
    required DateTime start,
    required DateTime end,
  });

  /// [studentId]: parent accounts pass the child; null = the user's own
  /// absences (the request then looks exactly as before).
  Future<List<AbsenceItem>> absences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  });

  Future<List<OfficeHourItem>> officeHours({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int klasseId,
    required DateTime start,
  });

  /// REST inbox (bearer token from getAuthToken).
  Future<List<InboxMessage>> inbox({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  Future<InboxMessageDetail> inboxMessage({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int id,
  });
}

/// One emission of a cache-first info stream.
class Cached<T> {
  const Cached({this.data, this.fetchedAt, this.error, this.refreshing = false});

  /// Cached or fresh data; null while nothing is known yet.
  final T? data;
  final DateTime? fetchedAt;

  /// Last refresh failure (data may still be shown from cache).
  final UntisException? error;

  /// A network refresh is in progress.
  final bool refreshing;
}

/// Cache-first info center data per account. Each stream emits the cached
/// value immediately (if any), then the network result. Re-subscribing
/// (e.g. pull-to-refresh invalidating the provider) triggers a new refresh;
/// pass `force: true` to bypass the freshness window.
abstract interface class InfoCenterRepository {
  Stream<Cached<List<Message>>> messagesOfDay(Account a, DateTime day, {bool force = false});
  Stream<Cached<List<InboxMessage>>> inbox(Account a, {bool force = false});
  Future<InboxMessageDetail> inboxMessage(Account a, int id);
  Stream<Cached<List<HomeworkItem>>> homework(Account a, DateTime start, DateTime end, {bool force = false});
  Stream<Cached<List<ExamItem>>> exams(Account a, DateTime start, DateTime end, {bool force = false});
  Stream<Cached<List<AbsenceItem>>> absences(Account a, DateTime start, DateTime end, {bool force = false});

  /// Reasons and defaults for reporting an absence for [studentId] (a child
  /// of parent account [a]). Never throws for a missing reason list; throws
  /// [UntisException] only when nothing at all is known.
  Future<AbsenceReportOptions> absenceReportOptions(Account a, int studentId);

  /// Reports a new absence ("Abwesenheit melden"). On success the cached
  /// absences of [a] are dropped, so the next subscription loads fresh data.
  /// Throws [UntisException].
  Future<void> reportAbsence(Account a, AbsenceReport report);

  /// The classreg record of [item] (who entered it, whether it may be
  /// deleted) for the selected child of parent account [a]. Null when the
  /// account has no child or the school's list doesn't contain it. Throws
  /// [UntisException].
  Future<AbsenceRecord?> absenceRecord(Account a, AbsenceItem item);

  /// Deletes absence [id] of the selected child. On success the cached
  /// absences of [a] are dropped. Throws [UntisException].
  Future<void> deleteAbsence(Account a, int id);
  /// Office hours of all teachers, or with [onlyMyClass] those of the
  /// account's (or selected child's) class.
  Stream<Cached<List<OfficeHourItem>>> officeHours(
    Account a,
    DateTime start, {
    bool force = false,
    bool onlyMyClass = false,
  });
}

final infoCenterRepositoryProvider = Provider<InfoCenterRepository>(
  (ref) => throw UnimplementedError('override infoCenterRepositoryProvider'),
);
