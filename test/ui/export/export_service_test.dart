import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/export_model.dart';
import 'package:better_betteruntis/ui/export/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mon = DateTime(2026, 11, 9);
  const target = TimetableTarget(ElementType.klasse, DemoIds.klasse);

  Future<ExportTimetable> prepare(ExportKind kind, {FakeNameResolver? names}) {
    final n = names ?? FakeNameResolver();
    return prepareExport(
      repo: FakeTimetableRepository(names: n),
      names: n,
      account: demoAccount(),
      target: target,
      elementName: '10a',
      options: ExportOptions(
        kind: kind,
        weekStart: mon,
        format: ExportFormat.csv,
      ),
    );
  }

  test(
    'regular timetable from the demo weeks reverts one-off changes',
    () async {
      final t = await prepare(ExportKind.regular);
      expect(t.periodLabel, 'Regular timetable');
      expect(t.schoolName, 'Demo-Gymnasium');
      expect(t.lessons.every((l) => l.status == LessonStatus.regular), isTrue);

      ExportLesson at(int day, int hour, int minute) => t.lessons.firstWhere(
        (l) => l.weekday == day && l.start == hour * 60 + minute,
      );
      // Tue unit 4: substitution FIS for WEB -> WEB.
      expect(at(2, 10, 30).teachersShort, ['WEB']);
      // Tue unit 5: cancelled chemistry is planned.
      expect(at(2, 11, 30).subject, 'CH');
      // Tue unit 3: exam every week -> dropped.
      expect(
        t.lessons.where((l) => l.weekday == 2 && l.start == 9 * 60 + 40),
        isEmpty,
      );
      // Wed unit 5: removed SCH restored, added NEU dropped, room R102.
      final ge = at(3, 11, 30);
      expect(ge.teachersShort, ['SCH']);
      expect(ge.rooms, ['R102']);
    },
  );

  test(
    'holiday Friday in the shown week is filled from the next weeks',
    () async {
      final fri = DateTime(2026, 11, 13);
      final names = FakeNameResolver(
        holidays: [
          Holiday(
            id: 1,
            name: 'S',
            longName: 'Studientag',
            start: fri,
            end: fri,
          ),
        ],
      );
      final t = await prepare(ExportKind.regular, names: names);
      expect(t.lessons.where((l) => l.weekday == 5), isNotEmpty);
      expect(t.holidays, isEmpty);

      final week = await prepare(ExportKind.week, names: names);
      expect(week.holidays, {5: 'Studientag'});
      expect(week.periodLabel, '9 – 13 Nov 2026');
    },
  );
}
