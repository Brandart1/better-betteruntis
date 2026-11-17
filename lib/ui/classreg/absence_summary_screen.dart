import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/absence_summary.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';

/// Grouping of [AbsenceSummaryScreen].
enum AbsenceSummaryGrouping {
  pupil('Per pupil'),
  klasse('Whole class');

  const AbsenceSummaryGrouping(this.label);
  final String label;
}

/// Absence summary of a lesson's pupils: scope Lesson · Subject · All
/// subjects, per pupil (tap for the pupil's absences) or for the whole
/// class. Period: the school year so far, or a custom range.
class AbsenceSummaryScreen extends ConsumerStatefulWidget {
  const AbsenceSummaryScreen({
    super.key,
    required this.account,
    required this.periods,
    required this.title,
    this.initialScope = AbsenceSummaryScope.lesson,
    this.scopes = AbsenceSummaryScope.values,
  });

  final Account account;
  final List<Period> periods;
  final String title;
  final AbsenceSummaryScope initialScope;

  /// The scopes to choose from; no choice when only one.
  final List<AbsenceSummaryScope> scopes;

  @override
  ConsumerState<AbsenceSummaryScreen> createState() =>
      _AbsenceSummaryScreenState();
}

class _AbsenceSummaryScreenState extends ConsumerState<AbsenceSummaryScreen> {
  late AbsenceSummaryScope _scope = widget.initialScope;
  AbsenceSummaryGrouping _grouping = AbsenceSummaryGrouping.pupil;

  /// Custom range; null = the school year so far.
  DateTimeRange? _range;
  SchoolYear? _year;

  AbsenceSummary? _summary;
  Object? _error;
  (int, int)? _progress;

  /// Only the latest load may set state.
  int _generation = 0;

  AbsenceSummaryRepository get _repo =>
      ref.read(absenceSummaryRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _repo.schoolYear(widget.account).then((y) {
      if (mounted) setState(() => _year = y);
    }, onError: (_) {});
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _summary = null;
      _error = null;
      _progress = null;
    });
    try {
      final s = await _repo.summary(
        widget.account,
        widget.periods,
        scope: _scope,
        from: _range?.start,
        to: _range?.end,
        onProgress: (done, total) {
          if (mounted && gen == _generation) {
            setState(() => _progress = (done, total));
          }
        },
      );
      if (mounted && gen == _generation) setState(() => _summary = s);
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  void _setScope(AbsenceSummaryScope s) {
    if (s == _scope) return;
    _scope = s;
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2, 1, 1);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange:
          _range ??
          (_summary == null || _summary!.from.isBefore(first)
              ? null
              : DateTimeRange(start: _summary!.from, end: _summary!.to)),
    );
    if (picked == null || !mounted) return;
    _range = picked;
    _load();
  }

  void _resetRange() {
    _range = null;
    _load();
  }

  static String _message(Object e) =>
      e is UntisException ? e.message : e.toString();

  String _date(DateTime d) => dateFormat(context, 'd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Absence summary'),
            Text(widget.title, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (widget.scopes.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _Choice<AbsenceSummaryScope>(
                  keyPrefix: 'summary-scope',
                  values: widget.scopes,
                  selected: _scope,
                  label: (s) => s.label,
                  onSelected: _setScope,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _Choice<AbsenceSummaryGrouping>(
                keyPrefix: 'summary-group',
                values: AbsenceSummaryGrouping.values,
                selected: _grouping,
                label: (g) => g.label,
                onSelected: (g) => setState(() => _grouping = g),
              ),
            ),
            if (_scope != AbsenceSummaryScope.lesson) _rangeTile(theme),
            ..._content(theme),
          ],
        ),
      ),
    );
  }

  Widget _rangeTile(ThemeData theme) {
    final s = _summary;
    final String text;
    if (_range != null) {
      text = '${_date(_range!.start)} – ${_date(_range!.end)}';
    } else if (s != null) {
      text =
          '${_year?.name.isNotEmpty == true ? 'School year ${_year!.name}' : 'School year'}'
          ' so far (${_date(s.from)} – ${_date(s.to)})';
    } else {
      text = 'School year so far';
    }
    final change = TextButton(
      key: const ValueKey('summary-range'),
      onPressed: _pickRange,
      child: const Text('Change'),
    );
    final reset = TextButton(
      key: const ValueKey('summary-range-reset'),
      onPressed: _resetRange,
      child: const Text('School year'),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          change,
          if (_range != null) reset,
        ],
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Could not load the absences: ${_message(_error!)}',
                key: const ValueKey('summary-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const ValueKey('summary-retry'),
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ];
    }
    final s = _summary;
    if (s == null) {
      final p = _progress;
      final step = p == null
          ? 'Loading…'
          : _scope == AbsenceSummaryScope.subject
          ? 'Reading the lessons of this course… (${p.$1} of ${p.$2})'
          : 'Loading… (${p.$1} of ${p.$2})';
      return [
        Padding(
          key: const ValueKey('summary-loading'),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step, style: muted),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: p == null || p.$2 == 0 ? null : p.$1 / p.$2,
              ),
            ],
          ),
        ),
      ];
    }
    return [
      ..._notes(s, muted),
      if (_grouping == AbsenceSummaryGrouping.klasse)
        _classTotals(theme, s)
      else if (s.pupils.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No pupils or absences found.', style: muted),
        )
      else
        for (final p in s.pupils) _pupilTile(theme, s, p),
    ];
  }

  List<Widget> _notes(AbsenceSummary s, TextStyle? muted) {
    final notes = [
      if (s.scope == AbsenceSummaryScope.subject)
        'Counted from ${s.lessonsLooked} lessons of this course in your '
            'timetable (lessons a substitute held included).',
      if (s.lessonsSkipped > 0)
        '${s.lessonsSkipped} lessons had no class register data '
            '(e.g. held by a substitute) and are not counted.',
      if (s.truncated) 'Only the latest $maxSummaryWeeks weeks were looked at.',
      if (s.approximate)
        'All subjects: lessons are counted from the time grid, so they are '
            'approximate.',
    ];
    return [
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(n, style: muted),
        ),
      const SizedBox(height: 8),
    ];
  }

  static String _counts(
    int lessons,
    int excused,
    int unexcused,
    int open,
    int late,
  ) => [
    '$lessons ${lessons == 1 ? 'lesson' : 'lessons'}',
    if (excused > 0) '$excused excused',
    if (unexcused > 0) '$unexcused unexcused',
    if (open > 0) '$open open',
    if (late > 0) '$late late',
  ].join(' · ');

  Widget _classTotals(ThemeData theme, AbsenceSummary s) {
    Widget row(String label, String value, {Key? key}) => ListTile(
      key: key,
      dense: !isLargeText(context),
      title: Text(label),
      trailing: Text(value, style: theme.textTheme.titleMedium),
    );
    return Column(
      key: const ValueKey('summary-class'),
      children: [
        row(
          'Absent lessons',
          '${s.lessons}',
          key: const ValueKey('summary-class-lessons'),
        ),
        row('Excused', '${s.excusedLessons}'),
        row('Unexcused', '${s.unexcusedLessons}'),
        row('Open (not decided yet)', '${s.openLessons}'),
        row(
          'Late arrivals',
          '${s.lateCount}',
          key: const ValueKey('summary-class-late'),
        ),
        row(
          'Pupils with absences',
          '${s.pupilsWithAbsences} of ${s.pupils.length}',
        ),
      ],
    );
  }

  Widget _pupilTile(ThemeData theme, AbsenceSummary s, PupilAbsenceSummary p) {
    final large = isLargeText(context);
    return ListTile(
      key: ValueKey('summary-pupil-${p.studentId ?? p.name}'),
      title: Text(p.name),
      subtitle: Text(
        p.hasAbsences
            ? _counts(
                p.lessons,
                p.excusedLessons,
                p.unexcusedLessons,
                p.openLessons,
                p.lateCount,
              )
            : 'No absences',
      ),
      trailing: large
          ? null
          : Text(
              '${p.lessons}',
              style: theme.textTheme.titleLarge?.copyWith(
                color: p.unexcusedLessons > 0 ? theme.colorScheme.error : null,
              ),
            ),
      onTap: p.hasAbsences
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PupilAbsencesScreen(summary: s, pupil: p),
              ),
            )
          : null,
    );
  }
}

/// The absences of one pupil in a summary, newest first.
class PupilAbsencesScreen extends StatelessWidget {
  const PupilAbsencesScreen({
    super.key,
    required this.summary,
    required this.pupil,
  });

  final AbsenceSummary summary;
  final PupilAbsenceSummary pupil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = dateFormat(context, 'EEE d MMM yyyy');
    String time(DateTime d) => hhmm(minuteOfDay(d));
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pupil.name),
            Text(summary.scope.label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              _AbsenceSummaryScreenState._counts(
                pupil.lessons,
                pupil.excusedLessons,
                pupil.unexcusedLessons,
                pupil.openLessons,
                pupil.lateCount,
              ),
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final a in pupil.absences)
            ListTile(
              title: Text(
                [
                  day.format(a.start),
                  if (a.label.isNotEmpty) a.label,
                ].join(' · '),
              ),
              subtitle: Text(
                [
                  [
                    _sameDay(a.start, a.end)
                        ? '${time(a.start)} – ${time(a.end)}'
                        : '${time(a.start)} – ${day.format(a.end)} ${time(a.end)}',
                    if (a.late)
                      'late'
                    else
                      '${a.lessons} ${a.lessons == 1 ? 'lesson' : 'lessons'}',
                    a.state.label,
                  ].join(' · '),
                  if (a.reason.isNotEmpty) a.reason,
                  if (a.text.isNotEmpty) a.text,
                ].join('\n'),
              ),
            ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// A segmented switch; with large text a wrapping row of chips instead, so
/// the labels are never squeezed.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.keyPrefix,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    String name(T v) => v is Enum ? v.name : '$v';
    if (isLargeText(context)) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in values)
            ChoiceChip(
              key: ValueKey('$keyPrefix-${name(v)}'),
              label: Text(label(v)),
              selected: v == selected,
              onSelected: (_) => onSelected(v),
            ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final v in values)
            ButtonSegment(
              value: v,
              label: Text(
                label(v),
                key: ValueKey('$keyPrefix-${name(v)}'),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onSelected(s.first),
      ),
    );
  }
}
