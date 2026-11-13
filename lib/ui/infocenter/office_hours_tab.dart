import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/models.dart';
import '../timetable/timetable_utils.dart';
import 'info_common.dart';
import 'info_providers.dart';
import '../common/search_field.dart';

/// Office hours of the next 2 weeks, grouped by teacher (A–Z), each
/// teacher's slots by time. All teachers by default; a chip narrows the list
/// to the teachers of the account's class.
class OfficeHoursTab extends ConsumerStatefulWidget {
  const OfficeHoursTab({super.key, required this.account});
  final Account account;

  @override
  ConsumerState<OfficeHoursTab> createState() => _OfficeHoursTabState();
}

/// Sort key for teacher names: case-insensitive, umlauts next to their base
/// letter, blank names last.
String teacherSortKey(String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return '\u{FFFF}';
  const map = {'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss', 'é': 'e', 'è': 'e'};
  return n.split('').map((c) => map[c] ?? c).join();
}

/// One teacher's office hours in [groupByTeacher].
class TeacherOfficeHours {
  const TeacherOfficeHours(this.key, this.name, this.items, {this.detail = ''});

  /// What the group was built from (see [officeHourTeacherKey]).
  final String key;

  /// Display name, possibly blank.
  final String name;

  /// Shown next to [name] only when another group has the same name (e.g.
  /// two teachers sent as just "Müller"): their email, else their rooms.
  final String detail;
  final List<OfficeHourItem> items;

  String get title {
    final n = name.isEmpty ? 'Teacher' : name;
    return detail.isEmpty ? n : '$n · $detail';
  }
}

/// Which teacher [o] belongs to. Names aren't unique (some schools send only
/// last names), so this is the teacher id when there is one, else the name
/// plus email and phone. A bare one-word name without either also takes the
/// rooms, so two "Müller"s in different rooms stay apart.
String officeHourTeacherKey(OfficeHourItem o) {
  if (o.teacherId > 0) return 'id:${o.teacherId}';
  final name = o.teacherName.trim().toLowerCase();
  final email = o.email.trim().toLowerCase();
  final phone = o.phone.replaceAll(RegExp(r'[^0-9+]'), '');
  final bare = !name.contains(RegExp(r'\s')) && email.isEmpty && phone.isEmpty;
  final rooms = bare ? o.rooms.trim().toLowerCase() : '';
  return 'name:$name|$email|$phone|$rooms';
}

/// [items] grouped by teacher ([officeHourTeacherKey]), groups sorted
/// alphabetically and each group by start time.
List<TeacherOfficeHours> groupByTeacher(Iterable<OfficeHourItem> items) {
  final byKey = groupBy(items, officeHourTeacherKey);
  final nameCount = <String, int>{};
  for (final l in byKey.values) {
    final n = l.first.teacherName.trim();
    nameCount[n] = (nameCount[n] ?? 0) + 1;
  }
  final groups = <TeacherOfficeHours>[];
  for (final MapEntry(:key, value: list) in byKey.entries) {
    final name = list.first.teacherName.trim();
    var detail = '';
    if ((nameCount[name] ?? 0) > 1) {
      final email = list
          .map((o) => o.email.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      detail = email.isNotEmpty
          ? email
          : {for (final o in list) o.rooms.trim()}
                .where((r) => r.isNotEmpty)
                .join(', ');
    }
    list.sort((a, b) => a.start.compareTo(b.start));
    groups.add(TeacherOfficeHours(key, name, list, detail: detail));
  }
  groups.sort((a, b) {
    var c = teacherSortKey(a.name).compareTo(teacherSortKey(b.name));
    if (c == 0) c = a.name.compareTo(b.name);
    if (c == 0) c = a.detail.compareTo(b.detail);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return groups;
}

/// Whether [o] matches the search [query] (case-insensitive, already
/// lower-cased and trimmed): teacher name, rooms or email contain it.
bool officeHourMatches(OfficeHourItem o, String query) =>
    query.isEmpty ||
    o.teacherName.toLowerCase().contains(query) ||
    o.rooms.toLowerCase().contains(query) ||
    o.email.toLowerCase().contains(query);

class _OfficeHoursTabState extends ConsumerState<OfficeHoursTab> {
  bool _onlyMine = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dateOnly(now);
    final until = addDays(today, 14);
    final q = InfoQuery(widget.account, start: today, onlyMine: _onlyMine);
    final p = officeHoursProvider(q);
    final value = ref.watch(p);

    List<OfficeHourItem> inRange(List<OfficeHourItem> l) => [
      for (final o in l)
        if (!o.end.isBefore(now) && o.start.isBefore(until)) o,
    ];
    List<OfficeHourItem> shown(List<OfficeHourItem> l) => [
      for (final o in inRange(l))
        if (officeHourMatches(o, _query)) o,
    ];

    final filter = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            fieldKey: const ValueKey('officehours-search'),
            hintText: 'Search teachers or rooms',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          FilterChip(
            key: const ValueKey('officehours-only-mine'),
            label: const Text('Only my class'),
            selected: _onlyMine,
            onSelected: (v) => setState(() => _onlyMine = v),
          ),
        ],
      ),
    );

    return CachedListView<List<OfficeHourItem>>(
      value: value,
      onRefresh: () => forceRefresh(ref, #officeHours, p, q),
      errorTitle: 'Could not load office hours',
      header: filter,
      isEmpty: (l) => shown(l).isEmpty,
      empty: _query.isNotEmpty
          ? const InfoEmptyState(
              icon: Icons.search_off,
              title: 'No matches',
              message: 'No teacher or room matches your search.',
            )
          : InfoEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No office hours',
              message: _onlyMine
                  ? 'None for your class in the next two weeks.'
                  : 'None in the next two weeks.',
            ),
      builder: (context, items) => [
        for (final g in groupByTeacher(shown(items))) ...[
          SliverToBoxAdapter(child: InfoSectionHeader(g.title)),
          SliverList.list(
            children: [
              for (final o in g.items)
                OfficeHourCard(item: o, showTeacher: false, now: now),
            ],
          ),
        ],
      ],
    );
  }
}

class OfficeHourCard extends ConsumerWidget {
  const OfficeHourCard({
    super.key,
    required this.item,
    this.showTeacher = true,
    this.now,
  });
  final OfficeHourItem item;

  /// Title is the teacher; when false (list grouped by teacher) the title is
  /// the day instead.
  final bool showTeacher;
  final DateTime? now;

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
              showTeacher
                  ? (o.teacherName.trim().isEmpty ? 'Teacher' : o.teacherName.trim())
                  : formatDay(context, dateOnly(o.start), now ?? DateTime.now()),
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
