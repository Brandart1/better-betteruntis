import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/absence_stats.dart';
import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'absence_lessons.dart';
import 'absences_tab.dart';
import 'info_common.dart';
import 'info_providers.dart';

/// Absences per subject with the attendance in each, over the time range
/// chosen in the Absences tab (up to today). Computed from the absences and
/// the timetable: cancelled lessons don't count.
class AbsencesBySubjectScreen extends ConsumerWidget {
  const AbsencesBySubjectScreen({super.key, required this.account, this.now});
  final Account account;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = this.now ?? DateTime.now();
    final filter = ref.watch(absenceFilterProvider);
    final (start, end) = filter.dates(now);
    final absences = ref.watch(
      absencesProvider(InfoQuery(account, start: start, end: end)),
    );
    final lessons = ref.watch(
      absenceLessonsProvider(AbsenceWeeks(account, mondaysBetween(start, now))),
    );
    final names = ref.watch(nameResolverProvider).value;

    Widget body;
    final items = absences.value?.data;
    final periods = lessons.value;
    if (absences.hasError && items == null) {
      body = const InfoEmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load absences',
      );
    } else if (lessons.hasValue && periods == null) {
      body = const InfoEmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load the timetable',
        message: 'The lessons are needed to work out the attendance.',
      );
    } else if (items == null || periods == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final inRange = [
        for (final p in periods)
          if (!p.start.isBefore(start)) p,
      ];
      final stats = attendanceBySubject(inRange, items, now);
      body = stats.isEmpty
          ? const InfoEmptyState(
              icon: Icons.event_busy,
              title: 'No lessons in this time range',
            )
          : _list(context, names, stats);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Absences by subject'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${filter.range.label}, up to today',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _list(
    BuildContext context,
    NameResolver? names,
    List<SubjectAttendance> stats,
  ) {
    var lessonMinutes = 0;
    var absentMinutes = 0;
    for (final s in stats) {
      lessonMinutes += s.lessonMinutes;
      absentMinutes += s.absentMinutes;
    }
    final total = SubjectAttendance(
      subjectId: -1,
      lessons: 0,
      missed: 0,
      missedUnexcused: 0,
      lessonMinutes: lessonMinutes,
      absentMinutes: absentMinutes,
    );
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kInfoMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Card.filled(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      formatPercent(total.attendancePercent),
                      key: const ValueKey('absences-subject-total'),
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text(
                      'Attendance in all subjects',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
            for (final s in stats)
              _SubjectCard(name: subjectName(names, s.subjectId), stats: s),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                'Attendance is the share of lesson time you were there. '
                'Cancelled lessons don\'t count. A lesson counts as missed '
                'with any absence in it, also arriving late or leaving early.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "97 %" or "97.5 %".
String formatPercent(double p) {
  final r = (p * 10).round() / 10;
  return r == r.roundToDouble()
      ? '${r.round()} %'
      : '${r.toStringAsFixed(1)} %';
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.name, required this.stats});
  final String name;
  final SubjectAttendance stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = stats;
    final p = s.attendancePercent;
    final missed = s.missed == 0
        ? 'No absences · ${s.lessons} ${s.lessons == 1 ? 'lesson' : 'lessons'}'
        : 'Missed ${s.missed} of ${s.lessons} lessons'
              '${s.missedUnexcused > 0 ? ' · ${s.missedUnexcused} unexcused' : ''}'
              ' · ${formatHours(s.absentMinutes / 60)}';
    return Card.outlined(
      key: ValueKey('absences-subject-${s.subjectId}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                Text(
                  formatPercent(p),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: s.missedUnexcused > 0 ? cs.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Semantics(
              label: 'Attendance ${formatPercent(p)}',
              child: LinearProgressIndicator(
                value: p / 100,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              missed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weeks touched by [items] (for the whole-day check on each absence).
List<DateTime> absenceMondays(List<AbsenceItem> items) => [
  for (final a in items) ...mondaysBetween(a.start, a.end),
];
