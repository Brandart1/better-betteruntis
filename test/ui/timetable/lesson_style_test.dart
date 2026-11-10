import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/dev/fake_timetable.dart';
import 'package:better_betteruntis/ui/timetable/lesson_layout.dart';
import 'package:better_betteruntis/ui/timetable/lesson_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../export/export_test_helpers.dart';

void main() {
  final cs = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final names = FakeNameResolver();
  const school = 0xFF81C784;
  const mathsBlue = 0xFF1976D2;

  LessonStyle styleOf(
    Set<PeriodFlag> flags,
    TimetableSettings s, {
    int? backColor,
  }) => LessonStyle.of(
    cs,
    LessonBlock([period(mon, 1, flags: flags, backColor: backColor)]),
    s,
    names,
  );

  group('base color priority', () {
    test('subject > school > regular > theme', () {
      const regular = {PeriodFlag.regular};
      const s = TimetableSettings(
        regularColor: 0xFF00796B,
        subjectColors: {'M': mathsBlue},
      );
      expect(
        styleOf(regular, s, backColor: school).background,
        const Color(mathsBlue),
      );
      final noSubject = s.copyWith(subjectColors: const {});
      expect(
        styleOf(regular, noSubject, backColor: school).background,
        const Color(school),
      );
      expect(
        styleOf(
          regular,
          noSubject.copyWith(useSchoolColors: false),
          backColor: school,
        ).background,
        const Color(0xFF00796B),
      );
      expect(
        styleOf(regular, const TimetableSettings()).background,
        cs.primaryContainer,
      );
    });

    test('subject names are matched case- and whitespace-insensitively', () {
      final s = const TimetableSettings().withSubjectColor(' m ', mathsBlue);
      expect(s.subjectColors, {'M': mathsBlue});
      expect(
        styleOf({PeriodFlag.regular}, s).background,
        const Color(mathsBlue),
      );
      // Without a resolver only inline names can match: no color here.
      final p = period(mon, 1);
      expect(
        LessonStyle.of(cs, LessonBlock([p]), s).background,
        cs.primaryContainer,
      );
    });

    test('white text on a dark subject color', () {
      const s = TimetableSettings(subjectColors: {'M': 0xFF0D47A1});
      expect(styleOf({PeriodFlag.regular}, s).foreground, Colors.white);
    });
  });

  group('defaults reproduce the previous look', () {
    const s = TimetableSettings();

    test('cancelled and exam are filled', () {
      final c = styleOf({PeriodFlag.cancelled}, s);
      expect(c.background, cs.surfaceContainerHighest);
      expect(c.border, isNull);
      expect(c.cancelled, isTrue);
      final e = styleOf({PeriodFlag.exam}, s);
      expect(e.background, cs.errorContainer);
      expect(e.border, cs.error);
      expect(e.borderWidth, LessonStyle.defaultBorderWidth);
    });

    test('substitution is filled by default, even over school colors', () {
      final st = styleOf({PeriodFlag.irregular}, s, backColor: school);
      expect(st.background, cs.tertiaryContainer);
    });

    test('border mode: school-colored substitution keeps its color', () {
      final st = styleOf(
        {PeriodFlag.irregular},
        s.copyWith(irregularMode: StateColorMode.border),
        backColor: school,
      );
      expect(st.background, const Color(school));
      expect(st.border, cs.tertiary);
    });
  });

  group('fill vs border', () {
    test('fill paints the state color, even over subject/school colors', () {
      const s = TimetableSettings(
        irregularMode: StateColorMode.fill,
        subjectColors: {'M': mathsBlue},
      );
      final st = styleOf({PeriodFlag.irregular}, s, backColor: school);
      expect(st.background, cs.tertiaryContainer);
      expect(st.border, cs.tertiary);

      final custom = styleOf({
        PeriodFlag.irregular,
      }, s.copyWith(irregularColor: 0xFFF57C00));
      expect(custom.background, const Color(0xFFF57C00));
    });

    test('border keeps the base color and draws a thick state border', () {
      const s = TimetableSettings(
        examMode: StateColorMode.border,
        cancelledMode: StateColorMode.border,
        irregularMode: StateColorMode.border,
        examColor: 0xFFD32F2F,
        subjectColors: {'M': mathsBlue},
      );
      final e = styleOf({PeriodFlag.exam}, s);
      expect(e.background, const Color(mathsBlue));
      expect(e.border, const Color(0xFFD32F2F));
      expect(e.borderWidth, LessonStyle.stateBorderWidth);
      expect(e.exam, isTrue);

      final c = styleOf({PeriodFlag.cancelled}, s);
      expect(c.background, const Color(mathsBlue));
      expect(c.border, cs.outline);
      expect(c.cancelled, isTrue, reason: 'keeps the strike-through');

      final i = styleOf(
        {PeriodFlag.irregular},
        s.copyWith(subjectColors: const {}),
        backColor: school,
      );
      expect(i.background, const Color(school));
      expect(i.border, cs.tertiary);
      expect(i.borderWidth, LessonStyle.stateBorderWidth);
    });

    test('cancelled wins over exam, exam over substitution', () {
      const s = TimetableSettings(cancelledColor: 0xFF90A4AE);
      final st = styleOf({PeriodFlag.cancelled, PeriodFlag.exam}, s);
      expect(st.cancelled, isTrue);
      expect(st.exam, isFalse);
      final ex = styleOf({PeriodFlag.exam, PeriodFlag.irregular}, s);
      expect(ex.exam, isTrue);
      expect(ex.background, cs.errorContainer);
    });
  });
}
