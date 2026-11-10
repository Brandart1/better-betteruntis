/// "Report absence" for parent accounts: pick a child, a time span, a reason
/// and an optional note, then send it via [InfoCenterRepository.reportAbsence].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/info.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../timetable/timetable_utils.dart';
import 'info_common.dart';

/// Whether [a] may plausibly report absences: a signed-in parent account with
/// at least one child. (Whether the school allows it is only known after
/// asking the server; the form says so.)
bool canReportAbsences(Account a) =>
    !a.anonymous && !a.hasOwnTimetable && a.children.isNotEmpty;

/// Default times when neither the time grid nor the server suggest any.
const kDefaultSchoolDay = (start: 8 * 60, end: 16 * 60);

/// The school day of [day] in minutes since midnight: first lesson start to
/// last lesson end of the time grid, else the server's defaults, else
/// [kDefaultSchoolDay].
({int start, int end}) schoolDayMinutes(
  TimeGrid? grid,
  DateTime day, [
  AbsenceReportOptions? options,
]) {
  final units = grid == null ? const <TimeUnit>[] : unitsFor(grid, day.weekday);
  if (units.isNotEmpty) {
    final start = units.map((u) => u.start).reduce((a, b) => a < b ? a : b);
    final end = units.map((u) => u.end).reduce((a, b) => a > b ? a : b);
    if (end > start) return (start: start, end: end);
  }
  final s = options?.defaultStartMinutes, e = options?.defaultEndMinutes;
  if (s != null && e != null && e > s) return (start: s, end: e);
  return kDefaultSchoolDay;
}

/// The form's values, with validation independent of widgets.
class AbsenceReportDraft {
  const AbsenceReportDraft({
    required this.studentId,
    required this.startDay,
    required this.endDay,
    required this.startMinutes,
    required this.endMinutes,
    this.reasonId,
    this.text = '',
  });

  final int? studentId;
  final DateTime startDay;
  final DateTime endDay;
  final int startMinutes;
  final int endMinutes;
  final int? reasonId;
  final String text;

  static const maxTextLength = 500;

  DateTime get start => DateTime(
    startDay.year,
    startDay.month,
    startDay.day,
    startMinutes ~/ 60,
    startMinutes % 60,
  );
  DateTime get end => DateTime(
    endDay.year,
    endDay.month,
    endDay.day,
    endMinutes ~/ 60,
    endMinutes % 60,
  );

  /// The first problem, or null when the draft can be sent. [reasons] are
  /// the selectable reasons; a reason is required only when there are any.
  String? validate(List<AbsenceReason> reasons) {
    if (studentId == null) return 'Choose a child.';
    if (!end.isAfter(start)) return 'The end must be after the start.';
    if (end.difference(start) > const Duration(days: 366)) {
      return 'An absence can last at most a year.';
    }
    if (reasons.isNotEmpty && !reasons.any((r) => r.id == reasonId)) {
      return 'Choose a reason.';
    }
    if (text.length > maxTextLength) {
      return 'The note is too long (max. $maxTextLength characters).';
    }
    return null;
  }

  AbsenceReport toReport() => AbsenceReport(
    studentId: studentId!,
    start: start,
    end: end,
    reasonId: reasonId,
    text: text.trim(),
  );
}

/// User-facing text for a failed report.
String describeReportError(Object? e) {
  if (e is UntisException) {
    if (e.isTimeout) return "The server didn't respond. Please try again.";
    if (e.isNetwork) return 'No connection. Please try again when online.';
    if (e.code == UntisException.noRight) {
      final m = e.message.trim();
      return m.isEmpty || m == 'HTTP 403'
          ? "Your school doesn't allow reporting absences for this account."
          : m;
    }
    return e.message;
  }
  return 'Something went wrong: $e';
}

/// Opens the form; resolves to true when an absence was reported.
Future<bool> showAbsenceReportScreen(
  BuildContext context,
  Account account,
) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AbsenceReportScreen(account: account),
    ),
  );
  return ok ?? false;
}

class AbsenceReportScreen extends ConsumerStatefulWidget {
  const AbsenceReportScreen({super.key, required this.account, this.now});
  final Account account;

  /// Clock for the defaults (tests).
  final DateTime? now;

  @override
  ConsumerState<AbsenceReportScreen> createState() =>
      _AbsenceReportScreenState();
}

class _AbsenceReportScreenState extends ConsumerState<AbsenceReportScreen> {
  late int? _studentId =
      widget.account.activeChild?.id ?? widget.account.children.firstOrNull?.id;
  late DateTime _startDay;
  late DateTime _endDay;
  int? _startMinutes;
  int? _endMinutes;
  bool _wholeDay = true;
  int? _reasonId;
  final _text = TextEditingController();

  AbsenceReportOptions? _options;
  Object? _optionsError;
  bool _loadingOptions = true;
  bool _submitting = false;
  String? _error;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(widget.now ?? DateTime.now());
    _startDay = today;
    _endDay = today;
    _loadOptions();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final id = _studentId;
    if (id == null) {
      setState(() => _loadingOptions = false);
      return;
    }
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final o = await ref
          .read(infoCenterRepositoryProvider)
          .absenceReportOptions(widget.account, id);
      if (!mounted) return;
      setState(() {
        _options = o;
        _loadingOptions = false;
        if (!o.reasons.any((r) => r.id == _reasonId)) {
          _reasonId = o.reasons.any((r) => r.id == o.defaultReasonId)
              ? o.defaultReasonId
              : o.reasons.firstOrNull?.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optionsError = e;
        _loadingOptions = false;
      });
    }
  }

  TimeGrid? get _grid => ref.read(nameResolverProvider).value?.timeGrid;

  AbsenceReportDraft get _draft {
    final first = schoolDayMinutes(_grid, _startDay, _options);
    final last = schoolDayMinutes(_grid, _endDay, _options);
    return AbsenceReportDraft(
      studentId: _studentId,
      startDay: _startDay,
      endDay: _endDay,
      startMinutes: _wholeDay ? first.start : _startMinutes ?? first.start,
      endMinutes: _wholeDay ? last.end : _endMinutes ?? last.end,
      reasonId: _reasonId,
      text: _text.text,
    );
  }

  bool get _blocked => _options?.allowed == false;

  Future<void> _pickDate({required bool start}) async {
    final today = dateOnly(widget.now ?? DateTime.now());
    final initial = start ? _startDay : _endDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: addDays(today, -60),
      lastDate: addDays(today, 365),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final span = _endDay.difference(_startDay).inDays;
        _startDay = dateOnly(picked);
        // Keep the span, so moving the start never leaves the end before it.
        _endDay = addDays(_startDay, span < 0 ? 0 : span);
      } else {
        _endDay = dateOnly(picked);
        if (_endDay.isBefore(_startDay)) _startDay = _endDay;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final d = _draft;
    final current = start ? d.startMinutes : d.endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final m = picked.hour * 60 + picked.minute;
      if (start) {
        _startMinutes = m;
      } else {
        _endMinutes = m;
      }
    });
  }

  Future<void> _submit() async {
    final reasons = _options?.reasons ?? const <AbsenceReason>[];
    final draft = _draft;
    final problem = draft.validate(reasons);
    setState(() {
      _showValidation = true;
      _error = null;
    });
    if (problem != null || _blocked) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(infoCenterRepositoryProvider)
          .reportAbsence(widget.account, draft.toReport());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeReportError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(nameResolverProvider); // rebuild when the time grid arrives
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = widget.account.children;
    final reasons = _options?.reasons ?? const <AbsenceReason>[];
    final draft = _draft;
    final problem = _showValidation ? draft.validate(reasons) : null;
    final dayFmt = dateFormat(context, 'EEE, d MMM yyyy');
    final enabled = !_submitting;

    Widget notice(
      IconData icon,
      String text, {
      required bool error,
      Key? key,
    }) => Card.filled(
      key: key,
      color: error ? cs.errorContainer : cs.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: error ? cs.onErrorContainer : cs.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: error ? cs.onErrorContainer : cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final fields = <Widget>[
      if (_blocked)
        notice(
          Icons.block,
          "Your school doesn't allow reporting absences for this account. "
          'Please contact the school directly.',
          error: true,
          key: const ValueKey('absence-report-blocked'),
        ),
      if (_optionsError != null)
        notice(
          Icons.info_outline,
          'Could not load the absence reasons: '
          '${describeReportError(_optionsError)}',
          error: false,
          key: const ValueKey('absence-report-options-error'),
        )
      else if ((_options?.notice ?? '').isNotEmpty)
        notice(
          Icons.info_outline,
          'Reasons from the school data are shown '
          '(${_options!.notice}).',
          error: false,
          key: const ValueKey('absence-report-options-notice'),
        ),
      if (children.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<int>(
            key: const ValueKey('absence-report-child'),
            initialValue: _studentId,
            decoration: const InputDecoration(
              labelText: 'Child',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in children)
                DropdownMenuItem(value: c.id, child: Text(c.displayName)),
            ],
            onChanged: enabled
                ? (v) {
                    if (v == null || v == _studentId) return;
                    setState(() => _studentId = v);
                    _loadOptions();
                  }
                : null,
          ),
        )
      else if (children.length == 1)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(children.single.displayName),
          subtitle: const Text('Child'),
        ),
      SwitchListTile(
        key: const ValueKey('absence-report-whole-day'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Whole school day'),
        subtitle: Text(
          '${hhmm(draft.startMinutes)} – ${hhmm(draft.endMinutes)}',
        ),
        value: _wholeDay,
        onChanged: enabled
            ? (v) => setState(() {
                _wholeDay = v;
                if (!v) {
                  _startMinutes = draft.startMinutes;
                  _endMinutes = draft.endMinutes;
                }
              })
            : null,
      ),
      _DateTimeRow(
        label: 'From',
        keyPrefix: 'absence-report-start',
        date: dayFmt.format(_startDay),
        time: hhmm(draft.startMinutes),
        timeEnabled: enabled && !_wholeDay,
        onDate: enabled ? () => _pickDate(start: true) : null,
        onTime: () => _pickTime(start: true),
      ),
      _DateTimeRow(
        label: 'Until',
        keyPrefix: 'absence-report-end',
        date: dayFmt.format(_endDay),
        time: hhmm(draft.endMinutes),
        timeEnabled: enabled && !_wholeDay,
        onDate: enabled ? () => _pickDate(start: false) : null,
        onTime: () => _pickTime(start: false),
      ),
      const SizedBox(height: 16),
      if (_loadingOptions)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        )
      else if (reasons.isNotEmpty)
        DropdownButtonFormField<int>(
          key: ValueKey('absence-report-reason-${_options.hashCode}'),
          initialValue: _reasonId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final r in reasons)
              DropdownMenuItem(value: r.id, child: Text(r.name)),
          ],
          onChanged: enabled ? (v) => setState(() => _reasonId = v) : null,
        )
      else
        Text(
          'The school offers no absence reasons; the absence is sent without one.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('absence-report-text'),
        controller: _text,
        enabled: enabled,
        minLines: 2,
        maxLines: 5,
        maxLength: AbsenceReportDraft.maxTextLength,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
          hintText: 'e.g. ill with a fever',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            problem,
            key: const ValueKey('absence-report-problem'),
            style: TextStyle(color: cs.error),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: notice(
            Icons.error_outline,
            _error!,
            error: true,
            key: const ValueKey('absence-report-error'),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'The school sees the absence right away; whether it is excused is '
        'decided by the school.',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report absence'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('absence-report-submit'),
              onPressed: _submitting || _blocked || _studentId == null
                  ? null
                  : _submit,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        key: ValueKey('absence-report-progress'),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Send'),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kInfoMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: fields,
          ),
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.keyPrefix,
    required this.date,
    required this.time,
    required this.timeEnabled,
    required this.onDate,
    required this.onTime,
  });

  final String label;
  final String keyPrefix;
  final String date;
  final String time;
  final bool timeEnabled;
  final VoidCallback? onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(
          child: OutlinedButton.icon(
            key: ValueKey('$keyPrefix-date'),
            onPressed: onDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(date, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: ValueKey('$keyPrefix-time'),
          onPressed: timeEnabled ? onTime : null,
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(time),
        ),
      ],
    ),
  );
}
