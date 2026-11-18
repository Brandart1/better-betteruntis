/// Parsers and payloads for substitution planning
/// (lib/core/substitution_planning.dart). Shapes from the decompiled
/// official app (Kotlin DTOs, keys = field names); tolerant because no real
/// answer has been seen yet.
library;

import '../core/substitution_planning.dart';
import 'teacher_tools_parsers.dart';

/// Production host of the Substitution Planning service.
const substitutionHost = 'substitution.webuntis.com';

/// `X-TenantID` of the substitution service: the school login, URL-encoded
/// like Java's `URLEncoder.encode` (space -> `+`).
String substitutionTenantId(String school) => Uri.encodeQueryComponent(school);

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

/// The display name of a ref dto (`{displayName}`), or of the ref inside a
/// period entry (`{klasse:{displayName}}`, `{currentRoom:{displayName}}`).
String _name(Object? v) {
  final j = _map(v);
  for (final k in const ['displayName', 'name', 'shortName']) {
    final s = _str(j[k]);
    if (s.isNotEmpty) return s;
  }
  for (final k in const ['klasse', 'currentRoom', 'room', 'teacher']) {
    if (j[k] is Map) {
      final s = _name(j[k]);
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

List<String> _names(Object? v) => [
  for (final e in _maps(v))
    if (_name(e) case final n when n.isNotEmpty) n,
];

/// Date-times of the substitution service and the teacher absence form.
/// Guess: like the rest of WebUntis, local time, a trailing `Z` is
/// dropped; an explicit offset (`+01:00`) is converted to local time.
DateTime? parseSpDateTime(Object? v) {
  if (v is! String) return null;
  var s = v.trim();
  if (s.isEmpty) return null;
  if (s.endsWith('Z') || s.endsWith('z')) s = s.substring(0, s.length - 1);
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return d.isUtc ? d.toLocal() : d;
}

/// One `SubstitutionRequestDto`; null without an id or times.
SubstitutionRequest? parseSubstitutionRequest(Object? raw) {
  final j = _map(raw);
  final period = _map(j['period']);
  final conflict = _map(j['periodConflict']);
  final periodId = _int(period['wuId']);
  final id = _int(conflict['id']) ?? periodId;
  final start =
      parseSpDateTime(conflict['startDateTime']) ??
      parseSpDateTime(period['startDateTime']);
  final end =
      parseSpDateTime(conflict['endDateTime']) ??
      parseSpDateTime(period['endDateTime']);
  if (id == null || start == null || end == null) return null;
  var absent = _name(conflict['originalTeacher']);
  if (absent.isEmpty) {
    for (final t in _maps(period['teachers'])) {
      absent = _name(t['removedTeacher']);
      if (absent.isNotEmpty) break;
    }
  }
  final classes = _names(conflict['klassen']);
  final rooms = _names(conflict['rooms']);
  final subject = _name(conflict['subject']);
  return SubstitutionRequest(
    id: id,
    periodId: periodId,
    start: start,
    end: end,
    unitOfDay: _int(conflict['unitOfDay']) ?? _int(period['unitOfDay']),
    subject: subject.isNotEmpty ? subject : _name(period['subject']),
    classes: classes.isNotEmpty ? classes : _names(period['klassen']),
    rooms: rooms.isNotEmpty ? rooms : _names(period['rooms']),
    absentTeacher: absent,
    state: SubstitutionRequestState.parse(j['state']),
  );
}

/// `AskTeacherViewDto` -> its requests (broken entries are skipped).
List<SubstitutionRequest> parseSubstitutionRequests(Object? raw) => [
  for (final r in _maps(_map(raw)['substitutionRequests']))
    ?parseSubstitutionRequest(r),
];

/// A `PeriodDto` of an absence group.
AbsenceLesson? _absenceLesson(Map<String, Object?> p) {
  final start = parseSpDateTime(p['startDateTime']);
  final end = parseSpDateTime(p['endDateTime']);
  if (start == null || end == null) return null;
  var substitute = '';
  var state = '';
  for (final t in _maps(p['teachers'])) {
    // The own entry: removed (absent) teacher, maybe a current substitute.
    if (t['removedTeacher'] is! Map) continue;
    substitute = _name(t['currentTeacher']);
    state = _str(t['conflictState']);
    break;
  }
  return AbsenceLesson(
    start: start,
    end: end,
    subject: _name(p['subject']),
    classes: _names(p['klassen']),
    substitute: substitute,
    cancelled: p['isCanceled'] == true || p['canceled'] == true,
    state: state,
  );
}

/// `PeriodGroupCollectionDto` -> the groups that are absences (overbooking
/// and unavailable rooms are left out).
List<TeacherAbsence> parseTeacherAbsences(Object? raw) {
  final out = <TeacherAbsence>[];
  for (final g in _maps(_map(raw)['groups'])) {
    final a = _map(_map(g['group'])['absence']);
    final start = parseSpDateTime(a['startDateTime']);
    final end = parseSpDateTime(a['endDateTime']);
    if (start == null || end == null) continue;
    final lessons = [for (final p in _maps(g['periods'])) ?_absenceLesson(p)]
      ..sort((x, y) => x.start.compareTo(y.start));
    out.add(
      TeacherAbsence(
        id: _int(a['wuAbsenceId']) ?? _int(a['id']) ?? 0,
        start: start,
        end: end,
        reason: _name(a['reason']),
        note: _str(a['note']),
        missedPeriods: _int(a['missedPeriods']),
        lessons: lessons,
      ),
    );
  }
  return out;
}

/// `TeacherAbsenceViewDto`.
TeacherAbsenceForm parseTeacherAbsenceForm(Object? raw) {
  final j = _map(raw);
  return TeacherAbsenceForm(
    reasons: [
      for (final r in _maps(j['reasons']))
        if (_int(r['id']) case final id?)
          TeacherAbsenceReason(
            id: id,
            name: _name(r).isEmpty ? '#$id' : _name(r),
          ),
    ],
    start: parseSpDateTime(j['startDateTime']),
    end: parseSpDateTime(j['endDateTime']),
  );
}

/// Body of `POST view/v1/teacher-absences` as the official app sends it:
/// id 0 (new), local times `yyyy-MM-dd'T'HH:mm:00` without a Z, the note
/// (empty string when none); no reason id when none was picked.
Map<String, Object?> teacherAbsencePayload(TeacherAbsenceDraft d) => {
  'id': 0,
  'teacherId': d.teacherId,
  'startDateTime': formatRestDateTime(d.start),
  'endDateTime': formatRestDateTime(d.end),
  'reasonId': ?d.reasonId,
  'note': d.note.trim(),
};

/// The id of the created absence in the answer, when sent.
int? createdTeacherAbsenceId(Object? raw) {
  final id = _int(_map(raw)['id']);
  return id == null || id <= 0 ? null : id;
}

/// `GET view/v2/home` (`HomeTabDto`): `sections[].cells[].type`, the type
/// being the upper snake key of `HomeTabCellType` (`TEACHER_ABSENCES`,
/// `SUBSTITUTION_REQUESTS`, ...). The server decides by these cells whether
/// the teacher sees "My absences" / "Substitution requests".
SubstitutionAvailability parseHomeAvailability(Object? raw) {
  final types = {
    for (final s in _maps(_map(raw)['sections']))
      for (final c in _maps(s['cells'])) '${c['type']}'.trim().toUpperCase(),
  };
  return SubstitutionAvailability(
    teacherAbsences: types.contains('TEACHER_ABSENCES'),
    substitutionRequests: types.contains('SUBSTITUTION_REQUESTS'),
  );
}
