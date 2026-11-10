/// Tolerant JSON -> core model mapping for the WebUntis internal API.
///
/// Every reader survives missing keys, wrong types and unknown enum values:
/// it falls back to a default instead of throwing.
library;

import '../core/absence_details.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

part 'info_parsers.dart';

// ---------------------------------------------------------------------------
// Primitive helpers
// ---------------------------------------------------------------------------

int? _intOrNull(Object? v) => switch (v) {
  int i => i,
  num n => n.toInt(),
  String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.toInt(),
  _ => null,
};

int _int(Object? v, [int fallback = 0]) => _intOrNull(v) ?? fallback;

String _str(Object? v, [String fallback = '']) => switch (v) {
  String s => s,
  num n => n.toString(),
  bool b => b.toString(),
  _ => fallback,
};

/// Non-blank trimmed string or null.
String? _nonBlank(Object? v) {
  final s = v is String ? v.trim() : (v is num ? v.toString() : null);
  return (s == null || s.isEmpty) ? null : s;
}

bool _bool(Object? v, [bool fallback = false]) => switch (v) {
  bool b => b,
  num n => n != 0,
  String s when s.toLowerCase() == 'true' => true,
  String s when s.toLowerCase() == 'false' => false,
  _ => fallback,
};

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

Iterable<Map<String, Object?>> _maps(Object? v) =>
    _list(v).whereType<Map>().map(_map);

List<int> _ints(Object? v) =>
    _list(v).map(_intOrNull).whereType<int>().toList();

// ---------------------------------------------------------------------------
// Formats
// ---------------------------------------------------------------------------

final _dateRe = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');
final _dateTimeRe = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})[T ](\d{1,2}):(\d{2})(?::(\d{2}))?',
);
final _timeRe = RegExp(r'^T?(\d{1,2}):(\d{2})');

/// "2025-09-15" (also accepts yyyyMMdd ints/strings) -> local midnight.
DateTime? parseDate(Object? v) {
  if (v is int || (v is String && RegExp(r'^\d{8}$').hasMatch(v.trim()))) {
    final n = _int(v);
    if (n < 10000101) return null;
    return DateTime(n ~/ 10000, (n ~/ 100) % 100, n % 100);
  }
  if (v is! String) return null;
  final m = _dateRe.firstMatch(v.trim());
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// "2025-09-15T08:00[:ss][Z]" -> local wall-clock DateTime (no conversion).
DateTime? parseDateTime(Object? v) {
  if (v is! String) return null;
  final m = _dateTimeRe.firstMatch(v.trim());
  if (m == null) return parseDate(v);
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    m[6] == null ? 0 : int.parse(m[6]!),
  );
}

/// "T08:00" (or "08:00", or Untis int 800) -> minutes since midnight.
int? parseTime(Object? v) {
  if (v is int) return (v ~/ 100) * 60 + v % 100;
  if (v is! String) return null;
  final m = _timeRe.firstMatch(v.trim());
  if (m == null) return null;
  return int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// "#rrggbb" -> 0xFFrrggbb. Also accepts "rrggbb" and "#aarrggbb".
int? parseColor(Object? v) {
  if (v is! String) return null;
  var s = v.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  if (s.length == 6) return 0xFF000000 | n;
  if (s.length == 8) return n;
  return null;
}

/// Formats a date as yyyy-MM-dd.
String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Master data
// ---------------------------------------------------------------------------

MasterElement? parseTeacher(Map<String, Object?> j) {
  final id = _intOrNull(j['id']);
  if (id == null) return null;
  final name = _nonBlank(j['name']);
  final first = _str(j['firstName']).trim();
  final last = _str(j['lastName']).trim();
  final full = '$first $last'.trim();
  return MasterElement(
    type: ElementType.teacher,
    id: id,
    name: name ?? _nonBlank(last) ?? '#$id',
    longName: full.isNotEmpty ? full : (name ?? '#$id'),
    foreColor: parseColor(j['foreColor']),
    backColor: parseColor(j['backColor']),
    active: _bool(j['active'], true),
    displayAllowed: _bool(j['displayAllowed'], true),
  );
}

/// Klassen, rooms and subjects.
MasterElement? parseSimpleElement(ElementType type, Map<String, Object?> j) {
  final id = _intOrNull(j['id']);
  if (id == null) return null;
  final name = _nonBlank(j['name']);
  final longName = _nonBlank(j['longName']);
  final short = name ?? longName ?? '#$id';
  return MasterElement(
    type: type,
    id: id,
    name: short,
    longName: longName ?? short,
    foreColor: parseColor(j['foreColor']),
    backColor: parseColor(j['backColor']),
    active: _bool(j['active'], true),
    displayAllowed: _bool(j['displayAllowed'], true),
  );
}

Holiday? parseHoliday(Map<String, Object?> j) {
  final start = parseDate(j['startDate']);
  final end = parseDate(j['endDate']) ?? start;
  if (start == null || end == null) return null;
  final name = _nonBlank(j['name']);
  final longName = _nonBlank(j['longName']);
  return Holiday(
    id: _int(j['id']),
    name: name ?? longName ?? '',
    longName: longName ?? name ?? '',
    start: start,
    end: end,
  );
}

SchoolYear? parseSchoolYear(Map<String, Object?> j) {
  final start = parseDate(j['startDate']);
  final end = parseDate(j['endDate']);
  if (start == null || end == null) return null;
  return SchoolYear(
    id: _int(j['id']),
    name: _str(j['name']),
    start: start,
    end: end,
  );
}

const _weekdays = {
  'MON': 1, 'TUE': 2, 'WED': 3, 'THU': 4, 'FRI': 5, 'SAT': 6, 'SUN': 7, //
};

/// Maps a time-grid day to DateTime.weekday. Accepts "MON".."SUN" (also full
/// English names) or Untis day numbers (1 = SUN, 2 = MON, ... 7 = SAT).
int? parseWeekday(Object? v) {
  if (v is String) {
    final s = v.trim().toUpperCase();
    if (s.length >= 3 && _weekdays.containsKey(s.substring(0, 3))) {
      return _weekdays[s.substring(0, 3)];
    }
    final n = int.tryParse(s);
    return n == null ? null : parseWeekday(n);
  }
  final n = _intOrNull(v);
  if (n == null || n < 1 || n > 7) return null;
  return n == 1 ? DateTime.sunday : n - 1;
}

TimeGrid? parseTimeGrid(Object? raw) {
  if (raw is! Map) return null;
  final days = <int, List<TimeUnit>>{};
  for (final d in _maps(raw['days'])) {
    final wd = parseWeekday(d['day']);
    if (wd == null) continue;
    final units = <TimeUnit>[];
    for (final u in _maps(d['units'])) {
      final s = parseTime(u['startTime']);
      final e = parseTime(u['endTime']);
      if (s == null || e == null) continue;
      units.add(
        TimeUnit(
          label: _str(u['label'], '${units.length + 1}'),
          start: s,
          end: e,
        ),
      );
    }
    units.sort((a, b) => a.start.compareTo(b.start));
    days[wd] = units;
  }
  return days.isEmpty ? null : TimeGrid(days);
}

/// Parses full or delta master data. The result is a [MasterDataWithLookups]
/// carrying `absenceReasons` / `excuseStatuses`.
MasterData parseMasterData(Object? raw) {
  final j = _map(raw);
  final elements = <MasterElement>[
    ..._maps(j['klassen'])
        .map((e) => parseSimpleElement(ElementType.klasse, e))
        .whereType<MasterElement>(),
    ..._maps(j['teachers']).map(parseTeacher).whereType<MasterElement>(),
    ..._maps(j['subjects'])
        .map((e) => parseSimpleElement(ElementType.subject, e))
        .whereType<MasterElement>(),
    ..._maps(j['rooms'])
        .map((e) => parseSimpleElement(ElementType.room, e))
        .whereType<MasterElement>(),
  ];
  return MasterDataWithLookups(
    timestamp: _int(j['timeStamp'] ?? j['timestamp']),
    elements: elements,
    holidays: _maps(j['holidays'])
        .map(parseHoliday)
        .whereType<Holiday>()
        .toList(),
    schoolYears: _maps(j['schoolyears'] ?? j['schoolYears'])
        .map(parseSchoolYear)
        .whereType<SchoolYear>()
        .toList(),
    timeGrid: parseTimeGrid(j['timeGrid']),
    lookups: parseAbsenceLookups(j),
  );
}

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

ElementRef? parseElementRef(Map<String, Object?> j) {
  final id = _intOrNull(j['id']);
  if (id == null) return null;
  final name = _nonBlank(j['name']);
  final longName = _nonBlank(j['longName']);
  final displayName = _nonBlank(j['displayName']);
  return ElementRef(
    type: ElementType.parse(j['type']),
    id: id,
    orgId: _intOrNull(j['orgId']) ?? id,
    inlineName: name ?? displayName ?? longName,
    inlineLongName: longName ?? displayName ?? name,
  );
}

Homework? parseHomework(Map<String, Object?> j) {
  final start = parseDate(j['startDate']) ?? parseDateTime(j['startDate']);
  final end = parseDate(j['endDate']) ?? start;
  if (start == null || end == null) return null;
  return Homework(
    id: _int(j['id']),
    lessonId: _int(j['lessonId']),
    startDate: start,
    endDate: end,
    text: _str(j['text']),
    remark: _str(j['remark']),
    completed: _bool(j['completed']),
  );
}

Exam? parseExam(Object? raw) {
  if (raw is! Map) return null;
  final j = _map(raw);
  return Exam(
    id: _int(j['id']),
    type: _str(j['examType'] ?? j['type']),
    name: _str(j['name']),
    text: _str(j['text']),
  );
}

Period? parsePeriod(Map<String, Object?> j) {
  final start = parseDateTime(j['startDateTime']);
  final end = parseDateTime(j['endDateTime']);
  if (start == null || end == null) return null;
  final text = _map(j['text']);
  final onlineLink = _nonBlank(j['onlinePeriodLink']);
  return Period(
    id: _int(j['id']),
    lessonId: _int(j['lessonId']),
    start: start,
    end: end,
    elements: _maps(j['elements'])
        .map(parseElementRef)
        .whereType<ElementRef>()
        .toList(),
    flags: _list(j['is']).map(PeriodFlag.parse).toSet(),
    lessonText: _str(text['lesson']),
    substitutionText: _str(text['substitution']),
    infoText: _str(text['info']),
    foreColor: parseColor(j['foreColor']) ?? parseColor(j['innerForeColor']),
    backColor: parseColor(j['backColor']) ?? parseColor(j['innerBackColor']),
    homework: _maps(j['homeWorks'])
        .map(parseHomework)
        .whereType<Homework>()
        .toList(),
    exam: parseExam(j['exam']),
    isOnline: _bool(j['isOnlinePeriod']),
    onlineLink: onlineLink,
  );
}

/// Parses a getTimetable2017 result.
TimetableResponse parseTimetableResponse(Object? raw) {
  final j = _map(raw);
  final periods =
      _maps(_map(j['timetable'])['periods'])
          .map(parsePeriod)
          .whereType<Period>()
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final md = j['masterData'];
  return TimetableResponse(periods, md is Map ? parseMasterData(md) : null);
}

// ---------------------------------------------------------------------------
// School search, login, messages
// ---------------------------------------------------------------------------

/// Extracts the host from a URL or bare host string; null when blank.
String? hostOf(Object? url) {
  final s = _nonBlank(url);
  if (s == null) return null;
  final withScheme = s.contains('://') ? s : 'https://$s';
  final host = Uri.tryParse(withScheme)?.host ?? '';
  return host.isEmpty ? null : host;
}

/// Resolves the API host: [customUrl] > mobileServiceUrl (if the platform
/// flag is set and it is non-blank) > serverUrl > server.
String resolveHost(
  Map<String, Object?> j, {
  String? customUrl,
  bool isIos = false,
}) {
  final custom = hostOf(customUrl);
  if (custom != null) return custom;
  final useMobile = _bool(
    j[isIos ? 'useMobileServiceUrlIos' : 'useMobileServiceUrlAndroid'],
  );
  if (useMobile) {
    final mobile = hostOf(j['mobileServiceUrl']);
    if (mobile != null) return mobile;
  }
  return hostOf(j['serverUrl']) ?? hostOf(j['server']) ?? '';
}

School? parseSchool(
  Map<String, Object?> j, {
  String? customUrl,
  bool isIos = false,
}) {
  final loginName = _nonBlank(j['loginName']);
  if (loginName == null) return null;
  return School(
    schoolId: _int(j['schoolId']),
    loginName: loginName,
    displayName: _nonBlank(j['displayName']) ?? loginName,
    address: _str(j['address']),
    host: resolveHost(j, customUrl: customUrl, isIos: isIos),
  );
}

List<School> parseSchools(Object? raw, {bool isIos = false}) =>
    _maps(_map(raw)['schools'])
        .map((s) => parseSchool(s, isIos: isIos))
        .whereType<School>()
        .toList();

/// Maps a getUserData2017 result into a [LoginResult].
LoginResult parseLoginResult(Object? raw, {required String secret}) {
  final j = _map(raw);
  final user = _map(j['userData']);
  return LoginResult(
    secret: secret,
    displayName: _str(user['displayName']),
    elementType: ElementType.parse(user['elemType']),
    elementId: _int(user['elemId']),
    klassenIds: _ints(user['klassenIds']),
    rights: _list(user['rights']).map(_nonBlank).whereType<String>().toSet(),
    masterData: parseMasterData(j['masterData']),
  );
}

List<Message> parseMessages(Object? raw) => [
  for (final m in _maps(_map(raw)['messages']))
    Message(
      id: _int(m['id']),
      subject: _str(m['subject']),
      bodyHtml: _str(m['body']),
      attachments: [
        for (final a in _maps(m['attachments']))
          (name: _str(a['name']), url: _str(a['url'])),
      ],
    ),
];
