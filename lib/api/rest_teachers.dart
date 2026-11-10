/// Fills in teachers from the REST timetable (`/api/rest/view/v1/timetable/
/// entries`) for schools whose JSON-RPC timetable omits TEACHER elements for
/// students. The REST response carries names (no ids), so teachers are added as
/// [ElementRef]s with synthetic negative ids and inline names; the name
/// resolver falls back to inline names for ids not in master data.
library;

import '../core/models.dart';
import 'parsers.dart' show parseDateTime;

/// One REST element as found in `positionN[].current` / `.removed`.
typedef RestName = ({String shortName, String longName});

class RestTeacherSlot {
  const RestTeacherSlot({this.current, this.removed});
  final RestName? current;
  final RestName? removed;
}

class RestEntry {
  const RestEntry({
    required this.ids,
    required this.start,
    required this.end,
    required this.teachers,
  });
  final List<int> ids;
  final DateTime start;
  final DateTime end;
  final List<RestTeacherSlot> teachers;
}

/// Stable synthetic id for a teacher known only by name. Always negative, so it
/// can never collide with a real master-data id or the "removed" marker 0.
int syntheticTeacherId(String shortName) {
  var h = 0x811c9dc5;
  for (final c in shortName.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return -(h % 0x3fffffff) - 1;
}

RestName? _name(Object? raw) {
  if (raw is! Map) return null;
  if (raw['type'] != 'TEACHER') return null;
  String s(Object? v) => v is String ? v.trim() : '';
  final short = s(raw['shortName']);
  final long = [s(raw['longName']), s(raw['displayName']), short]
      .firstWhere((x) => x.isNotEmpty, orElse: () => '');
  if (short.isEmpty && long.isEmpty) return null;
  return (shortName: short.isEmpty ? long : short, longName: long);
}

/// Tolerant parse of the `entries` response. Unknown shapes yield [].
List<RestEntry> parseRestEntries(Object? raw) {
  if (raw is! Map || raw['days'] is! List) return const [];
  final out = <RestEntry>[];
  for (final day in raw['days'] as List) {
    if (day is! Map || day['gridEntries'] is! List) continue;
    for (final g in day['gridEntries'] as List) {
      if (g is! Map) continue;
      final d = g['duration'];
      final start = d is Map ? parseDateTime(d['start']) : null;
      final end = d is Map ? parseDateTime(d['end']) : null;
      if (start == null || end == null) continue;
      final ids = [
        for (final i in (g['ids'] is List ? g['ids'] as List : const []))
          if (i is num) i.toInt(),
      ];
      final teachers = <RestTeacherSlot>[];
      for (var p = 1; p <= 7; p++) {
        final pos = g['position$p'];
        if (pos is! List) continue;
        for (final e in pos) {
          if (e is! Map) continue;
          final cur = _name(e['current']);
          final rem = _name(e['removed']);
          if (cur != null || rem != null) {
            teachers.add(RestTeacherSlot(current: cur, removed: rem));
          }
        }
      }
      out.add(RestEntry(ids: ids, start: start, end: end, teachers: teachers));
    }
  }
  return out;
}

List<ElementRef> _refs(List<RestTeacherSlot> slots) => [
  for (final t in slots)
    if (t.current != null && t.removed != null && t.current!.shortName != t.removed!.shortName)
      // Substitution: show the new teacher, strike the original.
      ElementRef(
        type: ElementType.teacher,
        id: syntheticTeacherId(t.current!.shortName),
        orgId: syntheticTeacherId(t.removed!.shortName),
        inlineName: t.current!.shortName,
        inlineLongName: t.current!.longName,
        orgInlineName: t.removed!.shortName,
        orgInlineLongName: t.removed!.longName,
      )
    else if (t.current != null)
      ElementRef(
        type: ElementType.teacher,
        id: syntheticTeacherId(t.current!.shortName),
        orgId: syntheticTeacherId(t.current!.shortName),
        inlineName: t.current!.shortName,
        inlineLongName: t.current!.longName,
      )
    else
      // Teacher removed without replacement.
      ElementRef(
        type: ElementType.teacher,
        id: 0,
        orgId: syntheticTeacherId(t.removed!.shortName),
        orgInlineName: t.removed!.shortName,
        orgInlineLongName: t.removed!.longName,
      ),
];

/// Adds REST teachers to [periods] that have no TEACHER element. Matches by
/// period id first, then by identical start/end when exactly one period and
/// one entry share that slot. Periods that already have teachers are left
/// untouched.
List<Period> mergeRestTeachers(List<Period> periods, List<RestEntry> entries) {
  if (entries.isEmpty) return periods;
  final byId = <int, RestEntry>{
    for (final e in entries)
      for (final id in e.ids) id: e,
  };
  String slot(DateTime s, DateTime e) => '${s.toIso8601String()}|${e.toIso8601String()}';
  final entriesBySlot = <String, List<RestEntry>>{};
  for (final e in entries) {
    (entriesBySlot[slot(e.start, e.end)] ??= []).add(e);
  }
  final periodsPerSlot = <String, int>{};
  for (final p in periods) {
    periodsPerSlot.update(slot(p.start, p.end), (n) => n + 1, ifAbsent: () => 1);
  }

  return [
    for (final p in periods)
      if (p.ofType(ElementType.teacher).isNotEmpty)
        p
      else
        () {
          final key = slot(p.start, p.end);
          final candidates = entriesBySlot[key];
          final match = byId[p.id] ??
              ((candidates?.length == 1 && periodsPerSlot[key] == 1) ? candidates!.single : null);
          if (match == null || match.teachers.isEmpty) return p;
          return p.copyWithElements([...p.elements, ..._refs(match.teachers)]);
        }(),
  ];
}
