import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/absence_summary.dart';
import '../../core/class_lead.dart';
import '../../core/class_register.dart';
import '../../core/excuses.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'absence_summary_screen.dart';
import 'excuses_screen.dart';

/// "My class" in the drawer for class teachers: per own class the open
/// absences (tap to excuse), the pupils absent most often, the class
/// register entries of the range, and links to the Excuses screen, the
/// class timetable and the absence summary.
class ClassLeadScreen extends ConsumerStatefulWidget {
  const ClassLeadScreen({super.key});

  @override
  ConsumerState<ClassLeadScreen> createState() => _ClassLeadScreenState();
}

class _ClassLeadScreenState extends ConsumerState<ClassLeadScreen> {
  List<ExcuseClass>? _classes;
  ExcuseClass? _class;
  ExcuseRange _range = ExcuseRange.last14;

  ClassLeadDashboard? _data;
  Object? _error;

  bool _allOpen = false;
  bool _allEvents = false;

  /// Only the latest load may set state.
  int _generation = 0;
  String? _accountId;

  static const _shown = 5;

  ClassLeadRepository get _repo => ref.read(classLeadRepositoryProvider);

  Future<void> _load(Account account) async {
    final gen = ++_generation;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final classes = _classes ?? await _repo.classes(account);
      if (!mounted || gen != _generation) return;
      final klasse =
          classes.where((c) => c.id == _class?.id).firstOrNull ??
          classes.firstOrNull;
      setState(() {
        _classes = classes;
        _class = klasse;
      });
      if (klasse == null) return;
      final data = await _repo.dashboard(account, klasse, range: _range);
      if (mounted && gen == _generation) setState(() => _data = data);
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  static String _message(Object e) =>
      e is UntisException ? e.message : e.toString();

  Future<void> _excuse(Account account, ExcuseAbsence a) async {
    final data = _data;
    if (data == null) return;
    final saved = await showModalBottomSheet<ExcuseAbsence>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExcuseSheet(
        account: account,
        meta: data.meta,
        absence: a,
        repository: ref.read(excuseRepositoryProvider),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _data = _data?.withAbsence(saved));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved: ${saved.studentName.isEmpty ? 'absence' : saved.studentName}'
          ' – ${saved.status?.name ?? saved.type.label}.',
        ),
      ),
    );
  }

  void _openSummary(Account account, ExcuseClass klasse) {
    final now = DateTime.now();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AbsenceSummaryScreen(
          account: account,
          // No lesson: the whole class (see AbsenceSummaryRepositoryImpl).
          periods: [
            Period(
              id: 0,
              lessonId: 0,
              start: now,
              end: now,
              elements: [
                ElementRef(type: ElementType.klasse, id: klasse.id, orgId: 0),
              ],
              flags: const {},
            ),
          ],
          title: klasse.name,
          initialScope: AbsenceSummaryScope.all,
          scopes: const [AbsenceSummaryScope.all],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final teacher = account != null && hasClassRegister(account);
    if (teacher && account.id != _accountId) {
      _accountId = account.id;
      _classes = null;
      _class = null;
      _data = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(account);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My class'),
        actions: [
          if (teacher)
            IconButton(
              key: const ValueKey('classlead-refresh'),
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(account),
            ),
        ],
      ),
      body: !teacher
          ? _note('Only teacher accounts have a class overview.')
          : RefreshIndicator(
              onRefresh: () => _load(account),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: _body(context, account),
              ),
            ),
    );
  }

  Widget _note(String text, {Key? key}) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(text, key: key, textAlign: TextAlign.center),
    ),
  );

  List<Widget> _body(BuildContext context, Account account) {
    final classes = _classes;
    final error = _error;
    if (error != null && classes == null) {
      return [_errorView(error, account)];
    }
    if (classes == null) return [_progress()];
    final klasse = _class;
    if (klasse == null) {
      return [
        _note(
          'Your school does not list you as the class teacher of a class. '
          'The Excuses screen shows the absences of every class you may see.',
          key: const ValueKey('classlead-none'),
        ),
      ];
    }
    final data = _data;
    return [
      _controls(context, account, classes, klasse),
      if (error != null)
        _errorView(error, account)
      else if (data == null)
        _progress()
      else ...[
        ..._openSection(context, account, data),
        ..._pupilSection(context, data),
        ..._eventSection(context, data),
      ],
    ];
  }

  Widget _progress() => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator()),
  );

  Widget _errorView(Object error, Account account) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Text(
          _message(error),
          key: const ValueKey('classlead-error'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _load(account),
          child: const Text('Try again'),
        ),
      ],
    ),
  );

  Widget _controls(
    BuildContext context,
    Account account,
    List<ExcuseClass> classes,
    ExcuseClass klasse,
  ) {
    final theme = Theme.of(context);
    final data = _data;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (classes.length > 1)
                DropdownButton<int>(
                  key: const ValueKey('classlead-class'),
                  value: klasse.id,
                  items: [
                    for (final c in classes)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) {
                    if (id == null || id == klasse.id) return;
                    _class = classes.firstWhere((c) => c.id == id);
                    _allOpen = _allEvents = false;
                    _load(account);
                  },
                )
              else
                Text(
                  klasse.name,
                  key: const ValueKey('classlead-class-name'),
                  style: theme.textTheme.titleLarge,
                ),
              DropdownButton<ExcuseRange>(
                key: const ValueKey('classlead-range'),
                value: _range,
                items: [
                  for (final r in classLeadRanges)
                    DropdownMenuItem(
                      key: ValueKey('classlead-range-${r.name}'),
                      value: r,
                      child: Text(r.label),
                    ),
                ],
                onChanged: (r) {
                  if (r == null || r == _range) return;
                  _range = r;
                  _load(account);
                },
              ),
            ],
          ),
          if (data != null)
            Text(
              formatWeekRange(context, data.start, data.end),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                key: const ValueKey('classlead-link-excuses'),
                avatar: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Excuses'),
                onPressed: () => context.push('/excuses?class=${klasse.id}'),
              ),
              ActionChip(
                key: const ValueKey('classlead-link-timetable'),
                avatar: const Icon(Icons.calendar_view_week_outlined, size: 18),
                label: const Text('Timetable'),
                onPressed: () => context.push(
                  '/timetable/${ElementType.klasse.apiName}/${klasse.id}',
                ),
              ),
              ActionChip(
                key: const ValueKey('classlead-link-summary'),
                avatar: const Icon(Icons.bar_chart_outlined, size: 18),
                label: const Text('Absence summary'),
                onPressed: () => _openSummary(account, klasse),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text, {Key? key}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, key: key, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _more(String label, Key key, VoidCallback onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton(key: key, onPressed: onPressed, child: Text(label)),
    ),
  );

  List<Widget> _openSection(
    BuildContext context,
    Account account,
    ClassLeadDashboard data,
  ) {
    final open = data.open;
    final shown = _allOpen ? open : open.take(_shown).toList();
    return [
      _header(
        context,
        open.isEmpty ? 'Open absences' : 'Open absences (${open.length})',
        key: const ValueKey('classlead-open-header'),
      ),
      if (open.isEmpty)
        const ListTile(
          key: ValueKey('classlead-open-none'),
          leading: Icon(Icons.check_circle_outline),
          title: Text('Nothing to excuse in this range.'),
        ),
      for (final a in shown)
        ListTile(
          key: ValueKey('classlead-absence-${a.id}'),
          title: Text(a.studentName.isEmpty ? 'Pupil' : a.studentName),
          subtitle: Text(
            [
              excuseTimeSpan(context, a.start, a.end),
              if (a.reasonName.isNotEmpty) a.reasonName,
              if (a.text.isNotEmpty) a.text,
            ].join('\n'),
          ),
          isThreeLine: a.reasonName.isNotEmpty || a.text.isNotEmpty,
          trailing: ExcuseStatusChip(absence: a),
          onTap: () => _excuse(account, a),
        ),
      if (shown.length < open.length)
        _more(
          'Show all ${open.length}',
          const ValueKey('classlead-open-more'),
          () => setState(() => _allOpen = true),
        ),
    ];
  }

  static String _duration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  List<Widget> _pupilSection(BuildContext context, ClassLeadDashboard data) {
    final top = data.topPupils;
    return [
      _header(context, 'Most absences'),
      if (top.isEmpty)
        const ListTile(
          key: ValueKey('classlead-pupils-none'),
          title: Text('No absences in this range.'),
        ),
      for (final (i, p) in top.indexed)
        ListTile(
          key: ValueKey('classlead-pupil-${p.studentId ?? 'i$i'}'),
          leading: CircleAvatar(child: Text('${p.absences}')),
          title: Text(p.name),
          subtitle: Text(
            [
              p.absences == 1 ? '1 absence' : '${p.absences} absences',
              if (p.minutes > 0) _duration(p.minutes),
              if (p.open > 0) '${p.open} open',
            ].join(' · '),
          ),
        ),
    ];
  }

  List<Widget> _eventSection(BuildContext context, ClassLeadDashboard data) {
    final events = data.events;
    final shown = _allEvents ? events : events.take(_shown).toList();
    final day = dateFormat(context, 'EEE d MMM');
    return [
      _header(context, 'Class register entries'),
      if (!data.eventsAvailable)
        const ListTile(
          key: ValueKey('classlead-events-unavailable'),
          title: Text(
            "Your school's server didn't send class register "
            'entries for this class.',
          ),
        )
      else if (events.isEmpty)
        const ListTile(
          key: ValueKey('classlead-events-none'),
          title: Text('No entries in this range.'),
        ),
      for (final (i, e) in shown.indexed)
        ListTile(
          key: ValueKey('classlead-event-${e.id ?? 'i$i'}'),
          leading: Icon(
            e.isClassWide ? Icons.groups_outlined : Icons.person_outline,
          ),
          title: Text(
            e.isClassWide
                ? 'Whole class'
                : (e.studentName.isEmpty ? 'Pupil' : e.studentName),
          ),
          subtitle: Text(
            [
              [
                if (e.date != null) day.format(e.date!),
                if (e.reasonName.isNotEmpty) e.reasonName,
              ].join(' · '),
              if (e.text.isNotEmpty) e.text,
            ].where((s) => s.isNotEmpty).join('\n'),
          ),
        ),
      if (shown.length < events.length)
        _more(
          'Show all ${events.length}',
          const ValueKey('classlead-events-more'),
          () => setState(() => _allEvents = true),
        ),
    ];
  }
}
