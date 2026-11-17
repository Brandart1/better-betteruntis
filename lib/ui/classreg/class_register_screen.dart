import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/absence_summary.dart';
import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/pupil_photos.dart';
import '../../core/teacher_tools.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';
import 'absence_details_sheet.dart';
import 'absence_summary_screen.dart';
import 'homework_editor_screen.dart';
import 'pupil_avatar.dart';
import 'substitute_note.dart';

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
///
/// Also shows the topics of the course's previous lessons and the class
/// register entries ("Klassenbucheinträge") of this and recent lessons of
/// the course, and the homework given in this lesson (added / changed on
/// its own, not with Save); those load lazily after the screen is up.
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

  /// Times / reason / note per absent pupil where they aren't the whole
  /// block without reason and note (server / on screen).
  Map<int, AbsenceDetails> _detailsBefore = {};
  Map<int, AbsenceDetails> _details = {};
  Map<int, String> _absenceReasons = const {};

  DateTime get _blockStart => widget.periods
      .map((p) => p.start)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get _blockEnd =>
      widget.periods.map((p) => p.end).reduce((a, b) => a.isAfter(b) ? a : b);
  String _topicBefore = '';

  List<ClassRegStudent> _students = const [];

  /// Entries of this lesson block.
  List<ClassRegEvent> _events = const [];

  /// Earlier lessons of the course (null while loading).
  CourseHistory? _history;
  Object? _historyError;
  Map<int, String> _reasons = const {};

  /// Homework of the course given in this lesson (null while loading).
  List<Homework>? _homework;
  Object? _homeworkError;

  /// Homework saved here, by id: shown even when the server's lists don't
  /// have it yet.
  final _savedHomework = <int, Homework>{};

  /// Day of the course's next lesson (default due date), looked up once
  /// when homework is first added. Failures mean no default (a week later).
  late final Future<DateTime?> _nextLesson = Future<DateTime?>.sync(
    () => _repo.nextLessonDay(widget.account, widget.periods),
  ).catchError((Object _) => null);

  /// Only the two newest previous topics are shown until expanded, so the
  /// pupils stay near the top.
  bool _showAllTopics = false;

  /// The substitute who held this lesson instead of the account's teacher;
  /// then everything is read-only (it is the substitute's class register).
  /// Lessons the teacher substituted in themselves stay editable.
  late final ElementRef? _substitute =
      heldBySubstitute(widget.periods, widget.account.elementId)
      ? substituteOf(widget.periods.first, widget.account.elementId)
      : null;

  bool get _readOnly => _substitute != null;

  void _openSummary() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AbsenceSummaryScreen(
        account: widget.account,
        periods: widget.periods,
        title: widget.title,
      ),
    ),
  );

  ClassRegisterRepository get _repo =>
      ref.read(classRegisterRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
    _loadHomework();
    _loadReasons();
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
      final d = await _repo.load(widget.account, widget.periods);
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
      final details = <int, AbsenceDetails>{};
      for (final s in absent) {
        final mine = [
          for (final r in regs) ...r.absences.where((a) => a.studentId == s),
        ];
        final d = AbsenceDetails(
          start: mine
              .map((a) => a.start)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          end: mine.map((a) => a.end).reduce((a, b) => a.isAfter(b) ? a : b),
          reasonId: mine.map((a) => a.reasonId).nonNulls.firstOrNull,
          text:
              mine
                  .map((a) => a.text.trim())
                  .where((t) => t.isNotEmpty)
                  .firstOrNull ??
              '',
        );
        if (_isPlain(d)) continue;
        details[s] = d;
      }
      final topic = regs
          .map((r) => r.topic)
          .firstWhere((t) => t.trim().isNotEmpty, orElse: () => '');
      setState(() {
        _data = d;
        _students = students;
        _absentBefore = absent;
        _absent = {...absent};
        _detailsBefore = details;
        _details = {...details};
        _topicBefore = topic;
        _topic.text = topic;
        _events = _blockEvents(d);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Entries of every period of the block, each once, newest first.
  List<ClassRegEvent> _blockEvents(PeriodRegisterData d) {
    final seen = <int>{};
    final out = <ClassRegEvent>[];
    for (final p in widget.periods) {
      for (final e in d.periods[p.id]?.events ?? const <ClassRegEvent>[]) {
        if (e.id != null && !seen.add(e.id!)) continue;
        out.add(e.inLesson(p.id, p.start));
      }
    }
    return out..sort((a, b) => b.date!.compareTo(a.date!));
  }

  Future<void> _loadHistory() async {
    setState(() {
      _history = null;
      _historyError = null;
    });
    try {
      final h = await _repo.courseHistory(widget.account, widget.periods);
      if (mounted) setState(() => _history = h);
    } catch (e) {
      if (mounted) setState(() => _historyError = e);
    }
  }

  Future<void> _loadHomework() async {
    setState(() => _homeworkError = null);
    try {
      final loaded = await _repo.homework(widget.account, widget.periods);
      final byId = {..._savedHomework, for (final h in loaded) h.id: h};
      if (mounted) {
        setState(
          () =>
              _homework = byId.values.toList()
                ..sort((a, b) => a.endDate.compareTo(b.endDate)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _homeworkError = e);
    }
  }

  Future<void> _editHomework([Homework? initial]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HomeworkEditorScreen(
          given: _blockStart,
          initial: initial,
          nextLesson: initial == null ? _nextLesson : null,
          onSubmit: (h) async {
            final s = await _repo.saveHomework(
              widget.account,
              widget.periods,
              h,
            );
            if (s.id > 0) _savedHomework[s.id] = s;
          },
        ),
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Homework saved')));
    // Only the homework is reloaded, so unsaved absences / topic stay.
    await _loadHomework();
  }

  Future<void> _loadReasons() async {
    final a = await _repo.absenceReasons(widget.account);
    if (mounted && a.isNotEmpty) setState(() => _absenceReasons = a);
    final r = await _repo.eventReasons(widget.account);
    if (mounted && r.isNotEmpty) setState(() => _reasons = r);
  }

  /// The whole block without reason and note: the default absence.
  bool _isPlain(AbsenceDetails d) =>
      !d.start.isAfter(_blockStart) &&
      !d.end.isBefore(_blockEnd) &&
      !d.hasReasonOrText;

  /// Changed details of the absent pupils for [ClassRegChanges.details]:
  /// a pupil set back to the whole lesson gets it explicitly.
  Map<int, AbsenceDetails> get _changedDetails => {
    for (final s in _absent)
      if (_details[s] != _detailsBefore[s])
        s: _details[s] ?? AbsenceDetails(start: _blockStart, end: _blockEnd),
  };

  Future<void> _editAbsence(ClassRegStudent s) async {
    final d = await showAbsenceDetailsSheet(
      context,
      pupil: s.displayName,
      start: _blockStart,
      end: _blockEnd,
      now: ref.read(teacherToolsClockProvider)(),
      reasons: _absenceReasons,
      initial: _details[s.id],
    );
    if (d == null || !mounted) return;
    setState(() {
      _absent.add(s.id);
      if (_isPlain(d)) {
        _details.remove(s.id);
      } else {
        _details[s.id] = d;
      }
    });
  }

  List<PeriodRegister> get _regs => [
    for (final p in widget.periods) ?_data?.periods[p.id],
  ];

  bool get _checked => _regs.isNotEmpty && _regs.every((r) => r.absenceChecked);

  bool get _dirty =>
      _data != null &&
      (_topic.text.trim() != _topicBefore.trim() ||
          !_sameSet(_absent, _absentBefore) ||
          _changedDetails.isNotEmpty);

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _save() async {
    final data = _data;
    if (data == null || _saving) return;
    setState(() => _saving = true);
    final topic = _topic.text.trim();
    try {
      await _repo.save(
        widget.account,
        widget.periods,
        data,
        ClassRegChanges(
          topic: topic != _topicBefore.trim() ? topic : null,
          markAbsent: _absent.difference(_absentBefore),
          markPresent: _absentBefore.difference(_absent),
          details: _changedDetails,
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

  void _useTopic(String topic) {
    setState(() {
      _topic.text = topic;
      _topic.selection = TextSelection.collapsed(offset: topic.length);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Topic copied into the field')),
      );
  }

  /// All pupils known from this lesson and the course's earlier lessons.
  Map<int, ClassRegStudent> get _knownStudents => {
    ...?_history?.students,
    ...?_data?.students,
    for (final s in _students) s.id: s,
  };

  Future<void> _newEntry() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NewClassRegEntryScreen(
          students: _students,
          reasons: _reasons,
          onSubmit: (e) => _repo.createEvent(widget.account, widget.periods, e),
        ),
      ),
    );
    if (created != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Entry created')));
    // Only the entries are reloaded, so unsaved absences / topic stay.
    try {
      final d = await _repo.load(widget.account, widget.periods);
      if (mounted) setState(() => _events = _blockEvents(d));
    } catch (_) {}
  }

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
          actions: [_photosToggle()],
        ),
        body: _body(theme),
        bottomNavigationBar: _data == null || _readOnly
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (_readOnly)
          SubstituteNote(
            name: substituteName(
              _substitute,
              ref.watch(nameResolverProvider).value,
            ),
          ),
        // The topic is the main thing besides the absences: own heading,
        // tinted field and larger text.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Lesson topic', style: theme.textTheme.titleMedium),
              Chip(
                key: const ValueKey('classreg-topic-state'),
                avatar: isLargeText(context)
                    ? null
                    : Icon(
                        _topicBefore.trim().isNotEmpty
                            ? Icons.check_circle
                            : Icons.pending_outlined,
                        size: 18,
                      ),
                label: Text(
                  _topicBefore.trim().isNotEmpty
                      ? 'Entered'
                      : 'Not entered yet',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const ValueKey('classreg-topic'),
            controller: _topic,
            readOnly: _readOnly,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: theme.textTheme.titleMedium,
            decoration: InputDecoration(
              hintText: 'What was covered in this lesson',
              prefixIcon: const Icon(Icons.menu_book_outlined),
              filled: true,
              fillColor: theme.colorScheme.primaryContainer.withValues(
                alpha: 0.35,
              ),
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
            ),
          ),
        ),
        ..._previousTopics(theme, muted),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          // Large text: the chip goes below the title instead of squeezing it.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Absences', style: theme.textTheme.titleMedium),
              Chip(
                avatar: isLargeText(context)
                    ? null
                    : Icon(
                        _checked ? Icons.check_circle : Icons.pending_outlined,
                        size: 18,
                      ),
                label: Text(_checked ? 'Checked' : 'Not checked yet'),
                visualDensity: VisualDensity.compact,
              ),
              // Absence summary (lesson / subject / all subjects).
              TextButton.icon(
                key: const ValueKey('classreg-summary'),
                onPressed: _openSummary,
                icon: isLargeText(context)
                    ? null
                    : const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Summary'),
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
                      '$absentCount absent'
                      '${_readOnly ? '' : ' — tap a pupil to switch'}',
            style: muted,
          ),
        ),
        for (final s in _students) _studentTile(theme, s),
        ..._homeworkSection(theme, muted),
        ..._entries(theme, muted),
      ],
    );
  }

  // ---- Previous topics -------------------------------------------------

  List<Widget> _previousTopics(ThemeData theme, TextStyle? muted) {
    final h = _history;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text('Previous topics', style: theme.textTheme.titleSmall),
      ),
      if (_historyError != null)
        _inlineError(
          'Could not load earlier lessons: ${_message(_historyError!)}',
          muted,
        )
      else if (h == null)
        _inlineLoading('Loading earlier lessons…', muted)
      else if (h.topics.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            h.lessonsLoaded == 0
                ? 'No earlier lessons of this course in the last weeks.'
                : 'No topics entered in the earlier lessons of this course.',
            style: muted,
          ),
        )
      else ...[
        if (!_readOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Text('Tap one to copy it into the field', style: muted),
          ),
        for (final l in _showAllTopics ? h.topics : h.topics.take(2))
          _topicTile(theme, l),
        if (h.topics.length > 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('classreg-prev-topics-more'),
                onPressed: () =>
                    setState(() => _showAllTopics = !_showAllTopics),
                child: Text(
                  _showAllTopics
                      ? 'Show fewer'
                      : 'Show ${h.topics.length - 2} more',
                ),
              ),
            ),
          ),
      ],
    ];
  }

  Widget _topicTile(ThemeData theme, ClassRegLesson l) {
    final topic = l.register.topic.trim();
    final large = isLargeText(context);
    return ListTile(
      key: ValueKey('classreg-prev-topic-${l.period.id}'),
      dense: !large,
      title: Text(topic),
      subtitle: Text(
        l.substitutedBy == null
            ? _date(l.period.start)
            : '${_date(l.period.start)} · substitute '
                  '${substituteName(l.substitutedBy, ref.watch(nameResolverProvider).value)}',
      ),
      trailing: large || _readOnly
          ? null
          : const Icon(Icons.content_copy, size: 18),
      onTap: _saving || _readOnly ? null : () => _useTopic(topic),
    );
  }

  String _date(DateTime d) => dateFormat(context, 'EEE d MMM').format(d);

  Widget _inlineLoading(String text, TextStyle? muted) => Padding(
    key: const ValueKey('classreg-history-loading'),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: muted),
        const SizedBox(height: 6),
        const LinearProgressIndicator(),
      ],
    ),
  );

  Widget _inlineError(String text, TextStyle? muted) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          text,
          style: muted?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          key: const ValueKey('classreg-history-retry'),
          onPressed: _loadHistory,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  // ---- Homework --------------------------------------------------------

  List<Widget> _homeworkSection(ThemeData theme, TextStyle? muted) {
    final list = _homework;
    final title = Text('Homework', style: theme.textTheme.titleMedium);
    final button = FilledButton.tonalIcon(
      key: const ValueKey('classreg-new-homework'),
      onPressed: _saving || _readOnly ? null : _editHomework,
      icon: const Icon(Icons.add),
      label: const Text('Add homework'),
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: isLargeText(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 8), button],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  button,
                ],
              ),
      ),
      if (_homeworkError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'Could not load the homework: ${_message(_homeworkError!)}',
                style: muted?.copyWith(color: theme.colorScheme.error),
              ),
              TextButton(
                key: const ValueKey('classreg-homework-retry'),
                onPressed: _loadHomework,
                child: const Text('Retry'),
              ),
            ],
          ),
        )
      else if (list == null)
        const Padding(
          key: ValueKey('classreg-homework-loading'),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: LinearProgressIndicator(),
        )
      else if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('No homework given in this lesson.', style: muted),
        )
      else
        for (final h in list) _homeworkTile(h),
    ];
  }

  Widget _homeworkTile(Homework h) {
    final lines = [
      ['Due ${_date(h.endDate)}', if (h.completed) 'done'].join(' · '),
      if (h.remark.trim().isNotEmpty) 'Remark: ${h.remark.trim()}',
    ].join('\n');
    return ListTile(
      key: ValueKey('classreg-homework-${h.id}'),
      leading: isLargeText(context)
          ? null
          : Icon(h.completed ? Icons.task_alt : Icons.assignment_outlined),
      title: Text(h.text),
      subtitle: Text(lines),
      trailing: isLargeText(context) || _readOnly
          ? null
          : const Icon(Icons.edit_outlined, size: 18),
      onTap: _saving || _readOnly ? null : () => _editHomework(h),
    );
  }

  // ---- Class register entries ------------------------------------------

  List<Widget> _entries(ThemeData theme, TextStyle? muted) {
    final h = _history;
    final title = Text(
      'Class register entries',
      style: theme.textTheme.titleMedium,
    );
    final button = FilledButton.tonalIcon(
      key: const ValueKey('classreg-new-entry'),
      onPressed: _saving || _readOnly ? null : _newEntry,
      icon: const Icon(Icons.add),
      label: const Text('New entry'),
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: isLargeText(context)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 8), button],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  button,
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('This lesson', style: theme.textTheme.titleSmall),
      ),
      if (_events.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('No entries in this lesson.', style: muted),
        )
      else
        for (final e in _events) _eventTile(theme, e),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'Recent entries in this course',
          style: theme.textTheme.titleSmall,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        child: Text(
          'From the earlier lessons of this course in your timetable '
          '(entries made by other teachers in other lessons are not shown).',
          style: muted,
        ),
      ),
      if (_historyError != null)
        _inlineError(
          'Could not load earlier lessons: ${_message(_historyError!)}',
          muted,
        )
      else if (h == null)
        _inlineLoading('Loading earlier lessons…', muted)
      else if (h.events.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('No entries found.', style: muted),
        )
      else
        for (final e in h.events) _eventTile(theme, e),
    ];
  }

  Widget _eventTile(ThemeData theme, ClassRegEvent e) {
    final students = _knownStudents;
    final who = e.studentId != null
        ? (students[e.studentId]?.displayName ??
              (e.studentName.isNotEmpty
                  ? e.studentName
                  : 'Pupil #${e.studentId}'))
        : (e.studentName.isNotEmpty ? e.studentName : 'Whole class');
    final reason =
        _reasons[e.reasonId] ??
        (e.reasonName.isNotEmpty
            ? e.reasonName
            : (e.reasonId != null ? 'Reason #${e.reasonId}' : null));
    final lines = [
      if (e.text.isNotEmpty) e.text,
      [
        if (e.date != null) _date(e.date!),
        if (e.author.isNotEmpty) e.author,
      ].join(' · '),
    ].where((s) => s.isNotEmpty).join('\n');
    return ListTile(
      key: ValueKey('classreg-entry-${e.ttId}-${e.id}'),
      leading: isLargeText(context)
          ? null
          : Icon(e.isClassWide ? Icons.groups_outlined : Icons.person_outline),
      title: Text(reason == null ? who : '$who · $reason'),
      subtitle: lines.isEmpty ? null : Text(lines),
    );
  }

  Widget _studentTile(ThemeData theme, ClassRegStudent s) {
    final absent = _absent.contains(s.id);
    return ListTile(
      key: ValueKey('classreg-student-${s.id}'),
      leading: PupilAvatar(account: widget.account, student: s, absent: absent),
      title: Text(s.displayName),
      subtitle: Text(
        absent
            ? describeAbsence(
                _details[s.id],
                _blockStart,
                _blockEnd,
                _absenceReasons,
              )
            : 'Present',
      ),
      trailing: _readOnly
          ? null
          : IconButton(
              key: ValueKey('classreg-absence-${s.id}'),
              tooltip: 'Late, left early, reason or note',
              icon: const Icon(Icons.more_time),
              onPressed: _saving ? null : () => _editAbsence(s),
            ),
      onTap: _saving || _readOnly
          ? null
          : () => setState(() {
              if (absent) {
                _absent.remove(s.id);
                _details.remove(s.id);
              } else {
                _absent.add(s.id);
              }
            }),
      onLongPress: () => showPupilPhotoDialog(context, ref, widget.account, s),
    );
  }

  /// App bar button to show / hide pupil photos (stored on this device).
  Widget _photosToggle() {
    final on = ref.watch(showPupilPhotosProvider);
    return IconButton(
      key: const ValueKey('classreg-photos-toggle'),
      tooltip: on ? 'Hide pupil photos' : 'Show pupil photos',
      icon: Icon(on ? Icons.hide_image_outlined : Icons.image_outlined),
      onPressed: () => ref.read(showPupilPhotosProvider.notifier).set(!on),
    );
  }
}

/// Form for a new class register entry: pupil (or the whole class), reason
/// (optional) and text. [onSubmit] sends it; its error stays visible here.
/// Pops with true once it was sent.
class NewClassRegEntryScreen extends StatefulWidget {
  const NewClassRegEntryScreen({
    super.key,
    required this.students,
    required this.reasons,
    required this.onSubmit,
  });

  final List<ClassRegStudent> students;
  final Map<int, String> reasons;
  final Future<void> Function(NewClassRegEvent event) onSubmit;

  @override
  State<NewClassRegEntryScreen> createState() => _NewClassRegEntryScreenState();
}

class _NewClassRegEntryScreenState extends State<NewClassRegEntryScreen> {
  final _text = TextEditingController();
  int? _studentId;
  int? _reasonId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && (_text.text.trim().isNotEmpty || _reasonId != null);

  String get _studentLabel {
    final id = _studentId;
    if (id == null) return 'Whole class';
    return widget.students
            .where((s) => s.id == id)
            .map((s) => s.displayName)
            .firstOrNull ??
        '#$id';
  }

  Future<void> _pickStudent() async {
    // 0 = whole class (pupil ids are positive).
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Pupil'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('classreg-entry-pupil-0'),
            onPressed: () => Navigator.of(c).pop(0),
            child: const Text('Whole class'),
          ),
          for (final s in widget.students)
            SimpleDialogOption(
              key: ValueKey('classreg-entry-pupil-${s.id}'),
              onPressed: () => Navigator.of(c).pop(s.id),
              child: Text(s.displayName),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() => _studentId = picked == 0 ? null : picked);
    }
  }

  Future<void> _pickReason() async {
    final sorted = widget.reasons.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    // -1 = no reason.
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Reason'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('classreg-entry-reason--1'),
            onPressed: () => Navigator.of(c).pop(-1),
            child: const Text('No reason'),
          ),
          for (final r in sorted)
            SimpleDialogOption(
              key: ValueKey('classreg-entry-reason-${r.key}'),
              onPressed: () => Navigator.of(c).pop(r.key),
              child: Text(r.value),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() => _reasonId = picked == -1 ? null : picked);
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        NewClassRegEvent(
          studentId: _studentId,
          reasonId: _reasonId,
          text: _text.text.trim(),
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
    return Scaffold(
      appBar: AppBar(title: const Text('New entry')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          ListTile(
            key: const ValueKey('classreg-entry-pupil'),
            leading: large ? null : const Icon(Icons.person_outline),
            title: const Text('Pupil'),
            subtitle: Text(_studentLabel),
            onTap: _sending ? null : _pickStudent,
          ),
          ListTile(
            key: const ValueKey('classreg-entry-reason'),
            leading: large ? null : const Icon(Icons.label_outline),
            title: const Text('Reason'),
            subtitle: Text(
              widget.reasons.isEmpty
                  ? 'No reasons known for this school'
                  : (_reasonId == null
                        ? 'No reason'
                        : widget.reasons[_reasonId] ?? '#$_reasonId'),
            ),
            onTap: _sending || widget.reasons.isEmpty ? null : _pickReason,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('classreg-entry-text'),
              controller: _text,
              minLines: 3,
              maxLines: 8,
              enabled: !_sending,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Text',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                key: const ValueKey('classreg-entry-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Could not create the entry: $_error',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('classreg-entry-send'),
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Create entry'),
            ),
          ),
        ],
      ),
    );
  }
}
