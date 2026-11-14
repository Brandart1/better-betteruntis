import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../timetable/lesson_card.dart';
import '../timetable/lesson_layout.dart';

/// Kinds of sample lessons in the settings preview.
enum PreviewKind { regular, substitution, cancelled, exam, school }

/// Row of sample lessons rendered with the real [LessonCard], so every
/// settings change is visible instantly.
class LessonPreview extends StatelessWidget {
  const LessonPreview({super.key, this.height = 104});

  final double height;

  static const _labels = {
    PreviewKind.regular: 'Regular',
    PreviewKind.substitution: 'Substitution',
    PreviewKind.cancelled: 'Cancelled',
    PreviewKind.exam: 'Exam',
    PreviewKind.school: 'School color',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final kind in PreviewKind.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  SizedBox(
                    height: height,
                    child: LessonCard(
                      key: ValueKey('preview-${kind.name}'),
                      block: LessonBlock([_samplePeriod(kind)]),
                      names: _previewNames,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labels[kind]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final _day = DateTime(2026, 11, 9);

ElementRef _ref(ElementType type, int id, [int? orgId]) =>
    ElementRef(type: type, id: id, orgId: orgId ?? id);

Period _samplePeriod(PreviewKind kind) {
  final (subject, teacher, room, flags, orgTeacher) = switch (kind) {
    PreviewKind.regular => (1, 11, 21, {PeriodFlag.regular}, null),
    PreviewKind.substitution => (2, 12, 22, {PeriodFlag.irregular}, 13),
    PreviewKind.cancelled => (3, 13, 23, {PeriodFlag.cancelled}, null),
    PreviewKind.exam => (4, 14, 24, {PeriodFlag.exam}, null),
    PreviewKind.school => (5, 15, 25, {PeriodFlag.regular}, null),
  };
  return Period(
    id: 900 + kind.index,
    lessonId: 900 + kind.index,
    start: DateTime(_day.year, _day.month, _day.day, 8),
    end: DateTime(_day.year, _day.month, _day.day, 8, 45),
    elements: [
      _ref(ElementType.subject, subject),
      _ref(ElementType.teacher, teacher, orgTeacher),
      _ref(ElementType.room, room),
    ],
    flags: flags,
    backColor: kind == PreviewKind.school ? 0xFF81C784 : null,
  );
}

const _previewNames = _PreviewNames();

class _PreviewNames implements NameResolver {
  const _PreviewNames();

  static const _short = {
    1: 'M', 2: 'D', 3: 'E', 4: 'PH', 5: 'BIO', //
    11: 'MUE', 12: 'FIS', 13: 'WEB', 14: 'BEC', 15: 'NEU', //
    21: 'R101', 22: 'R204', 23: 'R12', 24: 'LAB', 25: 'R3',
  };
  static const _long = {
    1: 'Mathematik',
    2: 'Deutsch',
    3: 'Englisch',
    4: 'Physik',
    5: 'Biologie',
    11: 'Anna Müller',
    12: 'Jonas Fischer',
    13: 'Lena Weber',
    14: 'Maria Becker',
    15: 'Nina Neumann',
  };

  int _id(ElementRef r, bool original) => original ? r.orgId : r.id;

  @override
  String shortName(ElementRef ref, {bool original = false}) =>
      _short[_id(ref, original)] ?? '?';

  @override
  String longName(ElementRef ref, {bool original = false}) {
    final id = _id(ref, original);
    return _long[id] ?? _short[id] ?? '?';
  }

  @override
  MasterElement? element(ElementType type, int id) => null;

  @override
  List<MasterElement> elementsOf(ElementType type, {bool onlyActive = true}) =>
      const [];

  @override
  List<Holiday> get holidays => const [];

  @override
  List<SchoolYear> get schoolYears => const [];

  @override
  TimeGrid get timeGrid => TimeGrid.fallback();
}
