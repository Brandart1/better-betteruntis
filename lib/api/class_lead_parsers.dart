/// Parser and params of getClassregData2017 (class teacher dashboard,
/// lib/core/class_lead.dart). Shapes from the decompiled official app
/// (`GetClassregDataRequest/Response`, `UMStudentAbsence`, `UMExcuse`,
/// `UMClassRegEvent`, `UMStudent`); no real answer seen yet.
library;

import '../core/class_lead.dart';
import '../core/class_register.dart';
import '../core/excuses.dart';
import '../core/models.dart';
import 'class_register_parsers.dart';
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

/// getClassregData2017 params (besides `auth`): days as `yyyy-MM-dd`.
Map<String, Object?> classregDataParams(
  int klasseId,
  DateTime start,
  DateTime end,
) => {
  'klasseId': klasseId,
  'startDate': formatDate(start),
  'endDate': formatDate(end),
};

/// The excuse status of an absence: `excuse.excuseStatusId` from [meta];
/// else the first status of the kind `excused` says when there is an
/// excuse; else none (open).
ExcuseStatus? _excuseStatus(Map<String, Object?> j, ExcuseMeta meta) {
  final excuse = _map(j['excuse']);
  final id = _int(excuse['excuseStatusId'] ?? j['excuseStatusId']);
  final known = meta.status(id);
  if (known != null) return known;
  if (j['excused'] == true) {
    return meta.statusesOf(ExcuseStatusType.excused).firstOrNull;
  }
  if (id != null && id > 0) {
    return meta.statusesOf(ExcuseStatusType.notExcused).firstOrNull;
  }
  return null;
}

/// One `UMStudentAbsence`; null without id or start.
ExcuseAbsence? parseClassLeadAbsence(
  Map<String, Object?> j,
  ExcuseMeta meta,
  Map<int, String> students,
) {
  final id = _int(j['id']);
  final start = parseDateTime(j['startDateTime']);
  if (id == null || start == null) return null;
  final studentId = _int(j['studentId']);
  final reasonId = _int(j['absenceReasonId']);
  final reason = _str(j['absenceReason']);
  return ExcuseAbsence(
    id: id,
    studentId: studentId != null && studentId > 0 ? studentId : null,
    studentName: students[studentId] ?? '',
    start: start,
    end: parseDateTime(j['endDateTime']) ?? start,
    reasonId: reasonId,
    reasonName: reason.isNotEmpty ? reason : (meta.reasons[reasonId] ?? ''),
    text: _str(j['text']),
    status: _excuseStatus(j, meta),
    excuseText: _str(_map(j['excuse'])['text']),
  );
}

/// One `UMClassRegEvent` (`elementType` STUDENT: about the pupil
/// `elementId`; CLASS: the whole class); null when it says nothing.
ClassRegEvent? parseClassLeadEvent(
  Map<String, Object?> j,
  Map<int, String> students,
  Map<int, String> reasons,
) {
  if (j['delete'] == true) return null;
  final type = ElementType.parse(j['elementType']);
  final elementId = _int(j['elementId']);
  final studentId = type == ElementType.student && (elementId ?? 0) > 0
      ? elementId
      : null;
  final reasonId = _int(j['eventReasonId']);
  final text = _str(j['text']);
  if (text.isEmpty && reasonId == null) return null;
  return ClassRegEvent(
    id: _int(j['id']),
    studentId: studentId,
    studentName: students[studentId] ?? '',
    reasonId: reasonId,
    reasonName: reasons[reasonId] ?? '',
    text: text,
    date: parseDateTime(j['dateTime']),
  );
}

/// getClassregData2017 answer `{absences, classRegEvents,
/// referencedStudents}`; [reasons] names the entry reasons.
ClassLeadData parseClassLeadData(
  Object? raw,
  ExcuseMeta meta, {
  Map<int, String> reasons = const {},
}) {
  final j = _map(raw);
  final students = <int, String>{
    for (final s in _maps(j['referencedStudents']))
      if (parseClassRegStudent(s) case final p?) p.id: p.displayName,
  };
  return ClassLeadData(
    absences: [
      for (final a in _maps(j['absences']))
        ?parseClassLeadAbsence(a, meta, students),
    ],
    events: [
      for (final e in _maps(j['classRegEvents']))
        ?parseClassLeadEvent(e, students, reasons),
    ],
    students: students,
  );
}
