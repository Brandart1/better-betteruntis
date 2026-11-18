/// Parser for class absence lists (teacher absence summaries, all-subjects
/// scope): the getClassregData2017 answer `{absences:[UMStudentAbsence],
/// referencedStudents}`. Keys are still accepted tolerantly: the classic
/// `GET /WebUntis/api/classreg/absences/students` shape (`{data:{absences:
/// [{id, studentId?, studentName, startDate, startTime, endDate, endTime,
/// isExcused, excuseStatus, reason, text, excuse:{…}}]}}`, seen for parents)
/// and the getStudentAbsences2017 shape (`{absences:[{id, studentId?,
/// startDateTime, endDateTime, excused, …}]}`).
library;

import '../core/absence_summary.dart';
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
  String s => s.trim(),
  num n => n.toString(),
  _ => '',
};

bool? _boolOrNull(Object? v) => switch (v) {
  bool b => b,
  num n => n != 0,
  String s when s.toLowerCase() == 'true' => true,
  String s when s.toLowerCase() == 'false' => false,
  _ => null,
};

String _first(Map<String, Object?> j, List<String> keys) {
  for (final k in keys) {
    final s = _str(j[k]);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// `<prefix>DateTime` (ISO / epoch ms), else `<prefix>Date` (yyyyMMdd or
/// ISO) + `<prefix>Time` (hhmm).
DateTime? _at(Map<String, Object?> j, String prefix) {
  final raw = j['${prefix}DateTime'] ?? j[prefix];
  if (raw is int && raw > 99991231) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  final dt = parseDateTime(raw);
  if (dt != null) return dt;
  final d = parseDate(j['${prefix}Date']) ?? parseDateTime(j['${prefix}Date']);
  if (d == null) return null;
  final t = parseTime(j['${prefix}Time']);
  return t == null ? d : DateTime(d.year, d.month, d.day, t ~/ 60, t % 60);
}

/// The list of absences: under `data.absences`, `absences`, `data` (a
/// list) or a top-level list.
Iterable<Map<String, Object?>> _items(Object? raw) {
  if (raw is List) return _maps(raw);
  final j = _map(raw);
  final data = j['data'];
  if (data is List) return _maps(data);
  final d = _map(data);
  return _maps(
    d['absences'] ?? d['studentAbsences'] ?? j['absences'] ?? j['items'],
  );
}

ClassAbsenceRecord? parseClassAbsenceRecord(
  Map<String, Object?> j, {
  Map<int, String> students = const {},
}) {
  final id = _int(j['id'] ?? j['absenceId']);
  final start = _at(j, 'start');
  if (id == null || start == null) return null;
  var end = _at(j, 'end') ?? start;
  if (end.isBefore(start)) end = start;
  final student = _map(j['student']);
  var name = j['student'] is String
      ? _str(j['student'])
      : _first(j, ['studentName', 'displayNameStudent', 'name']);
  if (name.isEmpty && student.isNotEmpty) {
    name = _first(student, ['displayName', 'longName', 'name']);
    if (name.isEmpty) {
      name = [
        _str(student['lastName']),
        _str(student['firstName']),
      ].where((s) => s.isNotEmpty).join(' ');
    }
  }
  final studentId = _int(j['studentId'] ?? student['id']);
  if (name.isEmpty && studentId != null) name = students[studentId] ?? '';
  final excuse = _map(j['excuse']);
  final excused =
      _boolOrNull(j['isExcused'] ?? j['excused'] ?? excuse['isExcused']) ??
      false;
  final status = j['excuseStatus'] is String
      ? _str(j['excuseStatus'])
      : _first(excuse, ['excuseStatus']);
  final statusId = _int(j['excuseStatusId'] ?? excuse['excuseStatusId']);
  final reasonMap = _map(j['reason']);
  final reason = j['reason'] is String
      ? _str(j['reason'])
      : (reasonMap.isNotEmpty
            ? _first(reasonMap, ['longName', 'name'])
            : _first(j, ['absenceReason', 'reasonName']));
  final late =
      _boolOrNull(j['isLate'] ?? j['late'] ?? j['lateness']) ??
      (_str(j['type']).toUpperCase().contains('LATE'));
  return ClassAbsenceRecord(
    id: id,
    studentId: studentId != null && studentId > 0 ? studentId : null,
    studentName: name,
    klasseId: _int(j['klasseId'] ?? j['classId']),
    start: start,
    end: end,
    state: excused
        ? ExcuseState.excused
        : RegExp('offen|open', caseSensitive: false).hasMatch(status)
        ? ExcuseState.open
        : (status.isNotEmpty || (statusId != null && statusId > 0))
        ? ExcuseState.unexcused
        : ExcuseState.open,
    reason: reason,
    text: _first(j, ['text', 'note', 'remark']),
    late: late,
  );
}

/// All absences of a class answer; entries without id or start are dropped.
///
/// getClassregData2017 carries no pupil names on the absences; they come
/// from `referencedStudents` (by `studentId`).
List<ClassAbsenceRecord> parseClassAbsenceRecords(Object? raw) {
  final names = <int, String>{};
  for (final s in _maps(_map(raw)['referencedStudents'])) {
    final id = _int(s['id']);
    if (id == null) continue;
    final n = [
      _str(s['lastName']),
      _str(s['firstName']),
    ].where((x) => x.isNotEmpty).join(' ');
    if (n.isNotEmpty) names[id] = n;
  }
  return [
    for (final e in _items(raw)) ?parseClassAbsenceRecord(e, students: names),
  ];
}
