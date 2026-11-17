import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/substitution_planning.dart';
import '../timetable/timetable_utils.dart';
import 'excuses_screen.dart' show excuseTimeSpan;

/// "My absences" in the drawer for teachers: the own absences the school
/// knows (with the lessons they affect and who substitutes) and "Report
/// absence" (reason, from–until, a note for the substitute).
class TeacherAbsencesScreen extends ConsumerStatefulWidget {
  const TeacherAbsencesScreen({super.key});

  @override
  ConsumerState<TeacherAbsencesScreen> createState() =>
      _TeacherAbsencesScreenState();
}

class _TeacherAbsencesScreenState extends ConsumerState<TeacherAbsencesScreen> {
  List<TeacherAbsence>? _absences;
  Object? _error;

  /// Only the latest load may set state.
  int _generation = 0;
  String? _accountId;

  SubstitutionPlanningRepository get _repo =>
      ref.read(substitutionPlanningRepositoryProvider);

  Future<void> _load(Account account) async {
    final gen = ++_generation;
    setState(() {
      _absences = null;
      _error = null;
    });
    try {
      final list = await _repo.absences(account);
      if (mounted && gen == _generation) setState(() => _absences = list);
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  Future<void> _report(Account account) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReportAbsenceScreen(account: account, repository: _repo),
      ),
    );
    if (created != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Absence reported.')));
    await _load(account);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final teacher = account != null && hasClassRegister(account);
    if (teacher && account.id != _accountId) {
      _accountId = account.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(account);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('My absences'),
        actions: [
          if (teacher)
            IconButton(
              key: const ValueKey('teacher-absences-refresh'),
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(account),
            ),
        ],
      ),
      floatingActionButton: teacher
          ? FloatingActionButton.extended(
              key: const ValueKey('teacher-absence-new'),
              onPressed: () => _report(account),
              icon: const Icon(Icons.add),
              label: const Text('Report absence'),
            )
          : null,
      body: !teacher
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only teacher accounts can report absences.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(account),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: _list(context, account),
              ),
            ),
    );
  }

  List<Widget> _list(BuildContext context, Account account) {
    final error = _error;
    if (error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                error is UntisException ? error.message : '$error',
                key: const ValueKey('teacher-absences-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _load(account),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ];
    }
    final list = _absences;
    if (list == null) {
      return [
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (list.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No absences. Tap "Report absence" to tell the school you '
            "can't come.",
            key: ValueKey('teacher-absences-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      for (final (i, a) in list.indexed)
        _AbsenceCard(key: ValueKey('teacher-absence-$i'), absence: a),
    ];
  }
}

class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({super.key, required this.absence});

  final TeacherAbsence absence;

  @override
  Widget build(BuildContext context) {
    final a = absence;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String t(DateTime d) => hhmm(d.hour * 60 + d.minute);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              excuseTimeSpan(context, a.start, a.end),
              style: theme.textTheme.titleMedium,
            ),
            if (a.reason.isNotEmpty) Text(a.reason),
            if (a.note.isNotEmpty) Text('Note for the substitute: ${a.note}'),
            if (a.missedPeriods != null && a.missedPeriods! > 0)
              Text(
                a.missedPeriods == 1
                    ? '1 lesson affected'
                    : '${a.missedPeriods} lessons affected',
                style: muted,
              ),
            for (final l in a.lessons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    '${dateFormat(context, 'EEE d MMM').format(l.start)} '
                        '${t(l.start)}',
                    [
                      if (l.subject.isNotEmpty) l.subject,
                      if (l.classes.isNotEmpty) l.classes.join(', '),
                    ].join(' '),
                    l.cancelled
                        ? 'cancelled'
                        : l.substitute.isNotEmpty
                        ? 'substitute: ${l.substitute}'
                        : 'no substitute yet',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: muted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Report an own absence: reason (from the server's form), from – until
/// (date and time each; quick "Today" / "Tomorrow" with the form's default
/// times), a note for the substitute. Pops with true when reported.
class ReportAbsenceScreen extends StatefulWidget {
  const ReportAbsenceScreen({
    super.key,
    required this.account,
    required this.repository,
  });

  final Account account;
  final SubstitutionPlanningRepository repository;

  @override
  State<ReportAbsenceScreen> createState() => _ReportAbsenceScreenState();
}

class _ReportAbsenceScreenState extends State<ReportAbsenceScreen> {
  TeacherAbsenceForm? _form;
  Object? _formError;
  int? _reasonId;
  late DateTime _start;
  late DateTime _end;

  /// Times of day of the quick buttons, in minutes (form defaults).
  int _dayStart = 7 * 60;
  int _dayEnd = 19 * 60;

  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setDay(0);
    _loadForm();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setDay(int offset) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + offset);
    _start = DateTime(d.year, d.month, d.day, _dayStart ~/ 60, _dayStart % 60);
    _end = DateTime(d.year, d.month, d.day, _dayEnd ~/ 60, _dayEnd % 60);
  }

  Future<void> _loadForm() async {
    setState(() {
      _form = null;
      _formError = null;
    });
    try {
      final form = await widget.repository.form(widget.account);
      if (!mounted) return;
      setState(() {
        _form = form;
        final s = form.start;
        final e = form.end;
        if (s != null && e != null && e.isAfter(s)) {
          _dayStart = s.hour * 60 + s.minute;
          _dayEnd = e.hour * 60 + e.minute;
          _setDay(0);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _formError = e);
    }
  }

  bool get _valid => _end.isAfter(_start);

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: start ? 'Absent from' : 'Absent until',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (start) {
        // Keep the length when the start moves.
        final length = _end.difference(_start);
        _start = d;
        if (!_end.isAfter(_start)) _end = _start.add(length);
      } else {
        _end = d;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  Future<void> _save() async {
    if (!_valid || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.reportAbsence(
        widget.account,
        start: _start,
        end: _end,
        reasonId: _reasonId,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is UntisException ? e.message : e.toString();
      });
    }
  }

  Widget _when(BuildContext context, {required bool start}) {
    final d = start ? _start : _end;
    final name = start ? 'from' : 'until';
    return Row(
      children: [
        SizedBox(width: 56, child: Text(start ? 'From' : 'Until')),
        Expanded(
          child: OutlinedButton(
            key: ValueKey('teacher-absence-$name-date'),
            onPressed: _saving ? null : () => _pickDate(start: start),
            child: Text(dateFormat(context, 'EEE d MMM y').format(d)),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: ValueKey('teacher-absence-$name-time'),
          onPressed: _saving ? null : () => _pickTime(start: start),
          child: Text(hhmm(d.hour * 60 + d.minute)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = _form;
    final formError = _formError;
    return Scaffold(
      appBar: AppBar(title: const Text('Report absence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (formError != null) ...[
            Text(
              formError is UntisException ? formError.message : '$formError',
              key: const ValueKey('teacher-absence-form-error'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _loadForm,
                child: const Text('Try again'),
              ),
            ),
          ] else if (form == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            DropdownButtonFormField<int?>(
              key: const ValueKey('teacher-absence-reason'),
              initialValue: _reasonId,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('No reason'),
                ),
                for (final r in form.reasons)
                  DropdownMenuItem<int?>(
                    key: ValueKey('teacher-absence-reason-${r.id}'),
                    value: r.id,
                    child: Text(r.name),
                  ),
              ],
              onChanged: _saving ? null : (v) => setState(() => _reasonId = v),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  key: const ValueKey('teacher-absence-today'),
                  label: const Text('Today'),
                  onPressed: _saving ? null : () => setState(() => _setDay(0)),
                ),
                ActionChip(
                  key: const ValueKey('teacher-absence-tomorrow'),
                  label: const Text('Tomorrow'),
                  onPressed: _saving ? null : () => setState(() => _setDay(1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _when(context, start: true),
            const SizedBox(height: 8),
            _when(context, start: false),
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'The end must be after the start.',
                  key: const ValueKey('teacher-absence-invalid'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('teacher-absence-note'),
              controller: _note,
              enabled: !_saving,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note for your substitute',
                hintText: 'e.g. where the worksheets are',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The school plans the substitutions; colleagues and pupils see '
              'them in their timetables once published.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('teacher-absence-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('teacher-absence-save'),
                onPressed: _saving || !_valid ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Report absence'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
