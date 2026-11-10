import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/models.dart';
import '../timetable/timetable_utils.dart';
import 'info_common.dart';
import 'info_providers.dart';

/// Office hours of the next 2 weeks, grouped by day.
class OfficeHoursTab extends ConsumerWidget {
  const OfficeHoursTab({super.key, required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = dateOnly(now);
    final until = addDays(today, 14);
    final q = InfoQuery(account, start: today);
    final p = officeHoursProvider(q);
    final value = ref.watch(p);

    List<OfficeHourItem> inRange(List<OfficeHourItem> l) => [
      for (final o in l)
        if (!o.end.isBefore(now) && o.start.isBefore(until)) o,
    ]..sort((a, b) => a.start.compareTo(b.start));

    return CachedListView<List<OfficeHourItem>>(
      value: value,
      onRefresh: () => forceRefresh(ref, #officeHours, p, q),
      errorTitle: 'Could not load office hours',
      isEmpty: (l) => inRange(l).isEmpty,
      empty: const InfoEmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No office hours',
        message: 'None in the next two weeks.',
      ),
      builder: (context, items) {
        final groups = groupBy(inRange(items), (OfficeHourItem o) => dateOnly(o.start));
        return [
          for (final MapEntry(key: day, value: list) in groups.entries) ...[
            SliverToBoxAdapter(child: InfoSectionHeader(formatDay(context, day, now))),
            SliverList.list(children: [for (final o in list) OfficeHourCard(item: o)]),
          ],
        ];
      },
    );
  }
}

class OfficeHourCard extends ConsumerWidget {
  const OfficeHourCard({super.key, required this.item});
  final OfficeHourItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = item;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ok = successColors(context);
    final email = o.email.trim();
    final phone = o.phone.trim();
    return Card.outlined(
      key: ValueKey('officehour-${o.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o.teacherName.trim().isEmpty ? 'Teacher' : o.teacherName.trim(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(formatTimeRange(context, o.start, o.end), style: theme.textTheme.bodySmall),
                if (o.rooms.trim().isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.room_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(child: Text(o.rooms.trim(), style: theme.textTheme.bodySmall)),
                ],
              ],
            ),
            if (o.registered || o.registrationPossible)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: o.registered
                    ? InfoChip('Registered', icon: Icons.how_to_reg, background: ok.bg, foreground: ok.fg)
                    : const InfoChip('Registration possible', icon: Icons.edit_calendar_outlined),
              ),
            if (email.isNotEmpty || phone.isNotEmpty)
              Wrap(
                spacing: 4,
                children: [
                  if (email.isNotEmpty)
                    TextButton.icon(
                      key: ValueKey('officehour-${o.id}-email'),
                      onPressed: () => openLink(context, ref, 'mailto:$email'),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: Text(email),
                    ),
                  if (phone.isNotEmpty)
                    TextButton.icon(
                      key: ValueKey('officehour-${o.id}-phone'),
                      onPressed: () =>
                          openLink(context, ref, 'tel:${phone.replaceAll(RegExp(r'[^0-9+]'), '')}'),
                      icon: const Icon(Icons.phone_outlined, size: 18),
                      label: Text(phone),
                    ),
                ],
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
