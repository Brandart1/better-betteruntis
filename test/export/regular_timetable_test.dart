import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/export/regular_timetable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'export_test_helpers.dart';

DateTime week(int i) => DateTime(mon.year, mon.month, mon.day + 7 * i);

int? teacherOf(Period p) => p.ofType(ElementType.teacher).firstOrNull?.id;

void main() {
  test('substitution is reverted to the planned teacher and room', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(
          week(0),
          1,
          teachers: [el(ElementType.teacher, 2, 1)],
          room: el(ElementType.room, 31, 30),
          flags: const {PeriodFlag.irregular},
          substitutionText: 'Vertretung',
        ),
      ]),
    ]);
    expect(res, hasLength(1));
    final p = res.single;
    expect(teacherOf(p), 1);
    expect(p.ofType(ElementType.room).single.id, 30);
    expect(p.isIrregular, isFalse);
    expect(p.substitutionText, isEmpty);
  });

  test('removed elements come back, added ones are dropped', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(
          week(0),
          1,
          teachers: [
            el(ElementType.teacher, 0, 1),
            el(ElementType.teacher, 5, 0),
          ],
        ),
      ]),
    ]);
    final teachers = res.single.ofType(ElementType.teacher).toList();
    expect(teachers.map((t) => t.id), [1]);
  });

  test('cancelled lessons count as planned', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(week(0), 2, flags: const {PeriodFlag.cancelled}),
      ]),
    ]);
    expect(res, hasLength(1));
    expect(res.single.isCancelled, isFalse);
    expect(res.single.start.weekday, 2);
  });

  test('purely additional lessons are dropped', () {
    final added = Period(
      id: 1,
      lessonId: 9,
      start: DateTime(2026, 11, 9, 14),
      end: DateTime(2026, 11, 9, 14, 45),
      elements: [
        el(ElementType.klasse, 40, 0),
        el(ElementType.subject, 12, 0),
        el(ElementType.teacher, 3, 0),
      ],
      flags: const {PeriodFlag.irregular},
    );
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [period(week(0), 1), added]),
    ]);
    expect(res, hasLength(1));
    expect(res.single.start.hour, 8);
  });

  test('exams are dropped; the slot is filled from other weeks', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(week(0), 1, subject: 10, flags: const {PeriodFlag.exam}),
      ]),
      SampleWeek(week(1), [period(week(1), 1, subject: 11)]),
    ]);
    expect(res.single.ofType(ElementType.subject).single.id, 11);
    // Dated in the reference (first) week.
    expect(res.single.start, DateTime(2026, 11, 9, 8));
  });

  test('exam only -> nothing', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(week(0), 1, exam: const Exam(id: 1, name: 'KA')),
      ]),
    ]);
    expect(res, isEmpty);
  });

  test('majority vote across weeks, ties go to the earliest week', () {
    Period at(int w, int subject) => period(week(w), 3, subject: subject);
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [at(0, 10)]),
      SampleWeek(week(1), [at(1, 11)]),
      SampleWeek(week(2), [at(2, 11)]),
      SampleWeek(week(3), [at(3, 10), period(week(3), 1)]),
    ]);
    // Slot Wed 08:00: 10 vs 11 two each -> earliest week (10).
    final wed = res.where((p) => p.start.weekday == 3).single;
    expect(wed.ofType(ElementType.subject).single.id, 10);

    final res2 = deriveRegularTimetable([
      SampleWeek(week(0), [at(0, 10)]),
      SampleWeek(week(1), [at(1, 11)]),
      SampleWeek(week(2), [at(2, 11)]),
    ]);
    expect(res2.single.ofType(ElementType.subject).single.id, 11);
  });

  test('a one-off lesson in an otherwise empty slot loses to "nothing"', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), [
        period(week(0), 1),
        period(week(0), 1, h: 13, lesson: 5),
      ]),
      SampleWeek(week(1), [period(week(1), 1)]),
      SampleWeek(week(2), [period(week(2), 1)]),
    ]);
    expect(res, hasLength(1));
    expect(res.single.start.hour, 8);
  });

  test('holiday days are filled from another sampled week', () {
    final fri0 = dayOf(week(0), 5);
    final res = deriveRegularTimetable(
      [
        // Friday of week 0 is a holiday (no lessons, or lessons marked
        // anyway — both must be ignored).
        SampleWeek(week(0), [
          period(week(0), 1),
          period(week(0), 5, subject: 99),
        ]),
        SampleWeek(week(1), [
          period(week(1), 1),
          period(week(1), 5, subject: 14),
        ]),
      ],
      holidays: [
        Holiday(id: 1, name: 'X', longName: 'Feiertag', start: fri0, end: fri0),
      ],
    );
    final fri = res.where((p) => p.start.weekday == 5).toList();
    expect(fri, hasLength(1));
    expect(fri.single.ofType(ElementType.subject).single.id, 14);
    // Reference week dates.
    expect(fri.single.start.day, fri0.day);
  });

  test('empty days (whole-week holidays) are not sampled', () {
    final res = deriveRegularTimetable([
      SampleWeek(week(0), const []),
      SampleWeek(week(1), [period(week(1), 2)]),
    ]);
    expect(res.single.start.weekday, 2);
  });

  test('parallel lessons in one slot are kept together', () {
    List<Period> slot(int w) => [
      period(week(w), 3, subject: 20, lesson: 1),
      period(week(w), 3, subject: 21, lesson: 2),
    ];
    final res = deriveRegularTimetable([
      SampleWeek(week(0), slot(0)),
      SampleWeek(week(1), slot(1)),
    ]);
    expect(res.map((p) => p.ofType(ElementType.subject).single.id).toSet(), {
      20,
      21,
    });
  });
}
