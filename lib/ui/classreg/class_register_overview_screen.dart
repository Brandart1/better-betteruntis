import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';
import 'class_register_screen.dart';
import 'substitute_note.dart';

/// Subject (long) names of [p], else its lesson text, else "Lesson".
String classRegLessonTitle(Period p, NameResolver? names) {
  final subjects = p.ofType(ElementType.subject).toList();
  if (subjects.isNotEmpty && names != null) {
    return subjects
        .map((s) => names.longName(s, original: s.id == 0))
        .join(', ');
  }
  return p.lessonText.isNotEmpty ? p.lessonText : 'Lesson';
}

/// "08:00 – 08:45 · 5a".
String classRegLessonTime(
  DateTime start,
  DateTime end,
  Period p,
  NameResolver? names,
) => [
  '${hhmm(minuteOfDay(start))} – ${hhmm(minuteOfDay(end))}',
  if (names != null)
    ...p
        .ofType(ElementType.klasse)
        .where((k) => k.id != 0)
        .map(names.shortName),
].join(' · ');

/// "Mon 3 Nov · 08:00 – 08:45 · 5a".
String classRegLessonSubtitle(
  BuildContext context,
  DateTime start,
  DateTime end,
  Period p,
  NameResolver? names,
) => [
  dateFormat(context, 'EEE d MMM').format(start),
  classRegLessonTime(start, end, p, names),
].join(' · ');

/// Range options of the past lessons in [ClassRegisterOverviewScreen], in
/// days.
const classRegRanges = [7, 14, 30];

/// The overview's idea of "now" (today vs. past, upcoming lessons).
final classRegisterClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Filter chips of [ClassRegisterOverviewScreen].
enum ClassRegFilter {
  all('All'),
  attendanceMissing('Attendance missing'),
  topicMissing('Topic missing'),
  done('Done');

  const ClassRegFilter(this.label);
  final String label;

  bool matches(PeriodRegister r) => switch (this) {
    all => true,
    attendanceMissing => !r.absenceChecked,
    topicMissing => !r.hasTopic,
    done => !r.isIncomplete,
  };

  /// Lessons a substitute held are never missing anything for the original
  /// teacher: they only show under [all].
  bool matchesLesson(ClassRegLesson l) =>
      l.isSubstituted ? this == all : matches(l.register);
}

final _lessonsProvider = FutureProvider.autoDispose
    .family<List<ClassRegLesson>, ({Account account, int days})>(
      (ref, q) => ref
          .watch(classRegisterRepositoryProvider)
          .lessons(q.account, days: q.days),
      retry: (_, _) => null,
    );

/// "Class register" (Klassenbuch) in the drawer: the teacher's lessons of
/// today (upcoming ones included) and of the last days, with what is still
/// missing (attendance check, topic).
class ClassRegisterOverviewScreen extends ConsumerStatefulWidget {
  const ClassRegisterOverviewScreen({super.key});

  @override
  ConsumerState<ClassRegisterOverviewScreen> createState() =>
      _ClassRegisterOverviewScreenState();
}

class _ClassRegisterOverviewScreenState
    extends ConsumerState<ClassRegisterOverviewScreen> {
  int _days = 14;
  ClassRegFilter _filter = ClassRegFilter.all;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final names = ref.watch(nameResolverProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class register'),
        actions: [
          PopupMenuButton<int>(
            key: const ValueKey('classreg-range'),
            tooltip: 'Time range',
            icon: const Icon(Icons.date_range_outlined),
            initialValue: _days,
            onSelected: (d) => setState(() => _days = d),
            itemBuilder: (_) => [
              for (final d in classRegRanges)
                PopupMenuItem(value: d, child: Text('Last $d days')),
            ],
          ),
        ],
      ),
      body: account == null || !hasClassRegister(account)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only teacher accounts have a class register.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _body(account, names),
    );
  }

  Widget _body(Account account, NameResolver? names) {
    final q = (account: account, days: _days);
    final async = ref.watch(_lessonsProvider(q));
    Future<void> reload() => ref.refresh(_lessonsProvider(q).future);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load: ${e is UntisException ? e.message : e}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: reload, child: const Text('Retry')),
            ],
          ),
        ),
      ),
      data: (lessons) => RefreshIndicator(
        onRefresh: () {
          ref.read(classRegisterRepositoryProvider).forgetReads();
          return reload();
        },
        child: _list(account, names, lessons, reload),
      ),
    );
  }

  Widget _list(
    Account account,
    NameResolver? names,
    List<ClassRegLesson> lessons,
    Future<void> Function() reload,
  ) {
    final now = ref.watch(classRegisterClockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final todays = [
      for (final l in lessons)
        if (!l.period.start.isBefore(today)) l,
    ]..sort((a, b) => a.period.start.compareTo(b.period.start));
    final past = [
      for (final l in lessons)
        if (l.period.start.isBefore(today)) l,
    ]..sort((a, b) => b.period.start.compareTo(a.period.start));
    final own = past.where((l) => !l.isSubstituted);
    final open = own.where((l) => l.register.isIncomplete).length;
    final shownToday = todays.where(_filter.matchesLesson);
    final shownPast = past.where(_filter.matchesLesson);
    final theme = Theme.of(context);

    Widget header(String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    Widget hint(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    String none(String what) => _filter == ClassRegFilter.all
        ? 'No lessons $what.'
        : 'No lessons $what match "${_filter.label}".';

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in ClassRegFilter.values)
                ChoiceChip(
                  key: ValueKey('classreg-filter-${f.name}'),
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        header('Today', key: const ValueKey('classreg-today')),
        if (shownToday.isEmpty) hint(none('today')),
        for (final l in shownToday)
          _tile(account, names, l, now, reload, today: true),
        header('Last $_days days', key: const ValueKey('classreg-past')),
        if (past.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              open == 0
                  ? 'Everything entered.'
                  : '$open of ${own.length} lessons miss the attendance '
                        'check or the topic.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (shownPast.isEmpty) hint(none('in the last $_days days')),
        for (final l in shownPast)
          _tile(account, names, l, now, reload, today: false),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tile(
    Account account,
    NameResolver? names,
    ClassRegLesson l,
    DateTime now,
    Future<void> Function() reload, {
    required bool today,
  }) {
    final p = l.period;
    final r = l.register;
    if (l.isSubstituted) return _substitutedTile(account, names, l, reload);
    final upcoming = p.start.isAfter(now);
    final running = !upcoming && p.end.isAfter(now);
    final title = classRegLessonTitle(p, names);
    final subtitle = classRegLessonSubtitle(context, p.start, p.end, p, names);
    final when = today
        ? [
            classRegLessonTime(p.start, p.end, p, names),
            if (upcoming) 'upcoming',
            if (running) 'now',
          ].join(' · ')
        : subtitle;
    final scheme = Theme.of(context).colorScheme;
    final large = isLargeText(context);
    final IconData icon;
    final Color color;
    if (!r.isIncomplete) {
      (icon, color) = (Icons.task_alt, scheme.primary);
    } else if (upcoming) {
      (icon, color) = (Icons.schedule, scheme.onSurfaceVariant);
    } else {
      (icon, color) = (Icons.pending_actions_outlined, scheme.error);
    }
    return ListTile(
      key: ValueKey('classreg-lesson-${p.id}'),
      leading: large ? null : Icon(icon, color: color),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              _Status(
                done: r.absenceChecked,
                upcoming: upcoming,
                doneText: 'Attendance checked',
                missingText: 'Attendance missing',
              ),
              _Status(
                done: r.hasTopic,
                upcoming: upcoming,
                doneText: 'Topic entered',
                missingText: 'Topic missing',
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: large ? null : const Icon(Icons.chevron_right),
      onTap: () async {
        await openClassRegister(
          context,
          account: account,
          periods: [p],
          title: title,
          subtitle: subtitle,
        );
        if (mounted) await reload();
      },
    );
  }
}

extension on _ClassRegisterOverviewScreenState {
  /// A lesson a substitute held instead of the teacher: "Substituted by X"
  /// with what they entered; opens the read-only class register.
  Widget _substitutedTile(
    Account account,
    NameResolver? names,
    ClassRegLesson l,
    Future<void> Function() reload,
  ) {
    final p = l.period;
    final r = l.register;
    final title = classRegLessonTitle(p, names);
    final subtitle = classRegLessonSubtitle(context, p.start, p.end, p, names);
    final large = isLargeText(context);
    final entered = l.registerMissing
        ? 'What they entered is not visible to you.'
        : [
            r.hasTopic ? 'Topic: ${r.topic.trim()}' : 'No topic entered',
            r.absenceChecked
                ? '${r.absences.map((a) => a.studentId).toSet().length} '
                      'absent'
                : 'Attendance not checked',
          ].join(' · ');
    return ListTile(
      key: ValueKey('classreg-lesson-${p.id}'),
      leading: large
          ? null
          : Icon(
              Icons.swap_horiz,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      title: Text(title),
      subtitle: Text(
        '$subtitle\n'
        'Substituted by ${substituteName(l.substitutedBy, names)}\n'
        '$entered',
      ),
      isThreeLine: true,
      trailing: large ? null : const Icon(Icons.chevron_right),
      onTap: () async {
        await openClassRegister(
          context,
          account: account,
          periods: [p],
          title: title,
          subtitle: subtitle,
        );
        if (mounted) await reload();
      },
    );
  }
}

/// "✓ Topic entered" / "! Topic missing" (neutral for upcoming lessons).
class _Status extends StatelessWidget {
  const _Status({
    required this.done,
    required this.upcoming,
    required this.doneText,
    required this.missingText,
  });

  final bool done;
  final bool upcoming;
  final String doneText;
  final String missingText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done
        ? scheme.primary
        : upcoming
        ? scheme.onSurfaceVariant
        : scheme.error;
    final icon = done
        ? Icons.check_circle
        : upcoming
        ? Icons.radio_button_unchecked
        : Icons.error_outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            done ? doneText : missingText,
            style: TextStyle(color: done ? null : color),
          ),
        ),
      ],
    );
  }
}
