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
  );
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
  );
}

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
    );

/// getPeriodData2017 result:
/// `{dataByTTId:{"<id>":{…}}, referencedStudents:[…]}`.
PeriodRegisterData parsePeriodData(Object? raw) {
  final j = _map(raw);
  final byId = _map(j['dataByTTId']);
  final periods = <int, PeriodRegister>{};
  for (final e in byId.entries) {
    final id = int.tryParse(e.key);
    if (id == null || e.value is! Map) continue;
    periods[id] = parsePeriodRegister(id, _map(e.value));
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
