/// Parsers and payloads for the teacher class register (getPeriodData2017,
/// createImmediateAbsence2017, …). Field names are tolerant on purpose: only
/// the shape BetterUntis-style clients use is known, no real teacher response
/// has been seen yet (docs/API.md "Class register (teachers)").
library;

import '../core/class_register.dart';
import 'parsers.dart';

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

/// Keys a pupil's photo URL might come in. None seen in a real
/// getPeriodData2017 answer yet; `imageUrl` is what the WebUntis REST API
/// uses for persons (`api/rest/view/v1/app/data`, messenger).
const studentImageKeys = [
  'imageUrl',
  'imageURL',
  'image',
  'photoUrl',
  'photo',
  'pictureUrl',
  'picture',
  'avatarUrl',
  'portraitUrl',
];

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

/// For the Debug log: every key the pupils of a getPeriodData2017 answer
/// carry (sorted, no values) and how many have a photo URL.
Map<String, Object?> referencedStudentsShape(Object? raw) {
  final students = _maps(_map(raw)['referencedStudents']).toList();
  return {
    'count': students.length,
    'keys': {for (final s in students) ...s.keys}.toList()..sort(),
    'withImageUrl': students.where((s) => studentImageUrl(s) != null).length,
  };
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
    reasonId: _int(j['absenceReasonId'] ?? j['reasonId']),
    text: _firstStr(j, ['text', 'reason']),
    excused: _bool(j['excused'] ?? j['isExcused'] ?? excuse['isExcused']),
    excuseStatusId: _int(j['excuseStatusId'] ?? excuse['excuseStatusId']),
    excuseStatus: j['excuseStatus'] is String
        ? _str(j['excuseStatus']).trim()
        : _firstStr(excuse, ['excuseStatus']),
  );
}

/// A class register entry ("Klassenbucheintrag"). No real response seen:
/// every key is a guess (`id`/`eventId`, `studentId`/`student{id,…}`,
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
  final studentId =
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
