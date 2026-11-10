import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'info_common.dart';
import 'info_providers.dart';

enum HomeworkRange {
  thisWeek('This week'),
  next2Weeks('Next 2 weeks'),
  past4Weeks('Past 4 weeks');

  const HomeworkRange(this.label);
  final String label;

  /// Inclusive date range relative to [now].
  (DateTime, DateTime) dates(DateTime now) {
    final today = dateOnly(now);
    return switch (this) {
      thisWeek => (mondayOf(today), addDays(mondayOf(today), 6)),
      next2Weeks => (today, addDays(today, 13)),
      past4Weeks => (addDays(today, -28), today),
    };
  }
}

final homeworkRangeProvider =
    NotifierProvider<SessionValue<HomeworkRange>, HomeworkRange>(
      () => SessionValue(HomeworkRange.thisWeek),
    );

class HomeworkTab extends ConsumerWidget {
  const HomeworkTab({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final range = ref.watch(homeworkRangeProvider);
    final (start, end) = range.dates(now);
    final q = InfoQuery(account, start: start, end: end);
    final p = homeworkProvider(q);
    final value = ref.watch(p);
    final names = ref.watch(nameResolverProvider).value;

    return CachedListView<List<HomeworkItem>>(
      value: value,
      onRefresh: () => forceRefresh(ref, #homework, p, q),
      errorTitle: 'Could not load homework',
      header: _RangeChips(
        selected: range,
        onSelected: (r) => ref.read(homeworkRangeProvider.notifier).set(r),
      ),
      isEmpty: (l) => l.isEmpty,
      empty: InfoEmptyState(
        icon: Icons.task_alt,
        title: range == HomeworkRange.past4Weeks ? 'No homework' : 'No homework 🎉',
        message: switch (range) {
          HomeworkRange.thisWeek => 'Nothing is due this week.',
          HomeworkRange.next2Weeks => 'Nothing is due in the next two weeks.',
          HomeworkRange.past4Weeks => 'No homework in the past four weeks.',
        },
      ),
      builder: (context, items) {
        final groups = groupBy(items, (HomeworkItem h) => dateOnly(h.dueOn));
        final days = groups.keys.toList()..sort();
        final ordered = range == HomeworkRange.past4Weeks ? days.reversed : days;
        return [
          for (final day in ordered) ...[
            SliverToBoxAdapter(
              child: InfoSectionHeader(
                homeworkDueLabel(context, day, now),
                color: day.isBefore(dateOnly(now)) &&
                        groups[day]!.any((h) => !h.completed)
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            SliverList.list(
              children: [
                for (final h in groups[day]!) HomeworkCard(item: h, names: names, now: now),
              ],
            ),
          ],
        ];
      },
    );
  }
}

/// "Due today", "Due tomorrow", "Was due yesterday", "Due Fri, 14 Nov".
String homeworkDueLabel(BuildContext context, DateTime day, DateTime now) {
  final d = daysUntil(day, now);
  if (d == 0) return 'Due today';
  if (d == 1) return 'Due tomorrow';
  if (d == -1) return 'Was due yesterday';
  final label = formatDay(context, day, now);
  return d < 0 ? 'Was due $label' : 'Due $label';
}

bool isOverdue(HomeworkItem h, DateTime now) =>
    !h.completed && dateOnly(h.dueOn).isBefore(dateOnly(now));

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.selected, required this.onSelected});
  final HomeworkRange selected;
  final ValueChanged<HomeworkRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kInfoMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in HomeworkRange.values)
                ChoiceChip(
                  label: Text(r.label),
                  showCheckmark: false,
                  selected: r == selected,
                  onSelected: (_) => onSelected(r),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeworkCard extends StatelessWidget {
  const HomeworkCard({
    super.key,
    required this.item,
    required this.names,
    required this.now,
  });

  final HomeworkItem item;
  final NameResolver? names;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final h = item;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overdue = isOverdue(h, now);
    final subject = h.subjectId == null
        ? null
        : resolveName(names, ElementType.subject, h.subjectId!);
    final teachers = resolveNames(names, ElementType.teacher, h.teacherIds);
    final fg = overdue ? cs.onErrorContainer : null;
    return Card.outlined(
      key: ValueKey('homework-${h.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: overdue ? cs.errorContainer : null,
      shape: overdue
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.error),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  h.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: h.completed ? cs.primary : (fg ?? cs.outline),
                  semanticLabel: h.completed ? 'Completed' : 'Not completed',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subject ?? 'Homework',
                    style: theme.textTheme.titleSmall?.copyWith(color: fg),
                  ),
                ),
                if (overdue)
                  InfoChip(
                    'Overdue',
                    icon: Icons.warning_amber_rounded,
                    background: cs.error,
                    foreground: cs.onError,
                  )
                else if (h.completed)
                  const InfoChip('Done'),
              ],
            ),
            if (teachers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(
                  teachers.join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fg ?? cs.onSurfaceVariant,
                  ),
                ),
              ),
            if (h.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 6),
                child: Text(
                  h.text.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    decoration: h.completed ? TextDecoration.lineThrough : null,
                    decorationColor: cs.outline,
                  ),
                ),
              ),
            if (h.remark.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(
                  h.remark.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: fg ?? cs.onSurfaceVariant,
                  ),
                ),
              ),
            if (h.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: AttachmentList(h.attachments),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
