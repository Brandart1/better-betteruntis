/// Parsers and payloads for the teacher class register (getPeriodData2017,
/// createImmediateAbsence2017, …). Field names are tolerant on purpose: only
/// the shape BetterUntis-style clients use is known, no real teacher response
/// has been seen yet (docs/API.md "Class register (teachers)").
library;

import '../core/class_register.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import 'parsers.dart';
import 'teacher_tools_parsers.dart';

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

Iterable<Map<String, Object?>> _maps(Object? v) =>
    (v is List ? v : const []).whereType<Map>().map(_map);

int? _int(Object? v) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s.trim()),
  _ => null,
};

String _str(Object? v) => switch (v) {
  String s => s,
  num n => n.toString(),
  _ => '',
};

bool _bool(Object? v) => switch (v) {
  bool b => b,
  num n => n != 0,
  String s => s.toLowerCase() == 'true',
  _ => false,
};

String _firstStr(Map<String, Object?> j, List<String> keys) {
  for (final k in keys) {
    final s = _str(j[k]).trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

ClassRegStudent? parseClassRegStudent(Map<String, Object?> j) {
  final id = _int(j['id'] ?? j['studentId']);
  if (id == null || id <= 0) return null;
  var first = _firstStr(j, ['firstName', 'foreName', 'forename']);
  var last = _firstStr(j, ['lastName', 'surName', 'surname', 'longName']);
  if (first.isEmpty && last.isEmpty) {
    last = _firstStr(j, ['displayName', 'fullName', 'name', 'key']);
    if (last.isEmpty) last = '#$id';
  }
  return ClassRegStudent(
    id: id,
    firstName: first,
    lastName: last,
    klasseId: _int(j['klasseId'] ?? j['classId']),
    imageUrl: studentImageUrl(j),
  );
}

/// Keys a pupil's photo URL comes in: `imageUrl` (getUserData2017
/// `masterData.students[]`, loaded as given by the official app).
const studentImageKeys = ['imageUrl'];

/// The photo URL of a pupil object, or null. Only URLs (absolute http(s) or
/// a server path starting with `/`) count; inline data and ids don't.
String? studentImageUrl(Map<String, Object?> j) {
  for (final k in studentImageKeys) {
    final v = j[k];
    final s = (v is Map ? _firstStr(_map(v), ['url', 'href', 'src']) : _str(v))
        .trim();
    if (s.startsWith('/') && !s.startsWith('//')) return s;
    final u = Uri.tryParse(s);
    if (u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.host.isNotEmpty) {
      return s;
    }
  }
  return null;
}

ClassRegAbsence? parseClassRegAbsence(Map<String, Object?> j) {
  final id = _int(j['id'] ?? j['absenceId']);
  final student = _int(j['studentId'] ?? _map(j['student'])['id']);
  final start = parseDateTime(j['startDateTime'] ?? j['start']);
  final end = parseDateTime(j['endDateTime'] ?? j['end']);
  if (id == null || student == null || start == null || end == null) {
    return null;
  }
  final excuse = _map(j['excuse']);
  return ClassRegAbsence(
    id: id,
    studentId: student,
    start: start,
    end: end,
    // 0 = no reason (the official app sends 0 for none).
    reasonId: switch (_int(j['absenceReasonId'] ?? j['reasonId'])) {
      0 => null,
      final id => id,
    },
    text: _str(j['text']),
    excused: _bool(j['excused'] ?? j['isExcused'] ?? excuse['isExcused']),
    excuseStatusId: _int(j['excuseStatusId'] ?? excuse['excuseStatusId']),
    excuseStatus: j['excuseStatus'] is String
        ? _str(j['excuseStatus']).trim()
        : _firstStr(excuse, ['excuseStatus']),
    excuseText: _str(excuse['text']).trim(),
    reasonName: j['absenceReason'] is String
        ? _str(j['absenceReason']).trim()
        : j['reason'] is String
        ? _str(j['reason']).trim()
        : '',
  );
}

/// A class register entry ("Klassenbucheintrag"). Official shape
/// (getPeriodData2017 / getClassregData2017 `classRegEvents`): `{id,
/// elementType, elementId, eventReasonId, dateTime, text}`; the older
/// guessed keys are still read (`id`/`eventId`, `studentId`/`student{id,…}`,
/// `eventReasonId`/`reasonId`/`eventReason{id,name}`, `text`/`remark`, a
/// date in `dateTime`/`startDateTime`/`date`/…). Null when it carries
/// nothing to show.
ClassRegEvent? parseClassRegEvent(Map<String, Object?> j, {int? ttId}) {
  final student = j['student'];
  final studentMap = _map(student);
  final reason = j['eventReason'] ?? j['reason'];
  final reasonMap = _map(reason);
  var studentName = student is String
      ? student.trim()
      : _firstStr(j, ['studentName', 'displayNameStudent']);
  if (studentName.isEmpty && studentMap.isNotEmpty) {
    studentName = parseClassRegStudent(studentMap)?.displayName ?? '';
    if (studentName.startsWith('#')) studentName = '';
  }
  final studentIds = j['studentIds'];
  // Official shape: `elementType`/`elementId` (STUDENT = a pupil).
  final elementId = _int(j['elementId']);
  final elementStudent =
      j.containsKey('elementType') &&
          ElementType.parse(j['elementType']) == ElementType.student &&
          (elementId ?? 0) > 0
      ? elementId
      : null;
  final studentId =
      elementStudent ??
      _int(j['studentId'] ?? studentMap['id']) ??
      (studentIds is List && studentIds.length == 1
          ? _int(studentIds.first)
          : null);
  final reasonId = _int(
    j['eventReasonId'] ??
        j['reasonId'] ??
        j['classRegEventReasonId'] ??
        reasonMap['id'],
  );
  final reasonName = reason is String
      ? reason.trim()
      : _firstStr(
          {...reasonMap, ...j},
          ['eventReasonName', 'reasonName', 'longName', 'name'],
        );
  final text = _firstStr(j, ['text', 'remark', 'description', 'comment']);
  if (text.isEmpty && reasonId == null && reasonName.isEmpty) return null;
  DateTime? date;
  for (final k in const [
    'dateTime',
    'startDateTime',
    'date',
    'eventDate',
    'createDate',
    'createdAt',
  ]) {
    date = _date(j[k]);
    if (date != null) break;
  }
  return ClassRegEvent(
    id: _int(j['id'] ?? j['eventId']),
    ttId: _int(j['ttId'] ?? j['periodId']) ?? ttId,
    studentId: studentId != null && studentId > 0 ? studentId : null,
    studentName: studentName,
    reasonId: reasonId,
    reasonName: reasonName,
    text: text,
    date: date,
    author: _firstStr(j, ['teacherName', 'createdBy', 'creator', 'author']),
  );
}

/// ISO date(-time), yyyyMMdd, or epoch milliseconds.
DateTime? _date(Object? v) => switch (v) {
  int n when n > 99991231 => DateTime.fromMillisecondsSinceEpoch(n),
  _ => parseDateTime(v) ?? parseDate(v),
};

List<ClassRegEvent> _events(Object? raw, {int? ttId}) =>
    _maps(raw)
        .map((e) => parseClassRegEvent(e, ttId: ttId))
        .whereType<ClassRegEvent>()
        .toList();

Object? _eventList(Map<String, Object?> j) =>
    j['classRegEvents'] ??
    j['classregEvents'] ??
    j['classRegEntries'] ??
    j['events'];

/// `topic` is a string, or an object with `text`/`lessonTopic`.
String _topic(Object? raw) => switch (raw) {
  String s => s,
  Map m => _firstStr(_map(m), ['text', 'lessonTopic', 'topic']),
  _ => '',
};

PeriodRegister parsePeriodRegister(int ttId, Map<String, Object?> j) =>
    PeriodRegister(
      ttId: _int(j['ttId']) ?? ttId,
      absenceChecked: _bool(j['absenceChecked'] ?? j['absencesChecked']),
      studentIds: (j['studentIds'] is List ? j['studentIds'] as List : const [])
          .map(_int)
          .whereType<int>()
          .toList(),
      absences: _maps(j['absences'])
          .map(parseClassRegAbsence)
          .whereType<ClassRegAbsence>()
          .toList(),
      topic: _topic(j['topic'] ?? j['lessonTopic']),
      events: _events(_eventList(j), ttId: _int(j['ttId']) ?? ttId),
      homework: _maps(j['homeWorks'] ?? j['homeworks'])
          .map(parseHomework)
          .whereType<Homework>()
          .toList(),
    );

/// getPeriodData2017 result:
/// `{dataByTTId:{"<id>":{…, classRegEvents?:[…]}}, referencedStudents:[…]}`.
PeriodRegisterData parsePeriodData(Object? raw) {
  final j = _map(raw);
  final byId = _map(j['dataByTTId']);
  final periods = <int, PeriodRegister>{};
  for (final e in byId.entries) {
    final id = int.tryParse(e.key);
    if (id == null || e.value is! Map) continue;
    periods[id] = parsePeriodRegister(id, _map(e.value));
  }
  // Entries may also come as one top-level list with a ttId per item.
  final loose = _events(_eventList(j));
  for (final ev in loose) {
    final r = periods[ev.ttId];
    if (r == null) continue;
    periods[r.ttId] = PeriodRegister(
      ttId: r.ttId,
      absenceChecked: r.absenceChecked,
      studentIds: r.studentIds,
      absences: r.absences,
      topic: r.topic,
      events: [...r.events, ev],
      homework: r.homework,
    );
  }
  return PeriodRegisterData(
    periods: periods,
    students: {
      for (final s in _maps(
        j['referencedStudents'] ?? j['students'],
      ).map(parseClassRegStudent).whereType<ClassRegStudent>())
        s.id: s,
    },
  );
}

/// "T08:00" (Untis' time format).
String formatUntisTime(DateTime d) =>
    'T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Id of [studentId]'s absence in a createImmediateAbsence2017 answer
/// (`{absences:[UMStudentAbsence]}`), null when there is none.
int? createdAbsenceId(Object? result, int studentId) {
  final list = result is Map ? result['absences'] : result;
  for (final a in _maps(list)) {
    if (_int(a['studentId']) == studentId) return _int(a['id']);
  }
  return null;
}

/// editAbsence2017 params (from the official app's `EditAbsenceRequest`):
/// times as local `yyyy-MM-ddTHH:mmZ` (literal Z), reason 0 = none, the
/// excuse kept as it is, strategy WRITE (no merging with other absences).
Map<String, Object?> editAbsenceParams(int ttId, ClassRegAbsence a) => {
  'absenceId': a.id,
  'periodId': ttId,
  'startDateTime': '${formatUntisDateTime(a.start)}Z',
  'endDateTime': '${formatUntisDateTime(a.end)}Z',
  'absenceReasonId': a.reasonId ?? 0,
  'text': a.text.trim(),
  'excuseStatusId': a.excuseStatusId ?? 0,
  'excuseText': a.excuseText.trim(),
  'strategy': 'WRITE',
};

/// The conflicts of an editAbsence2017 answer
/// (`{result:{absences, conflicts:[UMStudentAbsence], …}}`): absences the
/// change would overlap; the change is not saved then.
int absenceConflicts(Object? result) {
  final r = result is Map ? result['result'] ?? result : null;
  return r is Map ? _maps(r['conflicts']).length : 0;
}

/// submitHomeWork params (from the official app): the lesson [ttId] it is
/// given in and the homework with dates as yyyy-MM-dd, id 0 for new.
Map<String, Object?> submitHomeworkParams(int ttId, Homework h) => {
  'ttId': ttId,
  'homeWork': {
    'id': h.id,
    'lessonId': h.lessonId,
    'startDate': formatDate(h.startDate),
    'endDate': formatDate(h.endDate),
    'text': h.text.trim(),
    'remark': h.remark.trim(),
    'completed': h.completed,
  },
};

/// The id of a submitHomeWork answer (`{success, submittedHomeWorkId}`),
/// null when it has none. Throws when the server says it was not saved.
int? submittedHomeworkId(Object? result) {
  final j = _map(result);
  if (j['success'] case final ok? when !_bool(ok)) {
    throw const UntisException(0, 'The server did not save the homework.');
  }
  return switch (_int(j['submittedHomeWorkId'] ?? j['id'])) {
    final id? when id > 0 => id,
    _ => null,
  };
}

/// submitClassRegEvents params (besides `auth`) for one pupil: `id` 0 =
/// new entry, else edits that entry. `startTime` is "THH:mm".
Map<String, Object?> submitClassRegEventParams({
  required int ttId,
  required int studentId,
  required DateTime start,
  required String text,
  int? reasonId,
  int? eventId,
}) => {
  'ttId': ttId,
  'event': {
    'id': eventId ?? 0,
    'element': {'type': ElementType.student.code, 'id': studentId},
    'date': formatDate(start),
    'startTime': formatUntisTime(start),
    'text': text.trim(),
    'reasonId': reasonId ?? 0,
  },
};
