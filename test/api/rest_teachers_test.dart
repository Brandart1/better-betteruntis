import 'package:better_betteruntis/api/rest_teachers.dart';
import 'package:better_betteruntis/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _el(String type, String short, String long) => {
  'type': type,
  'status': 'REGULAR',
  'shortName': short,
  'longName': long,
  'displayName': long,
  'displayNameLabel': type,
};

Map<String, Object?> _entry({
  required List<int> ids,
  required String start,
  required String end,
  Object? teacherCurrent,
  Object? teacherRemoved,
}) => {
  'ids': ids,
  'duration': {'start': start, 'end': end},
  'type': 'NORMAL_TEACHING_PERIOD',
  'status': 'REGULAR',
  'position1': [
    {'current': _el('SUBJECT', 'M', 'Mathematik'), 'removed': null},
  ],
  'position2': [
    {'current': teacherCurrent, 'removed': teacherRemoved},
  ],
  'position3': [
    {'current': _el('ROOM', 'R1', 'Raum 1'), 'removed': null},
  ],
  'position4': null,
};

Map<String, Object?> _response(List<Map<String, Object?>> entries) => {
  'format': 4,
  'days': [
    {'date': '2026-11-09', 'status': 'REGULAR', 'dayEntries': [], 'gridEntries': entries},
    {'date': '2026-11-14', 'status': 'NO_DATA', 'dayEntries': [], 'gridEntries': []},
  ],
  'errors': [],
};

Period _period(int id, String start, String end, {List<ElementRef> extra = const []}) => Period(
  id: id,
  lessonId: 1,
  start: DateTime.parse(start),
  end: DateTime.parse(end),
  elements: [
    const ElementRef(type: ElementType.subject, id: 5, orgId: 5),
    const ElementRef(type: ElementType.room, id: 9, orgId: 9),
    ...extra,
  ],
  flags: const {PeriodFlag.regular},
);

void main() {
  test('parses teachers from any position and ignores other types', () {
    final entries = parseRestEntries(_response([
      _entry(
        ids: [100],
        start: '2026-11-09T07:55',
        end: '2026-11-09T08:45',
        teacherCurrent: _el('TEACHER', 'ABC', 'Alpha Beta'),
      ),
    ]));
    expect(entries, hasLength(1));
    expect(entries.single.ids, [100]);
    expect(entries.single.teachers.single.current?.shortName, 'ABC');
    expect(entries.single.teachers.single.current?.longName, 'Alpha Beta');
  });

  test('junk input yields no entries instead of throwing', () {
    expect(parseRestEntries(null), isEmpty);
    expect(parseRestEntries({'days': 'x'}), isEmpty);
    expect(parseRestEntries({'days': [{'gridEntries': [{'duration': 1}]}]}), isEmpty);
  });

  test('merges by period id', () {
    final entries = parseRestEntries(_response([
      _entry(
        ids: [100],
        start: '2026-11-09T07:55',
        end: '2026-11-09T08:45',
        teacherCurrent: _el('TEACHER', 'ABC', 'Alpha Beta'),
      ),
    ]));
    // Times differ on purpose: the id must win.
    final merged = mergeRestTeachers([_period(100, '2026-11-09T09:00', '2026-11-09T09:50')], entries);
    final t = merged.single.ofType(ElementType.teacher).single;
    expect(t.inlineName, 'ABC');
    expect(t.inlineLongName, 'Alpha Beta');
    expect(t.id, lessThan(0));
    expect(t.change, ElementChange.regular);
  });

  test('falls back to a unique time slot when ids differ', () {
    final entries = parseRestEntries(_response([
      _entry(
        ids: [999],
        start: '2026-11-09T07:55',
        end: '2026-11-09T08:45',
        teacherCurrent: _el('TEACHER', 'ABC', 'Alpha Beta'),
      ),
    ]));
    final merged = mergeRestTeachers([_period(100, '2026-11-09T07:55', '2026-11-09T08:45')], entries);
    expect(merged.single.ofType(ElementType.teacher).single.inlineName, 'ABC');
  });

  test('ambiguous time slot is left alone', () {
    final entries = parseRestEntries(_response([
      _entry(ids: [998], start: '2026-11-09T07:55', end: '2026-11-09T08:45',
          teacherCurrent: _el('TEACHER', 'ABC', 'Alpha Beta')),
      _entry(ids: [999], start: '2026-11-09T07:55', end: '2026-11-09T08:45',
          teacherCurrent: _el('TEACHER', 'XYZ', 'Xi Yz')),
    ]));
    final merged = mergeRestTeachers([
      _period(100, '2026-11-09T07:55', '2026-11-09T08:45'),
      _period(101, '2026-11-09T07:55', '2026-11-09T08:45'),
    ], entries);
    for (final p in merged) {
      expect(p.ofType(ElementType.teacher), isEmpty);
    }
  });

  test('substitution and removal map to element changes with original names', () {
    final entries = parseRestEntries(_response([
      _entry(ids: [100], start: '2026-11-09T07:55', end: '2026-11-09T08:45',
          teacherCurrent: _el('TEACHER', 'NEW', 'New Teacher'),
          teacherRemoved: _el('TEACHER', 'OLD', 'Old Teacher')),
      _entry(ids: [101], start: '2026-11-09T08:50', end: '2026-11-09T09:40',
          teacherRemoved: _el('TEACHER', 'GONE', 'Gone Teacher')),
    ]));
    final merged = mergeRestTeachers([
      _period(100, '2026-11-09T07:55', '2026-11-09T08:45'),
      _period(101, '2026-11-09T08:50', '2026-11-09T09:40'),
    ], entries);
    final sub = merged[0].ofType(ElementType.teacher).single;
    expect(sub.change, ElementChange.substituted);
    expect(sub.inlineName, 'NEW');
    expect(sub.orgInlineName, 'OLD');
    expect(merged[0].isIrregular, isTrue);

    final removed = merged[1].ofType(ElementType.teacher).single;
    expect(removed.change, ElementChange.removed);
    expect(removed.orgInlineName, 'GONE');
  });

  test('periods that already have teachers are untouched', () {
    final p = _period(100, '2026-11-09T07:55', '2026-11-09T08:45',
        extra: const [ElementRef(type: ElementType.teacher, id: 42, orgId: 42)]);
    final entries = parseRestEntries(_response([
      _entry(ids: [100], start: '2026-11-09T07:55', end: '2026-11-09T08:45',
          teacherCurrent: _el('TEACHER', 'ABC', 'Alpha Beta')),
    ]));
    expect(identical(mergeRestTeachers([p], entries).single, p), isTrue);
  });

  test('synthetic ids are stable, negative and distinct', () {
    expect(syntheticTeacherId('ABC'), syntheticTeacherId('ABC'));
    expect(syntheticTeacherId('ABC'), lessThan(0));
    expect(syntheticTeacherId('ABC'), isNot(syntheticTeacherId('ABD')));
    expect(syntheticTeacherId(''), lessThan(0));
  });
}
