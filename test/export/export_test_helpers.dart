import 'package:better_betteruntis/core/models.dart';

/// Monday 2026-11-09.
final mon = DateTime(2026, 11, 9);

DateTime dayOf(DateTime weekStart, int weekday) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + weekday - 1);

ElementRef el(ElementType t, int id, [int? orgId]) =>
    ElementRef(type: t, id: id, orgId: orgId ?? id);

int _ids = 1;

/// A period on [weekday] of [weekStart] from [h]:[m] lasting [minutes].
Period period(
  DateTime weekStart,
  int weekday, {
  int h = 8,
  int m = 0,
  int minutes = 45,
  int lesson = 1,
  int subject = 10,
  List<ElementRef>? teachers,
  ElementRef? room,
  List<ElementRef> extra = const [],
  Set<PeriodFlag> flags = const {PeriodFlag.regular},
  Exam? exam,
  String infoText = '',
  String substitutionText = '',
  int? backColor,
}) {
  final d = dayOf(weekStart, weekday);
  final start = DateTime(d.year, d.month, d.day, h, m);
  return Period(
    id: _ids++,
    lessonId: lesson,
    start: start,
    end: start.add(Duration(minutes: minutes)),
    elements: [
      el(ElementType.klasse, 40),
      el(ElementType.subject, subject),
      ...?teachers,
      if (teachers == null) el(ElementType.teacher, 1),
      room ?? el(ElementType.room, 30),
      ...extra,
    ],
    flags: flags,
    exam: exam,
    infoText: infoText,
    substitutionText: substitutionText,
    backColor: backColor,
  );
}
