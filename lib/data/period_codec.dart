/// JSON (de)serialization of [Period]s and [TimeGrid]s for the local cache.
///
/// This is our own storage format (not the Untis wire format). Decoding is
/// tolerant: missing or malformed fields fall back to defaults.
library;

import 'dart:convert';

import '../core/models.dart';

abstract final class PeriodCodec {
  static String encodeList(List<Period> periods) =>
      jsonEncode([for (final p in periods) toJson(p)]);

  static List<Period> decodeList(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map) fromJson(e.cast<String, Object?>()),
      ];
    } on FormatException {
      return const [];
    }
  }

  static Map<String, Object?> toJson(Period p) => {
    'id': p.id,
    'lessonId': p.lessonId,
    'start': p.start.toIso8601String(),
    'end': p.end.toIso8601String(),
    'elements': [
      for (final e in p.elements)
        {
          'type': e.type.apiName,
          'id': e.id,
          'orgId': e.orgId,
          if (e.inlineName != null) 'name': e.inlineName,
          if (e.inlineLongName != null) 'longName': e.inlineLongName,
        },
    ],
    'flags': [for (final f in p.flags) f.name],
    'lessonText': p.lessonText,
    'substitutionText': p.substitutionText,
    'infoText': p.infoText,
    if (p.foreColor != null) 'foreColor': p.foreColor,
    if (p.backColor != null) 'backColor': p.backColor,
    'homework': [
      for (final h in p.homework)
        {
          'id': h.id,
          'lessonId': h.lessonId,
          'startDate': h.startDate.toIso8601String(),
          'endDate': h.endDate.toIso8601String(),
          'text': h.text,
          'remark': h.remark,
          'completed': h.completed,
        },
    ],
    if (p.exam != null)
      'exam': {
        'id': p.exam!.id,
        'type': p.exam!.type,
        'name': p.exam!.name,
        'text': p.exam!.text,
      },
    'isOnline': p.isOnline,
    if (p.onlineLink != null) 'onlineLink': p.onlineLink,
  };

  static Period fromJson(Map<String, Object?> j) {
    final exam = j['exam'];
    return Period(
      id: _int(j['id']),
      lessonId: _int(j['lessonId']),
      start: _date(j['start']),
      end: _date(j['end']),
      elements: [
        for (final e in _list(j['elements']))
          if (e is Map)
            ElementRef(
              type: ElementType.parse(e['type']),
              id: _int(e['id']),
              orgId: _int(e['orgId']),
              inlineName: _strOrNull(e['name']),
              inlineLongName: _strOrNull(e['longName']),
            ),
      ],
      flags: {
        for (final f in _list(j['flags']))
          PeriodFlag.values.firstWhere(
            (v) => v.name == f,
            orElse: () => PeriodFlag.unknown,
          ),
      },
      lessonText: _str(j['lessonText']),
      substitutionText: _str(j['substitutionText']),
      infoText: _str(j['infoText']),
      foreColor: _intOrNull(j['foreColor']),
      backColor: _intOrNull(j['backColor']),
      homework: [
        for (final h in _list(j['homework']))
          if (h is Map)
            Homework(
              id: _int(h['id']),
              lessonId: _int(h['lessonId']),
              startDate: _date(h['startDate']),
              endDate: _date(h['endDate']),
              text: _str(h['text']),
              remark: _str(h['remark']),
              completed: h['completed'] == true,
            ),
      ],
      exam: exam is Map
          ? Exam(
              id: _int(exam['id']),
              type: _str(exam['type']),
              name: _str(exam['name']),
              text: _str(exam['text']),
            )
          : null,
      isOnline: j['isOnline'] == true,
      onlineLink: _strOrNull(j['onlineLink']),
    );
  }

  static String encodeTimeGrid(TimeGrid grid) => jsonEncode({
    for (final MapEntry(:key, :value) in grid.days.entries)
      '$key': [
        for (final u in value)
          {'label': u.label, 'start': u.start, 'end': u.end},
      ],
  });

  /// Returns null if [json] is unusable.
  static TimeGrid? decodeTimeGrid(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! Map) return null;
      final days = <int, List<TimeUnit>>{};
      for (final MapEntry(:key, :value) in raw.entries) {
        final day = int.tryParse('$key');
        if (day == null) continue;
        days[day] = [
          for (final u in _list(value))
            if (u is Map)
              TimeUnit(
                label: _str(u['label']),
                start: _int(u['start']),
                end: _int(u['end']),
              ),
        ];
      }
      return TimeGrid(days);
    } on FormatException {
      return null;
    }
  }

  static int _int(Object? v) => _intOrNull(v) ?? 0;
  static int? _intOrNull(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : null);
  static String _str(Object? v) => v is String ? v : '';
  static String? _strOrNull(Object? v) => v is String ? v : null;
  static List<Object?> _list(Object? v) => v is List ? v : const [];
  static DateTime _date(Object? v) =>
      (v is String ? DateTime.tryParse(v) : null) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
