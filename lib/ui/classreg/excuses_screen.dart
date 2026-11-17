import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/excuses.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';

/// "Excuses" in the drawer for teachers: the absences of a class in a range,
/// filtered by excuse status; tap one to excuse it (or not) with a text.
/// Who may excuse is decided by the server (usually the class teacher).
class ExcusesScreen extends ConsumerStatefulWidget {
  const ExcusesScreen({super.key});

  @override
  ConsumerState<ExcusesScreen> createState() => _ExcusesScreenState();
}

class _ExcusesScreenState extends ConsumerState<ExcusesScreen> {
  ExcuseMeta? _meta;
  int? _classId;
  ExcuseRange _range = ExcuseRange.last14;
  ExcuseFilter _filter = ExcuseFilter.open;
  ({DateTime start, DateTime end})? _days;

  List<ExcuseAbsence>? _absences;
  Object? _error;

  /// Only the latest load may set state.
  int _generation = 0;
  String? _accountId;

  ExcuseRepository get _repo => ref.read(excuseRepositoryProvider);

  Future<void> _load(Account account) async {
    final gen = ++_generation;
    setState(() {
      _absences = null;
      _error = null;
    });
    try {
      final meta = _meta ?? await _repo.meta(account);
      if (!mounted || gen != _generation) return;
      final classId =
          _classId ??
          // A class of the account (class teacher), else the first one.
          meta.classes
              .where((c) => account.klassenIds.contains(c.id))
              .firstOrNull
              ?.id ??
          meta.classes.firstOrNull?.id;
      setState(() {
        _meta = meta;
        _classId = classId;
      });
      if (classId == null) {
        setState(() => _absences = const []);
        return;
      }
      final days = await _repo.rangeDays(account, _range);
      if (mounted && gen == _generation) setState(() => _days = days);
      final list = await _repo.absences(
        account,
        classId: classId,
        range: _range,
        filter: _filter,
      );
      if (mounted && gen == _generation) setState(() => _absences = list);
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  static String _message(Object e) =>
      e is UntisException ? e.message : e.toString();

  Future<void> _open(Account account, ExcuseAbsence a) async {
    final meta = _meta;
    if (meta == null) return;
    final saved = await showModalBottomSheet<ExcuseAbsence>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExcuseSheet(
        account: account,
        meta: meta,
        absence: a,
        repository: _repo,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _absences = [
        for (final x in _absences ?? const <ExcuseAbsence>[])
          if (x.id != saved.id)
            x
          else if (_filter.type == null || saved.type == _filter.type)
            saved,
      ];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved: ${saved.studentName.isEmpty ? 'absence' : saved.studentName}'
          ' – ${saved.status?.name ?? saved.type.label}.',
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
      _meta = null;
      _classId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(account);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excuses'),
        actions: [
          if (teacher)
            IconButton(
              key: const ValueKey('excuses-refresh'),
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(account),
            ),
        ],
      ),
      body: !teacher
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Only teacher accounts can excuse absences.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(account),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _controls(context, account),
                  ..._list(context, account),
                ],
              ),
            ),
    );
  }

  Widget _controls(BuildContext context, Account account) {
    final meta = _meta;
    final days = _days;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (meta != null && meta.classes.isNotEmpty)
                DropdownButton<int>(
                  key: const ValueKey('excuses-class'),
                  value: _classId,
                  items: [
                    for (final c in meta.classes)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) {
                    if (id == null || id == _classId) return;
                    _classId = id;
                    _load(account);
                  },
                ),
              DropdownButton<ExcuseRange>(
                key: const ValueKey('excuses-range'),
                value: _range,
                items: [
                  for (final r in ExcuseRange.values)
                    DropdownMenuItem(
                      key: ValueKey('excuses-range-${r.name}'),
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
          if (days != null)
            Text(
              formatWeekRange(context, days.start, days.end),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in ExcuseFilter.values)
                ChoiceChip(
                  key: ValueKey('excuses-filter-${f.name}'),
                  label: Text(f.label),
                  selected: f == _filter,
                  onSelected: (_) {
                    if (f == _filter) return;
                    _filter = f;
                    _load(account);
                  },
                ),
            ],
          ),
        ],
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
                _message(error),
                key: const ValueKey('excuses-error'),
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
    if (_meta?.classes.isEmpty ?? false) {
      return [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No classes to show. Your school may not allow this account to '
            'manage absences.',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    if (list.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _filter == ExcuseFilter.all
                ? 'No absences in this range.'
                : 'No absences with status "${_filter.label}" in this range.',
            key: const ValueKey('excuses-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      for (final a in list)
        ListTile(
          key: ValueKey('excuse-${a.id}'),
          title: Text(a.studentName.isEmpty ? 'Pupil' : a.studentName),
          subtitle: Text(
            [
              excuseTimeSpan(context, a.start, a.end),
              if (a.reasonName.isNotEmpty) a.reasonName,
              if (a.text.isNotEmpty) a.text,
              if (a.excuseText.isNotEmpty) 'Excuse: ${a.excuseText}',
            ].join('\n'),
          ),
          isThreeLine: a.reasonName.isNotEmpty || a.text.isNotEmpty,
          trailing: ExcuseStatusChip(absence: a),
          onTap: () => _open(account, a),
        ),
    ];
  }
}

/// "Mon 10 Nov, 08:00–08:45", or both dates when it spans days.
String excuseTimeSpan(BuildContext context, DateTime start, DateTime end) {
  final day = dateFormat(context, 'EEE d MMM');
  String t(DateTime d) => hhmm(d.hour * 60 + d.minute);
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return sameDay
      ? '${day.format(start)}, ${t(start)}–${t(end)}'
      : '${day.format(start)} ${t(start)} – ${day.format(end)} ${t(end)}';
}

/// The excuse status of an absence as a small colored label.
class ExcuseStatusChip extends StatelessWidget {
  const ExcuseStatusChip({super.key, required this.absence});

  final ExcuseAbsence absence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (absence.type) {
      ExcuseStatusType.excused => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      ExcuseStatusType.notExcused => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      ExcuseStatusType.open => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            absence.status?.name ?? absence.type.label,
            key: ValueKey('excuse-status-${absence.id}'),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

/// Excuse of one absence: quick Excused / Not excused (a chooser when the
/// school has several statuses of that kind), every status, the excuse
/// text, Save. Pops with the saved absence; errors stay in the sheet.
class ExcuseSheet extends StatefulWidget {
  const ExcuseSheet({
    super.key,
    required this.account,
    required this.meta,
    required this.absence,
    required this.repository,
  });

  final Account account;
  final ExcuseMeta meta;
  final ExcuseAbsence absence;
  final ExcuseRepository repository;

  @override
  State<ExcuseSheet> createState() => _ExcuseSheetState();
}

class _ExcuseSheetState extends State<ExcuseSheet> {
  late ExcuseStatus? _status =
      widget.absence.status ??
      widget.meta.status(widget.meta.defaultExcuseStatusId);
  late final _text = TextEditingController(text: widget.absence.excuseText);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _quick(ExcuseStatusType type) async {
    final options = widget.meta.statusesOf(type);
    if (options.isEmpty) return;
    final chosen = options.length == 1
        ? options.single
        : await showDialog<ExcuseStatus>(
            context: context,
            builder: (context) => SimpleDialog(
              title: Text(type.label),
              children: [
                for (final s in options)
                  SimpleDialogOption(
                    key: ValueKey('excuse-choose-${s.id}'),
                    onPressed: () => Navigator.of(context).pop(s),
                    child: Text(s.name),
                  ),
              ],
            ),
          );
    if (chosen != null && mounted) setState(() => _status = chosen);
  }

  Future<void> _save() async {
    final status = _status;
    if (status == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.save(
        widget.account,
        widget.absence,
        status: status,
        text: _text.text,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is UntisException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.absence;
    final theme = Theme.of(context);
    final editable = a.excuseStatusEditable;
    final hasExcused = widget.meta
        .statusesOf(ExcuseStatusType.excused)
        .isNotEmpty;
    final hasNotExcused = widget.meta
        .statusesOf(ExcuseStatusType.notExcused)
        .isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.studentName.isEmpty ? 'Absence' : a.studentName,
              style: theme.textTheme.titleLarge,
            ),
            Text(excuseTimeSpan(context, a.start, a.end)),
            if (a.reasonName.isNotEmpty) Text('Reason: ${a.reasonName}'),
            if (a.text.isNotEmpty) Text('Note: ${a.text}'),
            const SizedBox(height: 16),
            if (!editable) ...[
              Row(
                children: [
                  const Text('Excuse: '),
                  ExcuseStatusChip(absence: a),
                ],
              ),
              if (a.excuseText.isNotEmpty) Text(a.excuseText),
              const SizedBox(height: 8),
              Text(
                "You can't change the excuse of this absence.",
                key: const ValueKey('excuse-readonly'),
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              Row(
                children: [
                  if (hasExcused)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('excuse-quick-excused'),
                        onPressed: _saving
                            ? null
                            : () => _quick(ExcuseStatusType.excused),
                        icon: const Icon(Icons.check),
                        label: const Text('Excused'),
                      ),
                    ),
                  if (hasExcused && hasNotExcused) const SizedBox(width: 8),
                  if (hasNotExcused)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('excuse-quick-notExcused'),
                        onPressed: _saving
                            ? null
                            : () => _quick(ExcuseStatusType.notExcused),
                        icon: const Icon(Icons.close),
                        label: const Text('Not excused'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Status', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in widget.meta.statuses)
                    ChoiceChip(
                      key: ValueKey('excuse-status-option-${s.id}'),
                      label: Text(s.name),
                      selected: _status?.id == s.id,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('excuse-text'),
                controller: _text,
                enabled: !_saving,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Excuse text',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('excuse-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('excuse-save'),
                  onPressed: _saving || _status == null ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
