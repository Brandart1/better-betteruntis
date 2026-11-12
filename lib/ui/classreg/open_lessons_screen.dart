import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'class_register_screen.dart';

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

/// "Mon 3 Nov · 08:00 – 08:45 · 5a".
String classRegLessonSubtitle(
  BuildContext context,
  DateTime start,
  DateTime end,
  Period p,
  NameResolver? names,
) => [
  dateFormat(context, 'EEE d MMM').format(start),
  '${hhmm(minuteOfDay(start))} – ${hhmm(minuteOfDay(end))}',
  if (names != null)
    ...p
        .ofType(ElementType.klasse)
        .where((k) => k.id != 0)
        .map(names.shortName),
].join(' · ');

/// Range options of [OpenLessonsScreen], in days.
const openLessonRanges = [7, 14, 30];

final _openLessonsProvider = FutureProvider.autoDispose
    .family<List<OpenLesson>, ({Account account, int days})>(
      (ref, q) => ref
          .watch(classRegisterRepositoryProvider)
          .openLessons(q.account, days: q.days),
      retry: (_, _) => null,
    );

/// The teacher's past lessons whose attendance check or topic is missing.
class OpenLessonsScreen extends ConsumerStatefulWidget {
  const OpenLessonsScreen({super.key});

  @override
  ConsumerState<OpenLessonsScreen> createState() => _OpenLessonsScreenState();
}

class _OpenLessonsScreenState extends ConsumerState<OpenLessonsScreen> {
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final names = ref.watch(nameResolverProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open lessons'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Time range',
            icon: const Icon(Icons.date_range_outlined),
            initialValue: _days,
            onSelected: (d) => setState(() => _days = d),
            itemBuilder: (_) => [
              for (final d in openLessonRanges)
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
          : _list(account, names),
    );
  }

  Widget _list(Account account, NameResolver? names) {
    final q = (account: account, days: _days);
    final async = ref.watch(_openLessonsProvider(q));
    Future<void> reload() => ref.refresh(_openLessonsProvider(q).future);
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
        onRefresh: reload,
        child: lessons.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.task_alt, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Everything entered for the last $_days days.',
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${lessons.length} lessons of the last $_days days '
                      'miss the attendance check or the topic.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  for (final l in lessons) _tile(account, names, l, reload),
                ],
              ),
      ),
    );
  }

  Widget _tile(
    Account account,
    NameResolver? names,
    OpenLesson l,
    Future<void> Function() reload,
  ) {
    final p = l.period;
    final title = classRegLessonTitle(p, names);
    final subtitle = classRegLessonSubtitle(context, p.start, p.end, p, names);
    final missing = [
      if (!l.register.absenceChecked) 'attendance',
      if (!l.register.hasTopic) 'topic',
    ];
    return ListTile(
      key: ValueKey('open-lesson-${p.id}'),
      leading: const Icon(Icons.pending_actions_outlined),
      title: Text(title),
      subtitle: Text('$subtitle\nMissing: ${missing.join(', ')}'),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final saved = await openClassRegister(
          context,
          account: account,
          periods: [p],
          title: title,
          subtitle: subtitle,
        );
        if (saved && mounted) await reload();
      },
    );
  }
}
