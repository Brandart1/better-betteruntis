import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';

/// Opens the class register of one lesson block ([periods]: one lesson, or
/// the periods of a double lesson). Resolves to true when something was saved.
Future<bool> openClassRegister(
  BuildContext context, {
  required Account account,
  required List<Period> periods,
  required String title,
  required String subtitle,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ClassRegisterScreen(
        account: account,
        periods: periods,
        title: title,
        subtitle: subtitle,
      ),
    ),
  );
  return saved ?? false;
}

/// Attendance check and lesson topic ("Lehrstoff") of one lesson, for
/// teacher accounts. Saving records the absences, confirms the attendance
/// check and stores the topic for every period of the block.
class ClassRegisterScreen extends ConsumerStatefulWidget {
  const ClassRegisterScreen({
    super.key,
    required this.account,
    required this.periods,
    required this.title,
    required this.subtitle,
  });

  final Account account;
  final List<Period> periods;
  final String title;
  final String subtitle;

  @override
  ConsumerState<ClassRegisterScreen> createState() =>
      _ClassRegisterScreenState();
}

class _ClassRegisterScreenState extends ConsumerState<ClassRegisterScreen> {
  final _topic = TextEditingController();
  PeriodRegisterData? _data;
  Object? _loadError;
  bool _saving = false;

  /// Absent according to the server / as currently set on screen.
  Set<int> _absentBefore = {};
  Set<int> _absent = {};
  String _topicBefore = '';

  List<ClassRegStudent> _students = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _loadError = null;
    });
    try {
      final d = await ref
          .read(classRegisterRepositoryProvider)
          .load(widget.account, widget.periods);
      if (!mounted) return;
      final regs = [for (final p in widget.periods) ?d.periods[p.id]];
      final ids = <int>{
        for (final r in regs) ...r.studentIds,
        if (regs.every((r) => r.studentIds.isEmpty)) ...d.students.keys,
      };
      final students = [
        for (final id in ids)
          d.students[id] ??
              ClassRegStudent(id: id, firstName: '', lastName: '#$id'),
      ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
      final absent = {
        for (final r in regs)
          for (final a in r.absences) a.studentId,
      };
      final topic = regs
          .map((r) => r.topic)
          .firstWhere((t) => t.trim().isNotEmpty, orElse: () => '');
      setState(() {
        _data = d;
        _students = students;
        _absentBefore = absent;
        _absent = {...absent};
        _topicBefore = topic;
        _topic.text = topic;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  List<PeriodRegister> get _regs => [
    for (final p in widget.periods) ?_data?.periods[p.id],
  ];

  bool get _checked => _regs.isNotEmpty && _regs.every((r) => r.absenceChecked);

  bool get _dirty =>
      _data != null &&
      (_topic.text.trim() != _topicBefore.trim() ||
          !_sameSet(_absent, _absentBefore));

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _save() async {
    final data = _data;
    if (data == null || _saving) return;
    setState(() => _saving = true);
    final topic = _topic.text.trim();
    try {
      await ref
          .read(classRegisterRepositoryProvider)
          .save(
            widget.account,
            widget.periods,
            data,
            ClassRegChanges(
              topic: topic != _topicBefore.trim() ? topic : null,
              markAbsent: _absent.difference(_absentBefore),
              markPresent: _absentBefore.difference(_absent),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Class register saved')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: ${_message(e)}')));
    }
  }

  static String _message(Object e) =>
      e is UntisException ? e.message : e.toString();

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('The absences and topic are not saved yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title),
              Text(widget.subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        body: _body(theme),
        bottomNavigationBar: _data == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    key: const ValueKey('classreg-save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _checked && !_dirty
                          ? 'Save'
                          : 'Save and confirm attendance',
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load the class register: ${_message(_loadError!)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final absentCount = _absent.length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            key: const ValueKey('classreg-topic'),
            controller: _topic,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Lesson topic',
              hintText: 'What was covered in this lesson',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Absences', style: theme.textTheme.titleMedium),
              ),
              Chip(
                avatar: Icon(
                  _checked ? Icons.check_circle : Icons.pending_outlined,
                  size: 18,
                ),
                label: Text(_checked ? 'Checked' : 'Not checked yet'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _students.isEmpty
                ? 'The server sent no pupils for this lesson.'
                : '${_students.length - absentCount} present · '
                      '$absentCount absent — tap a pupil to switch',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final s in _students) _studentTile(theme, s),
      ],
    );
  }

  Widget _studentTile(ThemeData theme, ClassRegStudent s) {
    final absent = _absent.contains(s.id);
    final cs = theme.colorScheme;
    return ListTile(
      key: ValueKey('classreg-student-${s.id}'),
      leading: CircleAvatar(
        backgroundColor: absent ? cs.errorContainer : cs.secondaryContainer,
        foregroundColor: absent ? cs.onErrorContainer : cs.onSecondaryContainer,
        child: Icon(absent ? Icons.close : Icons.check),
      ),
      title: Text(s.displayName),
      subtitle: Text(absent ? 'Absent' : 'Present'),
      onTap: _saving
          ? null
          : () => setState(() {
              absent ? _absent.remove(s.id) : _absent.add(s.id);
            }),
    );
  }
}
