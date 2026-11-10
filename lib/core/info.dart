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

/// Office hour from getOfficeHours2017 (carries names directly).
class OfficeHourItem {
  const OfficeHourItem({
    required this.id,
    required this.start,
    required this.end,
    required this.teacherName,
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

  Future<List<AbsenceItem>> absences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
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
  Stream<Cached<List<OfficeHourItem>>> officeHours(Account a, DateTime start, {bool force = false});
}

final infoCenterRepositoryProvider = Provider<InfoCenterRepository>(
  (ref) => throw UnimplementedError('override infoCenterRepositoryProvider'),
);
