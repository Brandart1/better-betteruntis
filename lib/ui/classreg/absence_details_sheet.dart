import 'package:flutter/material.dart';

import '../../core/class_register.dart';
import '../timetable/timetable_utils.dart';

/// One line about a pupil's absence in a lesson block from [start] to
/// [end]: "Absent", "Late · arrived 08:20", "Left early · from 09:10" or
/// "Absent 08:10–08:30", plus the reason and the note.
String describeAbsence(
  AbsenceDetails? d,
  DateTime start,
  DateTime end,
  Map<int, String> reasons,
) {
  if (d == null) return 'Absent';
  final fromStart = !d.start.isAfter(start);
  final toEnd = !d.end.isBefore(end);
  final when = switch ((fromStart, toEnd)) {
    (true, true) => 'Absent',
    (true, false) => 'Late · arrived ${_t(d.end)}',
    (false, true) => 'Left early · from ${_t(d.start)}',
    (false, false) => 'Absent ${_t(d.start)}–${_t(d.end)}',
  };
  return [
    when,
    if (d.reasonId case final id?) reasons[id] ?? 'Reason #$id',
    if (d.text.trim().isNotEmpty) d.text.trim(),
  ].join(' · ');
}

String _t(DateTime d) => hhmm(minuteOfDay(d));

/// Times, reason and note of one pupil's absence in a lesson block
/// ([start]–[end]). Pops with the new [AbsenceDetails], or null on cancel.
/// [now] offers "Arrived now" / "Left now" while the lesson runs.
Future<AbsenceDetails?> showAbsenceDetailsSheet(
  BuildContext context, {
  required String pupil,
  required DateTime start,
  required DateTime end,
  required DateTime now,
  required Map<int, String> reasons,
  AbsenceDetails? initial,
}) => showModalBottomSheet<AbsenceDetails>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => AbsenceDetailsSheet(
    pupil: pupil,
    start: start,
    end: end,
    now: now,
    reasons: reasons,
    initial: initial,
  ),
);

class AbsenceDetailsSheet extends StatefulWidget {
  const AbsenceDetailsSheet({
    super.key,
    required this.pupil,
    required this.start,
    required this.end,
    required this.now,
    required this.reasons,
    this.initial,
  });

  final String pupil;
  final DateTime start;
  final DateTime end;
  final DateTime now;
  final Map<int, String> reasons;
  final AbsenceDetails? initial;

  @override
  State<AbsenceDetailsSheet> createState() => _AbsenceDetailsSheetState();
}

class _AbsenceDetailsSheetState extends State<AbsenceDetailsSheet> {
  late DateTime _from = _clamp(widget.initial?.start ?? widget.start);
  late DateTime _until = _clamp(widget.initial?.end ?? widget.end);
  late int? _reason = widget.initial?.reasonId;
  late final _note = TextEditingController(text: widget.initial?.text ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime _clamp(DateTime d) => d.isBefore(widget.start)
      ? widget.start
      : d.isAfter(widget.end)
      ? widget.end
      : d;

  bool get _running =>
      widget.now.isAfter(widget.start) && widget.now.isBefore(widget.end);

  /// The current minute, so "now" isn't saved with seconds.
  DateTime get _nowMinute => DateTime(
    widget.now.year,
    widget.now.month,
    widget.now.day,
    widget.now.hour,
    widget.now.minute,
  );

  bool get _valid => _from.isBefore(_until);

  Future<void> _pick(bool from) async {
    final current = from ? _from : _until;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: from ? 'Absent from' : 'Absent until',
    );
    if (t == null || !mounted) return;
    final d = _clamp(
      DateTime(
        widget.start.year,
        widget.start.month,
        widget.start.day,
        t.hour,
        t.minute,
      ),
    );
    setState(() => from ? _from = d : _until = d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whole = _from == widget.start && _until == widget.end;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Absence · ${widget.pupil}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Lesson ${_t(widget.start)}–${_t(widget.end)}. For a late '
              'arrival or leaving early, set the part of the lesson the '
              'pupil was missing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const ValueKey('absence-whole'),
                  label: const Text('Whole lesson'),
                  selected: whole,
                  onSelected: (_) => setState(() {
                    _from = widget.start;
                    _until = widget.end;
                  }),
                ),
                if (_running) ...[
                  ActionChip(
                    key: const ValueKey('absence-arrived-now'),
                    avatar: const Icon(Icons.login, size: 18),
                    label: const Text('Arrived now'),
                    onPressed: () => setState(() {
                      _from = widget.start;
                      _until = _nowMinute;
                    }),
                  ),
                  ActionChip(
                    key: const ValueKey('absence-left-now'),
                    avatar: const Icon(Icons.logout, size: 18),
                    label: const Text('Left now'),
                    onPressed: () => setState(() {
                      _from = _nowMinute;
                      _until = widget.end;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    key: const ValueKey('absence-from'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('From'),
                    subtitle: Text(_t(_from)),
                    onTap: () => _pick(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    key: const ValueKey('absence-until'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Until'),
                    subtitle: Text(_t(_until)),
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            if (!_valid)
              Text(
                '“From” must be before “until”.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (widget.reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                key: const ValueKey('absence-reason'),
                initialValue: widget.reasons.containsKey(_reason)
                    ? _reason
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No reason'),
                  ),
                  for (final MapEntry(:key, :value) in widget.reasons.entries)
                    DropdownMenuItem<int?>(value: key, child: Text(value)),
                ],
                onChanged: (v) => setState(() => _reason = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('absence-note'),
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('absence-apply'),
                  onPressed: _valid
                      ? () => Navigator.of(context).pop(
                          AbsenceDetails(
                            start: _from,
                            end: _until,
                            reasonId: _reason,
                            text: _note.text.trim(),
                          ),
                        )
                      : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
