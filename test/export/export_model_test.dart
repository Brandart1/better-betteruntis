import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/export/export_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'export_test_helpers.dart';

void main() {
  final names = FakeNameResolver();

  test('lessons from the demo week: merging, names, status, colors', () {
    final lessons = buildExportLessons(
      buildDemoWeek(mon),
      names,
      regular: false,
    );
    final maths = lessons.firstWhere((l) => l.weekday == 1 && l.subject == 'M');
    expect(maths.lessonNumbers, '1–2');
    expect(maths.start, 7 * 60 + 45);
    expect(maths.end, 9 * 60 + 20);
    expect(maths.subjectLong, 'Mathematik');
    expect(maths.teachers, ['MUE (Anna Müller)']);
    expect(maths.teachersShort, ['MUE']);
    expect(maths.rooms, ['R101']);
    expect(maths.classes, ['10a']);
    // School color of the subject.
    expect(maths.color, 0xFFB3D4FC);

    final subst = lessons.firstWhere((l) => l.weekday == 2 && l.subject == 'E');
    expect(subst.status, LessonStatus.substitution);
    expect(subst.teachersShort, ['FIS']);
    expect(subst.replaced, ['WEB']);
    expect(subst.info, 'Vertretung');

    final cancelled = lessons.firstWhere((l) => l.subject == 'CH');
    expect(cancelled.status, LessonStatus.cancelled);
    expect(cancelled.color, ExportPalette.defaultCancelled);

    final exam = lessons.firstWhere((l) => l.weekday == 2 && l.subject == 'M');
    expect(exam.status, LessonStatus.exam);
    expect(exam.info, contains('Klassenarbeit Nr. 2'));

    // Removed teacher SCH + inline-only NEU.
    final ge = lessons.firstWhere((l) => l.weekday == 3 && l.subject == 'GE');
    expect(ge.teachers, ['NEU (Nina Neumann)']);
    expect(ge.replaced, containsAll(['SCH', 'R102']));
    expect(ge.replacedTeachers, ['SCH']);
    expect(ge.replacedRooms, ['R102']);
    expect(ge.rooms, ['R204']);
  });

  test('unresolved names are dropped', () {
    final p = period(
      mon,
      1,
      teachers: [el(ElementType.teacher, 777)],
      room: el(ElementType.room, 888),
    );
    final l = buildExportLessons([p], names, regular: false).single;
    expect(l.teachers, isEmpty);
    expect(l.rooms, isEmpty);
    expect(l.subject, 'M');
  });

  test('regular mode reports everything as regular, no one-off texts', () {
    final p = period(mon, 1, infoText: 'Heute in der Aula');
    final l = buildExportLessons([p], names, regular: true).single;
    expect(l.status, LessonStatus.regular);
    expect(l.info, isEmpty);
  });

  test('no palette -> no colors', () {
    final l = buildExportLessons(
      [period(mon, 1)],
      names,
      regular: false,
      palette: null,
    ).single;
    expect(l.color, isNull);
  });

  group('palette', () {
    test('defaults: everything filled', () {
      const p = ExportPalette();
      expect(p.colorFor(LessonStatus.exam, null), ExportPalette.defaultExam);
      expect(p.borderFor(LessonStatus.exam), isNull);
      expect(
        p.colorFor(LessonStatus.cancelled, 0xFF81C784),
        ExportPalette.defaultCancelled,
      );
      expect(
        p.colorFor(LessonStatus.substitution, 0xFF81C784),
        ExportPalette.defaultSubstitution,
      );
      expect(p.borderFor(LessonStatus.substitution), isNull);
      const b = ExportPalette(substitutionMode: StateColorMode.border);
      expect(b.colorFor(LessonStatus.substitution, 0xFF81C784), 0xFF81C784);
      expect(
        b.borderFor(LessonStatus.substitution),
        ExportPalette.defaultSubstitutionBorder,
      );
      expect(p.borderFor(LessonStatus.regular), isNull);
    });

    test('fromSettings: subject colors win, modes are taken over', () {
      final p = ExportPalette.fromSettings(
        const TimetableSettings(
          regularColor: 0xFF00796B,
          examColor: 0xFFD32F2F,
          subjectColors: {'M': 0xFF1976D2},
          examMode: StateColorMode.border,
          irregularMode: StateColorMode.fill,
          cancelledMode: StateColorMode.border,
        ),
      );
      expect(p.colorFor(LessonStatus.regular, 0xFF81C784, 'm'), 0xFF1976D2);
      expect(p.colorFor(LessonStatus.regular, 0xFF81C784, 'D'), 0xFF81C784);
      expect(p.colorFor(LessonStatus.regular, null, 'D'), 0xFF00796B);
      // Exam as border: base color + custom exam color as border.
      expect(p.colorFor(LessonStatus.exam, null, 'M'), 0xFF1976D2);
      expect(p.borderFor(LessonStatus.exam), 0xFFD32F2F);
      // Substitution filled even over the school color.
      expect(
        p.colorFor(LessonStatus.substitution, 0xFF81C784, 'M'),
        ExportPalette.defaultSubstitution,
      );
      expect(p.borderFor(LessonStatus.substitution), isNull);
      expect(
        p.borderFor(LessonStatus.cancelled),
        ExportPalette.defaultCancelledBorder,
      );
    });

    test('lessons carry subject colors and border colors', () {
      final palette = ExportPalette.fromSettings(
        const TimetableSettings(
          subjectColors: {'M': 0xFF1976D2},
          examMode: StateColorMode.border,
        ),
      );
      final lessons = buildExportLessons(
        buildDemoWeek(mon),
        names,
        regular: false,
        palette: palette,
      );
      final maths = lessons.firstWhere(
        (l) => l.weekday == 1 && l.subject == 'M',
      );
      expect(maths.color, 0xFF1976D2);
      expect(maths.borderColor, isNull);
      final exam = lessons.firstWhere(
        (l) => l.weekday == 2 && l.subject == 'M',
      );
      expect(exam.color, 0xFF1976D2);
      expect(exam.borderColor, ExportPalette.defaultExamBorder);
    });
  });

  test('file names are sanitized', () {
    expect(
      exportFileName('Anna Müller', ExportKind.regular, mon, ExportFormat.csv),
      'timetable_Anna_Mueller_regular.csv',
    );
    expect(
      exportFileName('10a/b: Ä?', ExportKind.week, mon, ExportFormat.pdf),
      'timetable_10a_b_Ae_2026-11-09.pdf',
    );
    expect(
      exportFileName('???', ExportKind.week, mon, ExportFormat.xlsx),
      'timetable_export_2026-11-09.xlsx',
    );
  });

  test('week range label', () {
    expect(
      exportWeekRange(DateTime(2026, 11, 9), DateTime(2026, 11, 13)),
      '9 – 13 Nov 2026',
    );
    expect(
      exportWeekRange(DateTime(2026, 10, 26), DateTime(2026, 11, 1)),
      '26 Oct – 1 Nov 2026',
    );
    expect(
      exportWeekRange(DateTime(2025, 12, 29), DateTime(2026, 1, 2)),
      '29 Dec 2025 – 2 Jan 2026',
    );
  });

  test('text style from the timetable settings, scales clamped', () {
    expect(
      ExportTextStyle.fromSettings(const TimetableSettings()),
      const ExportTextStyle(),
    );
    const d = ExportTextStyle();
    expect(d.subjectScale, 1);
    expect(d.detailScale, 1);

    final s = ExportTextStyle.fromSettings(
      const TimetableSettings(
        centerText: false,
        subjectFontSize: 22,
        detailFontSize: 9,
        boldSubject: false,
      ),
    );
    expect(s.centered, isFalse);
    expect(s.boldSubject, isFalse);
    expect(s.subjectScale, closeTo(22 / 15, 1e-9));
    expect(s.detailScale, 0.75);

    expect(const ExportTextStyle(subjectSize: 100).subjectScale, 1.5);
    expect(const ExportTextStyle(detailSize: 1).detailScale, 0.7);
    expect(const ExportTextStyle(detailSize: double.nan).detailScale, 1);
  });
}
