import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'info_common.dart';
import 'info_providers.dart';

/// Upcoming exams (next 8 weeks) and a collapsible "Past" section (last 8
/// weeks).
class ExamsTab extends ConsumerStatefulWidget {
  const ExamsTab({super.key, required this.account});
  final Account account;

  @override
  ConsumerState<ExamsTab> createState() => _ExamsTabState();
}

class _ExamsTabState extends ConsumerState<ExamsTab> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dateOnly(now);
    final upQ = InfoQuery(widget.account, start: today, end: addDays(today, 56));
    final pastQ = InfoQuery(widget.account, start: addDays(today, -56), end: today);
    final upP = examsProvider(upQ);
    final pastP = examsProvider(pastQ);
    final up = ref.watch(upP);
    final past = ref.watch(pastP);
    final names = ref.watch(nameResolverProvider).value;

    Future<void> refresh() => Future.wait([
      forceRefresh(ref, #exams, upP, upQ),
      forceRefresh(ref, #exams, pastP, pastQ),
    ]);

    final upcoming = [
      for (final e in up.value?.data ?? const <ExamItem>[])
        if (!e.end.isBefore(now)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final pastItems = [
      for (final e in past.value?.data ?? const <ExamItem>[])
        if (e.end.isBefore(now)) e,
    ]..sort((a, b) => b.start.compareTo(a.start));
    final pastStatus = InfoStatus.of(past);

    return CachedListView<List<ExamItem>>(
      value: up,
      onRefresh: refresh,
      errorTitle: 'Could not load exams',
      extraStatuses: [pastStatus],
      // Never "empty": the past section is always offered.
      isEmpty: (_) => false,
      empty: const SizedBox.shrink(),
      builder: (context, _) => [
        if (upcoming.isEmpty)
          const SliverToBoxAdapter(
            child: InfoEmptyState(
              icon: Icons.event_available,
              title: 'No upcoming exams',
              message: 'Nothing scheduled in the next 8 weeks.',
            ),
          )
        else ...[
          const SliverToBoxAdapter(child: InfoSectionHeader('Upcoming')),
          SliverList.list(
            children: [
              for (final e in upcoming) ExamCard(exam: e, names: names, now: now),
            ],
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ListTile(
              key: const ValueKey('exams-past-toggle'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                pastStatus.hasData ? 'Past (${pastItems.length})' : 'Past',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              trailing: Icon(_showPast ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _showPast = !_showPast),
            ),
          ),
        ),
        if (_showPast)
          if (!pastStatus.hasData)
            SliverToBoxAdapter(
              child: pastStatus.failed
                  ? ListTile(
                      title: const Text('Could not load past exams'),
                      subtitle: Text(describeInfoError(pastStatus.error)),
                      trailing: TextButton(
                        onPressed: () => forceRefresh(ref, #exams, pastP, pastQ),
                        child: const Text('Retry'),
                      ),
                    )
                  : const InfoSkeleton(count: 2, shrinkWrap: true),
            )
          else if (pastItems.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('No exams in the past 8 weeks.'),
              ),
            )
          else
            SliverList.list(
              children: [
                for (final e in pastItems)
                  ExamCard(exam: e, names: names, now: now, past: true),
              ],
            ),
      ],
    );
  }
}

/// "today", "tomorrow", "in 3 days", "in 2 weeks".
String examCountdown(DateTime start, DateTime now) {
  final d = daysUntil(start, now);
  if (d <= 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  if (d < 14) return 'in $d days';
  return 'in ${(d / 7).round()} weeks';
}

class ExamCard extends StatelessWidget {
  const ExamCard({
    super.key,
    required this.exam,
    required this.names,
    required this.now,
    this.past = false,
  });

  final ExamItem exam;
  final NameResolver? names;
  final DateTime now;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final e = exam;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subject = e.subjectId == null
        ? null
        : resolveName(names, ElementType.subject, e.subjectId!);
    final title = [
      ?subject,
      if (e.name.trim().isNotEmpty && e.name.trim() != subject) e.name.trim(),
    ];
    final rooms = resolveNames(names, ElementType.room, e.roomIds, long: false);
    final teachers = resolveNames(names, ElementType.teacher, e.teacherIds);
    final classes = resolveNames(names, ElementType.klasse, e.klassenIds, long: false);
    final soon = !past && daysUntil(e.start, now) <= 2;
    final muted = past ? cs.onSurfaceVariant : null;

    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );

    final sameDayEnd = sameDay(e.start, e.end);
    final when = sameDayEnd
        ? '${formatDay(context, e.start, now)} · ${formatTimeRange(context, e.start, e.end)}'
        : '${formatDay(context, e.start, now)} ${dateFormat(context, 'HH:mm').format(e.start)} – '
              '${formatDay(context, e.end, now)} ${dateFormat(context, 'HH:mm').format(e.end)}';

    return Card.outlined(
      key: ValueKey('exam-${e.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateBadge(date: e.start, past: past),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? 'Exam' : title.join(' · '),
                          style: theme.textTheme.titleSmall?.copyWith(color: muted),
                        ),
                      ),
                      if (!past)
                        InfoChip(
                          examCountdown(e.start, now),
                          icon: Icons.schedule,
                          background: soon ? cs.tertiaryContainer : null,
                          foreground: soon ? cs.onTertiaryContainer : null,
                        ),
                    ],
                  ),
                  if (e.examType.trim().isNotEmpty)
                    Text(
                      e.examType.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  line(Icons.access_time, when),
                  if (rooms.isNotEmpty) line(Icons.room_outlined, rooms.join(', ')),
                  if (teachers.isNotEmpty) line(Icons.person_outline, teachers.join(', ')),
                  if (classes.isNotEmpty) line(Icons.groups_outlined, classes.join(', ')),
                  if (e.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(e.text.trim(), style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date, required this.past});
  final DateTime date;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = past ? cs.surfaceContainerHighest : cs.primaryContainer;
    final fg = past ? cs.onSurfaceVariant : cs.onPrimaryContainer;
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(
            dateFormat(context, 'MMM').format(date).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
          Text(
            '${date.day}',
            style: theme.textTheme.titleLarge?.copyWith(color: fg, height: 1.1),
          ),
          Text(
            dateFormat(context, 'EEE').format(date),
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
