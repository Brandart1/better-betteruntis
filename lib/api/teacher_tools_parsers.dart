/// Parsers and payloads for room changes and exam creation (teachers).
///
/// The room calls come from the official Untis Mobile app's API classes
/// (GetRoomChangeDataResponse `{availableRoomIds, errors}`,
/// GetAvailableRoomsResponse `{roomIds}`, SubmitRoomChangeResponse
/// `{errors, periods}`, UMError `{code, title, details}`); no real answer
/// has been seen yet, so everything is parsed tolerantly. The exam call is a
/// guess (docs/API.md "Room booking and exams (teachers)").
library;

import '../core/teacher_tools.dart';
import 'parsers.dart';

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

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

String _firstStr(Map<String, Object?> j, List<String> keys) {
  for (final k in keys) {
    final s = _str(j[k]).trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// Ids from a list of ids or of `{id}` objects; positive, unique, in order.
List<int> _ids(Object? v) {
  final out = <int>[];
  for (final e in v is List ? v : const []) {
    final id = e is Map ? _int(_map(e)['id'] ?? _map(e)['roomId']) : _int(e);
    if (id != null && id > 0 && !out.contains(id)) out.add(id);
  }
  return out;
}

/// `errors` list (UMError items, plain strings or `{message}`).
List<TeacherToolError> parseTeacherToolErrors(Object? v) {
  final out = <TeacherToolError>[];
  for (final e in v is List ? v : const []) {
    if (e is String && e.trim().isNotEmpty) {
      out.add(TeacherToolError(title: e.trim()));
    } else if (e is Map) {
      final j = _map(e);
      final err = TeacherToolError(
        code: _firstStr(j, ['code', 'errorCode', 'category']),
        title: _firstStr(j, ['title', 'message', 'msg']),
        details: _firstStr(j, ['details', 'detail', 'description']),
      );
      if (err.code.isNotEmpty ||
          err.title.isNotEmpty ||
          err.details.isNotEmpty) {
        out.add(err);
      }
    }
  }
  return out;
}

/// getRoomChangeData2017 / getAvailableRooms2017 answer. Accepts
/// `availableRoomIds`, `roomIds`, `rooms`, `availableRooms` or a bare list.
FreeRooms parseFreeRooms(Object? raw) {
  if (raw is List) return FreeRooms(roomIds: _ids(raw));
  final j = _map(raw);
  final nested = _map(j['roomChangeData']);
  final src = nested.isNotEmpty ? nested : j;
  for (final k in ['availableRoomIds', 'roomIds', 'availableRooms', 'rooms']) {
    if (src[k] is List) {
      return FreeRooms(
        roomIds: _ids(src[k]),
        errors: parseTeacherToolErrors(src['errors'] ?? j['errors']),
      );
    }
  }
  return FreeRooms(
    errors: parseTeacherToolErrors(src['errors'] ?? j['errors']),
  );
}

/// submitRoomChange2017 answer `{errors, periods}`.
RoomChangeResult parseRoomChangeResult(Object? raw) {
  final j = _map(raw);
  final periods = j['periods'];
  return RoomChangeResult(
    errors: parseTeacherToolErrors(j['errors']),
    periodCount: periods is List ? periods.length : 0,
  );
}

/// Master data `examTypes` (also accepted: `examtypes`, a bare list).
List<ExamType> parseExamTypes(Object? masterData) {
  final j = _map(masterData);
  final list = masterData is List
      ? masterData
      : (j['examTypes'] ?? j['examtypes'] ?? j['examType']);
  final out = <ExamType>[];
  final seen = <int>{};
  for (final e in list is List ? list : const []) {
    final m = _map(e);
    final id = _int(m['id']);
    final name = _firstStr(m, ['name', 'shortName', 'longName']);
    if (id == null || name.isEmpty || !seen.add(id)) continue;
    if (m['active'] == false) continue;
    out.add(ExamType(id: id, name: name, longName: _firstStr(m, ['longName'])));
  }
  return out;
}

/// Local date-time as the 2017 methods use it: `2026-11-16T08:00`.
String formatUntisDateTime(DateTime d) =>
    '${formatDate(d)}T${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// getAvailableRooms2017's date-time, as the official app formats it
/// (`yyyy-MM-dd'T'HH:mm'Z'`: local time with a literal `Z`):
/// `2026-11-16T08:00Z`.
String formatAvailableRoomsDateTime(DateTime d) => '${formatUntisDateTime(d)}Z';

/// Local date-time with seconds, as the REST calendar API takes it:
/// `2026-11-16T08:00:00`.
String formatRestDateTime(DateTime d) => '${formatUntisDateTime(d)}:00';

/// Bodies of the room booking without a lesson (**guessed**), per URL of
/// `UntisApiImpl.roomBookingUrls`: first the REST calendar API's entry
/// shape (the official app's calendar-entry updates send
/// `{rooms:{value:[ids]}, teachers:[{value:id}], notesAll:{value:text}}`,
/// its room form takes `startDateTime` / `endDateTime`), then a classic-web
/// shape.
Map<String, Object?> roomBookingCalendarPayload(RoomBookingRequest b) => {
  'startDateTime': formatRestDateTime(b.start),
  'endDateTime': formatRestDateTime(b.end),
  'rooms': {
    'value': [b.roomId],
  },
  if (b.teacherId != null)
    'teachers': [
      {'value': b.teacherId},
    ],
  if (b.text.trim().isNotEmpty) 'notesAll': {'value': b.text.trim()},
};

Map<String, Object?> roomBookingClassicPayload(RoomBookingRequest b) => {
  'roomId': b.roomId,
  'roomIds': [b.roomId],
  'date': _yyyymmdd(b.start),
  'startTime': _hhmm(b.start),
  'endTime': _hhmm(b.end),
  'startDateTime': formatUntisDateTime(b.start),
  'endDateTime': formatUntisDateTime(b.end),
  'teacherId': ?b.teacherId,
  if (b.text.trim().isNotEmpty) 'text': b.text.trim(),
};

/// Answer of a room booking: the id (`{id}`, `{data:{id}}`, `{booking:{id}}`)
/// and error lists / `success:false` like the exam answer.
RoomBookingResult parseRoomBookingResult(Object? raw) {
  final j = _map(raw);
  final id = parseCreatedExamId(raw) ?? _int(_map(j['booking'])['id']);
  return RoomBookingResult(
    errors: [
      ...parseExamErrors(raw),
      ...parseTeacherToolErrors(j['validationErrors']),
    ],
    id: id != null && id > 0 ? id : null,
  );
}

int _yyyymmdd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
int _hhmm(DateTime d) => d.hour * 100 + d.minute;

/// Body of the exam creation request (assumed). Mirrors what
/// `GET /WebUntis/api/exams` returns per exam (`examType`, `name`,
/// `examDate` yyyymmdd, `startTime`/`endTime` hhmm, `text`), plus the ids of
/// the elements the web client works with. Keys without a value are left
/// out.
Map<String, Object?> examPayload(NewExam e) => {
  'examTypeId': ?e.examTypeId,
  if (e.examType.trim().isNotEmpty) 'examType': e.examType.trim(),
  'name': e.name.trim(),
  'text': e.text.trim(),
  'examDate': _yyyymmdd(e.start),
  'startDate': _yyyymmdd(e.start),
  'endDate': _yyyymmdd(e.end),
  'startTime': _hhmm(e.start),
  'endTime': _hhmm(e.end),
  'startDateTime': formatUntisDateTime(e.start),
  'endDateTime': formatUntisDateTime(e.end),
  'subjectId': ?e.subjectId,
  'lessonId': ?e.lessonId,
  'klasseIds': e.klasseIds,
  'studentIds': e.studentIds,
  'roomIds': e.roomIds,
  'teacherIds': e.teacherIds,
  if (e.periodIds.isNotEmpty) 'periodIds': e.periodIds,
};

/// The new exam's id from the answer (`{data:{id}}`, `{id}`, `{exam:{id}}`,
/// `{data:{exam:{id}}}`), else null.
int? parseCreatedExamId(Object? raw) {
  final j = _map(raw);
  final data = _map(j['data']);
  for (final m in [data, j, _map(data['exam']), _map(j['exam'])]) {
    final id = _int(m['id'] ?? m['examId']);
    if (id != null && id > 0) return id;
  }
  return null;
}

/// Error messages a 2xx exam answer may still carry
/// (`{errors:[…]}`, `{data:{errors:[…]}}`, `{data:{success:false, message}}`).
List<TeacherToolError> parseExamErrors(Object? raw) {
  final j = _map(raw);
  final data = _map(j['data']);
  final errors = [
    ...parseTeacherToolErrors(j['errors']),
    ...parseTeacherToolErrors(data['errors']),
  ];
  if (errors.isEmpty && (data['success'] == false || j['success'] == false)) {
    errors.add(
      TeacherToolError(
        title: _firstStr(data.isNotEmpty ? data : j, ['message', 'error']),
        code: 'success:false',
      ),
    );
  }
  return errors;
}
