import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/models.dart';
import '../timetable/timetable_utils.dart';
import 'absence_report_screen.dart';
import 'info_common.dart';
import 'info_providers.dart';

enum AbsenceRange {
  schoolYear('School year', null),
  days7('7 days', 7),
  days14('14 days', 14),
  days30('30 days', 30),
  days90('90 days', 90);

  const AbsenceRange(this.label, this.days);
  final String label;
  final int? days;
}

/// Start of the current school year: Sep 1 of this year, or of last year
/// before September. (The master-data school years aren't exposed to the UI.)
DateTime schoolYearStart(DateTime now) =>
    DateTime(now.month >= 9 ? now.year : now.year - 1, 9, 1);

class AbsenceFilter {
  const AbsenceFilter({
    this.onlyUnexcused = false,
    this.reverse = false,
    this.range = AbsenceRange.schoolYear,
  });

  final bool onlyUnexcused;

  /// Oldest first instead of newest first.
  final bool reverse;
  final AbsenceRange range;

  AbsenceFilter copyWith({bool? onlyUnexcused, bool? reverse, AbsenceRange? range}) =>
      AbsenceFilter(
        onlyUnexcused: onlyUnexcused ?? this.onlyUnexcused,
        reverse: reverse ?? this.reverse,
        range: range ?? this.range,
      );

  (DateTime, DateTime) dates(DateTime now) {
    final today = dateOnly(now);
    final days = range.days;
    return (days == null ? schoolYearStart(now) : addDays(today, -days), today);
  }

  List<AbsenceItem> apply(List<AbsenceItem> items) {
    final out = [
      for (final a in items)
        if (!onlyUnexcused || !a.excused) a,
    ]..sort((a, b) => reverse ? a.start.compareTo(b.start) : b.start.compareTo(a.start));
    return out;
  }
}

final absenceFilterProvider =
    NotifierProvider<SessionValue<AbsenceFilter>, AbsenceFilter>(
      () => SessionValue(const AbsenceFilter()),
    );

/// Summary over all absences in the range (independent of the toggles).
({int total, int unexcused, double hours}) absenceSummary(List<AbsenceItem> items) {
  var minutes = 0;
  for (final a in items) {
    final m = a.end.difference(a.start).inMinutes;
    if (m > 0) minutes += m;
  }
  return (
    total: items.length,
    unexcused: items.where((a) => !a.excused).length,
    hours: minutes / 60,
  );
}

String formatHours(double h) =>
    h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';

class AbsencesTab extends ConsumerWidget {
  const AbsencesTab({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final filter = ref.watch(absenceFilterProvider);
    final (start, end) = filter.dates(now);
    final q = InfoQuery(account, start: start, end: end);
    final p = absencesProvider(q);
    final value = ref.watch(p);
    final notifier = ref.read(absenceFilterProvider.notifier);

    final header = Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kInfoMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                key: const ValueKey('absences-only-unexcused'),
                label: const Text('Only unexcused'),
                selected: filter.onlyUnexcused,
                onSelected: (v) => notifier.set(filter.copyWith(onlyUnexcused: v)),
              ),
              FilterChip(
                key: const ValueKey('absences-reverse'),
                avatar: Icon(filter.reverse ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
                showCheckmark: false,
                label: Text(filter.reverse ? 'Oldest first' : 'Newest first'),
                selected: filter.reverse,
                onSelected: (v) => notifier.set(filter.copyWith(reverse: v)),
              ),
              PopupMenuButton<AbsenceRange>(
                key: const ValueKey('absences-range'),
                tooltip: 'Time range',
                initialValue: filter.range,
                onSelected: (r) => notifier.set(filter.copyWith(range: r)),
                itemBuilder: (_) => [
                  for (final r in AbsenceRange.values)
                    PopupMenuItem(value: r, child: Text(r.label)),
                ],
                child: IgnorePointer(
                  child: FilterChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    showCheckmark: false,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(filter.range.label), const Icon(Icons.arrow_drop_down, size: 18)],
                    ),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return CachedListView<List<AbsenceItem>>(
      value: value,
      onRefresh: () => forceRefresh(ref, #absences, p, q),
      errorTitle: 'Could not load absences',
      header: header,
      isEmpty: (l) => l.isEmpty,
      empty: const InfoEmptyState(
        icon: Icons.verified_outlined,
        title: 'No absences',
        message: 'Nothing recorded in this time range.',
      ),
      builder: (context, items) {
        final summary = absenceSummary(items);
        final shown = filter.apply(items);
        return [
          SliverToBoxAdapter(child: _SummaryCard(summary: summary)),
          if (shown.isEmpty)
            const SliverToBoxAdapter(
              child: InfoEmptyState(
                icon: Icons.thumb_up_alt_outlined,
                title: 'No unexcused absences',
              ),
            )
          else
            SliverList.list(children: [for (final a in shown) AbsenceCard(absence: a, now: now)]),
          // Room for the "Report absence" button of parent accounts.
          if (canReportAbsences(account))
            const SliverToBoxAdapter(child: SizedBox(height: 72)),
        ];
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final ({int total, int unexcused, double hours}) summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget stat(String key, String value, String label, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            key: ValueKey('absences-summary-$key'),
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
          Text(label, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
        ],
      ),
    );
    return Card.filled(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            stat('total', '${summary.total}', 'Absences'),
            stat(
              'unexcused',
              '${summary.unexcused}',
              'Unexcused',
              color: summary.unexcused > 0 ? cs.error : null,
            ),
            stat('hours', formatHours(summary.hours), 'Total'),
          ],
        ),
      ),
    );
  }
}

class AbsenceCard extends StatelessWidget {
  const AbsenceCard({super.key, required this.absence, required this.now});
  final AbsenceItem absence;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = absence;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ok = successColors(context);
    final singleDay = sameDay(a.start, a.end);
    final dateFmt = dateFormat(context, a.start.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy');
    final time = dateFormat(context, 'HH:mm');
    final when = singleDay
        ? '${dateFmt.format(a.start)} · ${formatTimeRange(context, a.start, a.end)}'
        : '${dateFmt.format(a.start)} ${time.format(a.start)} – ${dateFmt.format(a.end)} ${time.format(a.end)}';
    return Card.outlined(
      key: ValueKey('absence-${a.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(when, style: theme.textTheme.titleSmall)),
                  a.excused
                    ? InfoChip('Excused', icon: Icons.check, background: ok.bg, foreground: ok.fg)
                    : InfoChip(
                        'Unexcused',
                        icon: Icons.priority_high,
                        background: cs.errorContainer,
                        foreground: cs.onErrorContainer,
                      ),
              ],
            ),
            if (a.reason.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(a.reason.trim(), style: theme.textTheme.bodyMedium),
              ),
            if (a.excuseStatus.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Excuse: ${a.excuseStatus.trim()}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            if (a.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(a.text.trim(), style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
