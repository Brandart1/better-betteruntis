/// Parsers and payloads for excuse management (SAA, lib/core/excuses.dart).
/// Shapes from the decompiled official app; tolerant because no real
/// teacher answer has been seen yet.
library;

import '../core/absence_summary.dart';
import '../core/excuses.dart';
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
  String s => s.trim(),
  num n => n.toString(),
  _ => '',
};

bool? _bool(Object? v) => switch (v) {
  bool b => b,
  String s => s.toLowerCase() == 'true',
  _ => null,
};

/// SAA date-time: local time with a literal `Z` (`2026-11-16T08:00:00Z`),
/// read by dropping the Z.
DateTime? parseSaaDateTime(Object? v) {
  if (v is! String) return null;
  var s = v.trim();
  if (s.endsWith('Z')) s = s.substring(0, s.length - 1);
  return DateTime.tryParse(s);
}

/// `yyyy-MM-dd'T'HH:mm:00'Z'` as the official app writes it.
String formatSaaDateTime(DateTime d) => '${formatUntisDateTime(d)}:00Z';

ExcuseStatus? _status(Map<String, Object?> j) {
  final id = _int(j['id']);
  final type = ExcuseStatusType.parse(j['type']);
  if (id == null || type == null) return null;
  final name = _str(j['name']).isEmpty ? type.label : _str(j['name']);
  return ExcuseStatus(id: id, name: name, type: type);
}

ExcuseMeta parseExcuseMeta(Object? raw) {
  final j = _map(raw);
  final statuses = [for (final s in _maps(j['excuseStatuses'])) ?_status(s)];
  final def = _int(j['defaultExcuseStatusId']);
  return ExcuseMeta(
    classes: [
      for (final c in _maps(j['classes']))
        if (_int(c['id']) case final id?)
          ExcuseClass(
            id: id,
            name: _str(c['name']).isEmpty ? '#$id' : _str(c['name']),
          ),
    ],
    statuses: statuses,
    reasons: {
      for (final r in _maps(j['reasons'])) ?_int(r['id']): _str(r['name']),
    },
    defaultExcuseStatusId: statuses.any((s) => s.id == def) ? def : null,
  );
}

/// Type of a master data excuse status from its name (the JSON-RPC
/// fallback has no types): "nicht entschuldigt", "unentschuldigt",
/// "not excused" -> not excused; "offen", "open" -> open; anything else
/// with "entsch" / "excus" / "attest" -> excused; else not excused.
ExcuseStatusType guessExcuseStatusType(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'nicht|\bnot\b|unent|unexc|kein').hasMatch(n)) {
    return ExcuseStatusType.notExcused;
  }
  if (RegExp(r'offen|open|ausst|pending').hasMatch(n)) {
    return ExcuseStatusType.open;
  }
  if (RegExp(r'entsch|excus|attest|befrei').hasMatch(n)) {
    return ExcuseStatusType.excused;
  }
  return ExcuseStatusType.notExcused;
}

/// Fallback meta from master data statuses and reasons.
ExcuseMeta excuseMetaFromLookups(
  Map<int, String> statuses,
  Map<int, String> reasons,
) => ExcuseMeta(
  statuses: [
    for (final MapEntry(key: id, value: name) in statuses.entries)
      ExcuseStatus(id: id, name: name, type: guessExcuseStatusType(name)),
  ],
  reasons: reasons,
  rest: false,
);

/// One `SaaAbsenceDto`; null without id or start.
ExcuseAbsence? parseSaaAbsence(Map<String, Object?> j, ExcuseMeta meta) {
  final id = _int(j['id']);
  final duration = _map(j['duration']);
  final start = parseSaaDateTime(duration['start']);
  if (id == null || start == null) return null;
  final end = parseSaaDateTime(duration['end']) ?? start;
  final reason = _map(j['reason']);
  final student = _map(j['student']);
  final status = _status(_map(j['excuseStatus']));
  final reasonId = _int(reason['id']) ?? _int(j['reasonId']);
  return ExcuseAbsence(
    id: id,
    studentId: _int(student['id']) ?? _int(j['studentId']),
    studentName: _str(student['name']),
    start: start,
    end: end,
    reasonId: reasonId,
    reasonName: _str(reason['name']).isNotEmpty
        ? _str(reason['name'])
        : (meta.reasons[reasonId] ?? ''),
    text: _str(j['text']),
    status: status == null ? null : meta.status(status.id) ?? status,
    excuseText: _str(j['excuseText']),
    excuseStatusEditable: _bool(j['excuseStatusEditable']) ?? true,
    raw: j,
  );
}

/// `POST view/v4/classreg/absences` answer `{absences:[…]}`.
List<ExcuseAbsence> parseSaaAbsences(Object? raw, ExcuseMeta meta) => [
  for (final a in _maps(_map(raw)['absences'])) ?parseSaaAbsence(a, meta),
];

/// `POST view/v4/classreg/absences` body. [ExcuseQuery.range] goes as
/// `dateRangeType`, the days as `dateRange` too (which one the server reads
/// is not known; they agree).
Map<String, Object?> saaListPayload(ExcuseQuery q) => {
  'classId': q.classId,
  'dateRange': {
    'start': formatSaaDateTime(
      DateTime(q.start.year, q.start.month, q.start.day),
    ),
    'end': formatSaaDateTime(
      DateTime(q.end.year, q.end.month, q.end.day, 23, 59),
    ),
  },
  'dateRangeType': q.range.apiName,
  'excuseStatusType': ?q.filter.type?.apiName,
};

/// `PUT view/v3/classreg/absences` body: the listed dto copied unchanged,
/// only the excuse status and text replaced (from the official app).
Map<String, Object?> saaSavePayload(
  ExcuseAbsence a,
  ExcuseStatus status,
  String text,
) {
  final j = a.raw;
  final student = _map(j['student']);
  return {
    'saveStrategy': 'ABSENCE_WRITE',
    'itemToSave': {
      'id': a.id,
      'studentId': _int(student['id']) ?? a.studentId,
      'duration': {
        'start': formatSaaDateTime(a.start),
        'end': formatSaaDateTime(a.end),
      },
      'reasonId': a.reasonId,
      'excuseStatusId': status.id,
      'excuseText': text.trim(),
      'text': j['text'] is String ? j['text'] : '',
      'studentOfAge': j['studentOfAge'] ?? student['studentOfAge'],
      'parentAutoNotificationStatus': j['parentAutoNotificationStatus'],
      'parentManualNotificationStatus': j['parentManualNotificationStatus'],
    },
  };
}

/// Conflicts of a save answer (`{modifiedAbsences, conflicts, …}`); any
/// means nothing was saved.
int saaConflicts(Object? raw) => _maps(_map(raw)['conflicts']).length;

/// The saved absence from `modifiedAbsences`, null when not there.
ExcuseAbsence? saaModifiedAbsence(Object? raw, int id, ExcuseMeta meta) {
  for (final a in _maps(_map(raw)['modifiedAbsences'])) {
    if (_int(a['id']) == id) return parseSaaAbsence(a, meta);
  }
  return null;
}

/// submitExcuse2017 params (official app).
Map<String, Object?> submitExcuseParams(
  int absenceId,
  ExcuseStatus status,
  String text,
) => {
  'absenceId': absenceId,
  'excuseStatusId': status.id,
  'date': null,
  'text': text.trim(),
};

/// Error texts of a submitExcuse2017 answer (`{absence, errors:[…]}`).
List<String> submitExcuseErrors(Object? raw) => [
  for (final e
      in (_map(raw)['errors'] is List ? _map(raw)['errors'] as List : const []))
    if (e is Map)
      _str(e['message']).isNotEmpty
          ? _str(e['message'])
          : _str(e['title']).isNotEmpty
          ? _str(e['title'])
          : _str(e['code'])
    else if (_str(e).isNotEmpty)
      _str(e),
];

/// A class absence list record (fallback) as an [ExcuseAbsence]: the status
/// is the first of [meta] with the record's state (none for open).
ExcuseAbsence excuseAbsenceFromRecord(ClassAbsenceRecord r, ExcuseMeta meta) {
  final type = switch (r.state) {
    ExcuseState.excused => ExcuseStatusType.excused,
    ExcuseState.unexcused => ExcuseStatusType.notExcused,
    ExcuseState.open => ExcuseStatusType.open,
  };
  return ExcuseAbsence(
    id: r.id,
    studentId: r.studentId,
    studentName: r.studentName,
    start: r.start,
    end: r.end,
    reasonName: r.reason,
    text: r.text,
    status: type == ExcuseStatusType.open
        ? null
        : meta.statusesOf(type).firstOrNull,
  );
}
