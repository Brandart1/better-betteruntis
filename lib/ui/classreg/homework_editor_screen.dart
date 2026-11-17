import 'package:flutter/material.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';

/// Form for homework given in a lesson on [given]: text, remark (only
/// teachers see it), due date and done. New homework is due on
/// [nextLesson] (the next lesson of the course) unless the teacher picks
/// another day; a week later when there is none. [onSubmit] sends it; its
/// error stays visible here. Pops with true once it was saved.
class HomeworkEditorScreen extends StatefulWidget {
  const HomeworkEditorScreen({
    super.key,
    required this.given,
    this.initial,
    this.nextLesson,
    required this.onSubmit,
  });

  final DateTime given;

  /// The homework to change; null for new homework.
  final Homework? initial;
  final Future<DateTime?>? nextLesson;
  final Future<void> Function(Homework homework) onSubmit;

  @override
  State<HomeworkEditorScreen> createState() => _HomeworkEditorScreenState();
}

class _HomeworkEditorScreenState extends State<HomeworkEditorScreen> {
  late final _text = TextEditingController(text: widget.initial?.text ?? '');
  late final _remark = TextEditingController(
    text: widget.initial?.remark ?? '',
  );
  late DateTime? _due = widget.initial?.endDate;
  late bool _completed = widget.initial?.completed ?? false;

  /// The due date is the next lesson of the course (not picked by hand).
  bool _dueIsNextLesson = false;
  bool _sending = false;
  String? _error;

  DateTime get _givenDay =>
      DateTime(widget.given.year, widget.given.month, widget.given.day);

  @override
  void initState() {
    super.initState();
    if (_due != null) return;
    final next = widget.nextLesson;
    void use(DateTime? d) {
      if (!mounted || _due != null) return;
      setState(() {
        _dueIsNextLesson = d != null;
        _due =
            d ?? DateTime(_givenDay.year, _givenDay.month, _givenDay.day + 7);
      });
    }

    if (next == null) {
      use(null);
    } else {
      next.then(use, onError: (_) => use(null));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _remark.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && _due != null && _text.text.trim().isNotEmpty;

  Future<void> _pickDue() async {
    final first = _givenDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: _due != null && !_due!.isBefore(first) ? _due! : first,
      firstDate: first,
      lastDate: DateTime(first.year + 1, first.month, first.day),
      helpText: 'Due date',
    );
    if (picked != null && mounted) {
      setState(() {
        _due = picked;
        _dueIsNextLesson = false;
      });
    }
  }

  Future<void> _send() async {
    final due = _due;
    if (!_canSend || due == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final base =
          widget.initial ??
          Homework(
            id: 0,
            lessonId: 0,
            startDate: _givenDay,
            endDate: due,
            text: '',
          );
      await widget.onSubmit(
        base.copyWith(
          endDate: due,
          text: _text.text.trim(),
          remark: _remark.text.trim(),
          completed: _completed,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is UntisException
            ? (e.code == 0 || e.code == -1
                  ? e.message
                  : '${e.message} (error ${e.code})')
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final large = isLargeText(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final due = _due;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New homework' : 'Edit homework'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              key: const ValueKey('homework-text'),
              controller: _text,
              minLines: 3,
              maxLines: 8,
              enabled: !_sending,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Homework',
                helperText: 'Pupils and parents see this',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const ValueKey('homework-remark'),
              controller: _remark,
              minLines: 1,
              maxLines: 4,
              enabled: !_sending,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Remark (optional)',
                helperText: 'Only teachers see this',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('homework-due'),
            leading: large ? null : const Icon(Icons.event_outlined),
            title: const Text('Due'),
            subtitle: Text(
              due == null
                  ? 'Finding the next lesson of this course…'
                  : '${dateFormat(context, 'EEE d MMM').format(due)}'
                        '${_dueIsNextLesson ? ' (next lesson of this course)' : ''}',
            ),
            trailing: large ? null : const Icon(Icons.edit_calendar_outlined),
            onTap: _sending ? null : _pickDue,
          ),
          SwitchListTile(
            key: const ValueKey('homework-done'),
            title: const Text('Done'),
            subtitle: const Text('Pupils see it marked as done'),
            value: _completed,
            onChanged: _sending ? null : (v) => setState(() => _completed = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              // There is no server call to delete homework.
              'Given ${dateFormat(context, 'EEE d MMM').format(_givenDay)}. '
              "Saved homework can't be deleted in the app; remove it in "
              'WebUntis if needed.',
              key: const ValueKey('homework-no-delete'),
              style: muted,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                key: const ValueKey('homework-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Could not save the homework: $_error',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('homework-save'),
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save homework'),
            ),
          ),
        ],
      ),
    );
  }
}
