// Tolerant parsers for the info center: homework, exams, absences, office
// hours and the REST inbox. Same rules as the rest of parsers.dart: missing or
// wrong-typed fields fall back to defaults, an unparseable item is skipped,
// never the whole list.
part of 'parsers.dart';

/// First non-blank string among [keys] of [j].
String? _firstStr(Map<String, Object?> j, List<String> keys) {
  for (final k in keys) {
    final s = _nonBlank(j[k]);
    if (s != null) return s;
  }
  return null;
}

/// `{name, url|src|downloadUrl|href}` lists; entries without any url or name
/// are dropped.
List<({String name, String url})> parseAttachments(Object? raw) => [
  for (final a in _maps(raw))
    if (_firstStr(a, const ['url', 'src', 'downloadUrl', 'href', 'link'])
        case final url?)
      (name: _firstStr(a, const ['name', 'fileName', 'title']) ?? url, url: url)
    else if (_firstStr(a, const ['name', 'fileName']) case final name?)
      (name: name, url: ''),
];

/// Ids > 0 only (0 means "none" in Untis).
int? _id(Object? v) {
  final i = _intOrNull(v);
  return (i == null || i <= 0) ? null : i;
}

/// Date + time from either `xDateTime` or the older `xDate` (yyyyMMdd) plus
/// `xTime` (hhmm or "T08:00").
DateTime? _dateTimeOf(Map<String, Object?> j, String prefix) {
  final dt = parseDateTime(j['${prefix}DateTime']);
  if (dt != null) return dt;
  final d = parseDate(j['${prefix}Date']) ?? parseDateTime(j['${prefix}Date']);
  if (d == null) return null;
  final t = parseTime(j['${prefix}Time']);
  return t == null ? d : DateTime(d.year, d.month, d.day, t ~/ 60, t % 60);
}

// ---------------------------------------------------------------------------
// Homework (getHomeWork2017)
// ---------------------------------------------------------------------------

/// Joins `homeWorks` with `lessonsById` (a map keyed by id strings; a list of
/// lessons is accepted too). Sorted by due date.
List<HomeworkItem> parseHomeworkItems(Object? raw) {
  final j = _map(raw);
  final lessons = <int, Map<String, Object?>>{};
  final byId = j['lessonsById'] ?? j['lessons'];
  if (byId is Map) {
    for (final e in byId.entries) {
      final l = _map(e.value);
      final id = _intOrNull(l['id']) ?? _intOrNull('${e.key}');
      if (id != null) lessons[id] = l;
    }
  } else {
    for (final l in _maps(byId)) {
      final id = _intOrNull(l['id']);
      if (id != null) lessons[id] = l;
    }
  }

  final items = <HomeworkItem>[];
  for (final h in _maps(j['homeWorks'] ?? j['homeworks'])) {
    final assigned = parseDate(h['startDate']) ?? parseDateTime(h['startDate']);
    final due = parseDate(h['endDate']) ?? parseDateTime(h['endDate']);
    if (assigned == null && due == null) continue;
    final lessonId = _int(h['lessonId']);
    final lesson = lessons[lessonId] ?? const <String, Object?>{};
    items.add(
      HomeworkItem(
        id: _int(h['id']),
        lessonId: lessonId,
        assignedOn: assigned ?? due!,
        dueOn: due ?? assigned!,
        text: _str(h['text']),
        remark: _str(h['remark']),
        completed: _bool(h['completed']),
        subjectId: _id(lesson['subjectId']) ?? _id(h['subjectId']),
        teacherIds: _ints(lesson['teacherIds'] ?? h['teacherIds']),
        klassenIds: _ints(
          lesson['klassenIds'] ?? lesson['klasseIds'] ?? h['klassenIds'],
        ),
        attachments: parseAttachments(h['attachments']),
      ),
    );
  }
  items.sort((a, b) => a.dueOn.compareTo(b.dueOn));
  return items;
}

// ---------------------------------------------------------------------------
// Exams (getExams2017)
// ---------------------------------------------------------------------------

List<ExamItem> parseExamItems(Object? raw) {
  final items = <ExamItem>[];
  for (final e in _maps(_map(raw)['exams'])) {
    final start = _dateTimeOf(e, 'start') ?? parseDate(e['examDate']);
    if (start == null) continue;
    final end = _dateTimeOf(e, 'end') ?? start;
    items.add(
      ExamItem(
        id: _int(e['id']),
        start: start,
        end: end.isBefore(start) ? start : end,
        examType: _str(e['examType'] ?? e['type']).trim(),
        name: _str(e['name']).trim(),
        text: _str(e['text']).trim(),
        subjectId: _id(e['subjectId']),
        klassenIds: _ints(e['klasseIds'] ?? e['klassenIds']),
        roomIds: _ints(e['roomIds']),
        teacherIds: _ints(e['teacherIds']),
      ),
    );
  }
  items.sort((a, b) => a.start.compareTo(b.start));
  return items;
}

// ---------------------------------------------------------------------------
// Absences (getStudentAbsences2017) + master-data lookups
// ---------------------------------------------------------------------------

/// `absenceReasons` / `excuseStatuses` of a master-data object. All entries
/// are kept, active or not.
AbsenceLookups parseAbsenceLookups(Object? masterData) {
  final j = _map(masterData);
  Map<int, String> names(Object? list) {
    final out = <int, String>{};
    for (final e in _maps(list)) {
      final id = _intOrNull(e['id']);
      final n = _firstStr(e, const ['longName', 'name']);
      if (id != null && n != null) out[id] = n;
    }
    return out;
  }

  return AbsenceLookups(
    reasons: names(j['absenceReasons']),
    statuses: names(j['excuseStatuses']),
  );
}

/// Absences with their reason/status ids, newest first.
List<RawAbsence> parseRawAbsences(Object? raw) {
  final items = <RawAbsence>[];
  for (final a in _maps(_map(raw)['absences'])) {
    final start = _dateTimeOf(a, 'start');
    if (start == null) continue;
    final end = _dateTimeOf(a, 'end') ?? start;
    final excuse = _map(a['excuse']);
    final inlineStatus = a['excuseStatus'] is String
        ? _nonBlank(a['excuseStatus'])
        : null;
    items.add(
      RawAbsence(
        id: _int(a['id']),
        start: start,
        end: end.isBefore(start) ? start : end,
        excused: _bool(a['excused'] ?? a['isExcused']),
        reasonId: _intOrNull(a['absenceReasonId']),
        inlineReason: a['absenceReason'] is String
            ? (_nonBlank(a['absenceReason']) ?? '')
            : '',
        text: _str(a['text']).trim(),
        excuseStatusId: _intOrNull(
          excuse['excuseStatusId'] ?? a['excuseStatusId'],
        ),
        inlineExcuseStatus:
            inlineStatus ??
            (excuse['excuseStatus'] is String
                ? (_nonBlank(excuse['excuseStatus']) ?? '')
                : ''),
      ),
    );
  }
  items.sort((a, b) => b.start.compareTo(a.start));
  return items;
}

// ---------------------------------------------------------------------------
// Office hours (getOfficeHours2017)
// ---------------------------------------------------------------------------

/// Office hours. Nothing here is confirmed by a real response yet (see
/// docs/API.md), so this accepts the plausible variants:
/// * a top-level list, or a list under `officeHours`/`officeHourList`/`items`;
/// * start/end as `startDateTime`/`endDateTime` (ISO string or epoch ms), or
///   `date`/`startDate` (yyyyMMdd int or ISO string) plus `startTime`/
///   `endTime` (hhmm int, "1345", "13:45" or "T13:45");
/// * the teacher as `displayNameTeacher`/`teacherName`/`teacher` (string or
///   `{displayName|longName|name}`);
/// * rooms as `displayNameRooms`/`rooms`/`roomName` (string, list of strings
///   or list of `{displayName|name}`).
List<OfficeHourItem> parseOfficeHourItems(Object? raw) {
  final m = _map(raw);
  final list = raw is List
      ? raw
      : (m['officeHours'] ?? m['officeHourList'] ?? m['items']);
  final items = <OfficeHourItem>[];
  for (final o in _maps(list)) {
    final day =
        _ohDate(o['date']) ?? _ohDate(o['startDate']) ?? _ohDate(o['day']);
    final start = _ohDateTime(o['startDateTime']) ??
        _ohDateTime(o['start']) ??
        _ohDateTime(o['startDate']) ??
        _ohAt(day, o['startTime']) ??
        day;
    if (start == null) continue;
    final endDay = _ohDate(o['endDate']) ??
        day ??
        DateTime(start.year, start.month, start.day);
    final end = _ohDateTime(o['endDateTime']) ??
        _ohDateTime(o['end']) ??
        _ohDateTime(o['endDate']) ??
        _ohAt(endDay, o['endTime']) ??
        start;
    items.add(
      OfficeHourItem(
        id: _int(o['id']),
        start: start,
        end: end.isBefore(start) ? start : end,
        teacherName: _ohName(o, const [
              'displayNameTeacher',
              'teacherName',
              'teacher',
              'teacherLongName',
            ]) ??
            '',
        rooms: _ohName(o, const [
              'displayNameRooms',
              'rooms',
              'roomName',
              'room',
              'displayNameRoom',
            ]) ??
            '',
        email: _str(o['email']).trim(),
        phone: _str(o['phone']).trim(),
        registrationPossible: _bool(o['registrationPossible']),
        registered: _bool(o['registered']),
      ),
    );
  }
  items.sort((a, b) => a.start.compareTo(b.start));
  return items;
}

/// yyyyMMdd (int or string) or an ISO date/date-time -> local midnight.
DateTime? _ohDate(Object? v) {
  final d = parseDate(v) ?? parseDateTime(v);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// ISO date-time string or epoch milliseconds. A bare date doesn't count.
DateTime? _ohDateTime(Object? v) {
  if (v is int && v > 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
  if (v is String && v.contains(RegExp(r'[T ]\d{1,2}:\d{2}'))) {
    return parseDateTime(v);
  }
  return null;
}

/// [day] at a time given as hhmm int, "1345", "13:45" or "T13:45".
DateTime? _ohAt(DateTime? day, Object? time) {
  if (day == null || time == null) return null;
  final digits = time is String ? RegExp(r'^\d{3,4}$').firstMatch(time.trim()) : null;
  final t = digits != null ? parseTime(int.parse(digits[0]!)) : parseTime(time);
  if (t == null || t < 0 || t >= 24 * 60) return null;
  return DateTime(day.year, day.month, day.day, t ~/ 60, t % 60);
}

/// A name from a string, a `{displayName|longName|name}` map, or a list of
/// either (joined with ", "). First of [keys] that yields one wins.
String? _ohName(Map<String, Object?> o, List<String> keys) {
  String? one(Object? v) {
    if (v is Map) {
      final m = _map(v);
      final full = '${_str(m['firstName']).trim()} ${_str(m['lastName']).trim()}'
          .trim();
      return _firstStr(m, const ['displayName', 'longName', 'name']) ??
          (full.isEmpty ? null : full);
    }
    return v is num ? null : _nonBlank(v);
  }

  for (final k in keys) {
    final v = o[k];
    final s = v is List
        ? v.map(one).whereType<String>().join(', ')
        : one(v);
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}
// ---------------------------------------------------------------------------
// REST inbox (/api/rest/view/v1/messages)
// ---------------------------------------------------------------------------

/// ISO-8601 from the REST API. With a zone (`Z`/offset) it is converted to
/// local time; without one it is taken as local wall clock.
DateTime? parseRestDateTime(Object? v) {
  if (v is int && v > 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
  if (v is! String) return null;
  final s = v.trim();
  final hasZone =
      RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s) && s.contains('T');
  if (hasZone) return DateTime.tryParse(s)?.toLocal() ?? parseDateTime(s);
  return parseDateTime(s);
}

String _sender(Map<String, Object?> m) {
  final s = m['sender'];
  if (s is String) return s.trim();
  final sm = _map(s);
  return _firstStr(sm, const ['displayName', 'name', 'fullName']) ??
      _firstStr(m, const ['senderName', 'senderDisplayName']) ??
      '';
}

InboxMessage? _inboxMessage(Map<String, Object?> m) {
  final id = _intOrNull(m['id']);
  if (id == null) return null;
  return InboxMessage(
    id: id,
    subject: _str(m['subject']).trim(),
    preview: _firstStr(m, const ['contentPreview', 'preview', 'content']) ?? '',
    sender: _sender(m),
    sentAt: parseRestDateTime(m['sentDateTime'] ?? m['sentAt'] ?? m['sent']),
    isRead: _bool(m['isMessageRead'] ?? m['isRead'] ?? m['read']),
    hasAttachments:
        _bool(m['hasAttachments']) || _list(m['attachments']).isNotEmpty,
  );
}

/// Merges `incomingMessages` and `readConfirmationMessages` (and a plain
/// `messages` list, or a top-level list), de-duplicated by id, newest first.
List<InboxMessage> parseInbox(Object? raw) {
  final j = _map(raw);
  final lists = raw is List
      ? [raw]
      : [j['incomingMessages'], j['readConfirmationMessages'], j['messages']];
  final byId = <int, InboxMessage>{};
  for (final l in lists) {
    for (final m in _maps(l)) {
      final msg = _inboxMessage(m);
      if (msg != null) byId.putIfAbsent(msg.id, () => msg);
    }
  }
  final out = byId.values.toList()
    ..sort((a, b) {
      final x = a.sentAt, y = b.sentAt;
      if (x == null || y == null) {
        return x == null ? (y == null ? 0 : 1) : -1;
      }
      return y.compareTo(x);
    });
  return out;
}

/// `/messages/{id}`. [fallbackId] is used when the body has no id.
InboxMessageDetail parseInboxMessageDetail(Object? raw, int fallbackId) {
  final j = _map(raw);
  return InboxMessageDetail(
    id: _intOrNull(j['id']) ?? fallbackId,
    subject: _str(j['subject']).trim(),
    bodyHtml:
        _firstStr(j, const ['content', 'body', 'contentHtml', 'text']) ?? '',
    sender: _sender(j),
    sentAt: parseRestDateTime(j['sentDateTime'] ?? j['sentAt'] ?? j['sent']),
    attachments: parseAttachments(j['attachments'] ?? j['storageAttachments']),
  );
}

/// `{"errorCode":"FORBIDDEN","errorMessage":"..."}` -> human message, or null.
String? parseRestErrorMessage(Object? raw) {
  final j = _map(raw);
  final msg = _nonBlank(j['errorMessage']) ?? _nonBlank(j['message']);
  final code = _nonBlank(j['errorCode']);
  if (msg != null) return msg;
  final validation = _list(j['validationErrors'])
      .map(
        (v) => v is Map
            ? _nonBlank(v['errorMessage']) ?? _nonBlank(v['message'])
            : _nonBlank(v),
      )
      .whereType<String>()
      .join('; ');
  if (code != null) return validation.isEmpty ? code : '$code: $validation';
  return validation.isEmpty ? null : validation;
}
