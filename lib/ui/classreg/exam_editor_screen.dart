import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/teacher_tools.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';
import 'room_booking_screen.dart';

/// Opens the exam editor. With [periods] (a lesson block of the teacher's
/// own timetable) everything is pre-filled from that lesson; without, the
/// teacher picks date, subject, classes and periods. Resolves to true when
/// an exam was created.
Future<bool> openExamEditor(
  BuildContext context, {
  required Account account,
  List<Period>? periods,
}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ExamEditorScreen(account: account, periods: periods),
    ),
  );
  return created ?? false;
}

/// Creates an exam on the server (teachers with the class register): type,
/// name, text, date, subject and classes (only what the teacher teaches),
/// periods (one or more consecutive units of the day), room and pupils.
class ExamEditorScreen extends ConsumerStatefulWidget {
  const ExamEditorScreen({super.key, required this.account, this.periods});

  final Account account;

  /// The lesson it was started from (null: from the exam menu).
  final List<Period>? periods;

  @override
  ConsumerState<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends ConsumerState<ExamEditorScreen> {
  final _name = TextEditingController();
  final _text = TextEditingController();

  late DateTime _date;
  int? _subjectId;
  Set<int> _klasseIds = {};

  /// Selected units of the day's time grid (inclusive), null: none.
  int? _from;
  int? _to;

  int? _roomId;

  /// Room of the lesson the editor was started from.
  int? _lessonRoom;

  TeacherCourses? _courses;
  Object? _coursesError;

  /// The teacher's own lessons on [_date] (null while loading).
  List<Period>? _dayLessons;

  List<ExamType> _types = const [];
  bool _typesLoaded = false;
  final _type = TextEditingController();

  List<ClassRegStudent>? _students;
  bool _loadingStudents = false;
  Set<int> _studentIds = {};

  bool _sending = false;
  String? _error;

  /// Default periods are applied once the day and the time grid are known.
  bool _pendingDefaults = false;

  TeacherToolsRepository get _repo => ref.read(teacherToolsRepositoryProvider);

  bool get _fromLesson => widget.periods?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    final ps = widget.periods;
    if (ps != null && ps.isNotEmpty) {
      final p = ps.first;
      _date = dateOnly(p.start);
      _subjectId = p
          .ofType(ElementType.subject)
          .map((e) => e.id)
          .where((id) => id != 0)
          .firstOrNull;
      _klasseIds = {
        for (final k in p.ofType(ElementType.klasse))
          if (k.id != 0) k.id,
      };
      final room = bookableRoomOf(p);
      if (room != null && room.id != 0) _lessonRoom = _roomId = room.id;
      _dayLessons = null;
    } else {
      var d = dateOnly(DateTime.now());
      while (d.weekday > 5) {
        d = addDays(d, 1);
      }
      _date = d;
    }
    _loadCourses();
    _loadDay(applyDefaults: true);
    unawaited(
      _repo.examTypes(widget.account).then((t) {
        if (mounted) {
          setState(() {
            _types = t;
            _typesLoaded = true;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() => _coursesError = null);
    try {
      final c = await _repo.courses(widget.account);
      if (mounted) setState(() => _courses = c);
    } catch (e) {
      if (mounted) setState(() => _coursesError = e);
    }
  }

  Future<void> _loadDay({bool applyDefaults = false}) async {
    final date = _date;
    setState(() => _dayLessons = null);
    List<Period> lessons;
    try {
      lessons = await _repo.lessonsOn(widget.account, date);
    } catch (_) {
      lessons = const [];
    }
    if (!mounted || date != _date) return;
    setState(() {
      _dayLessons = lessons;
      if (applyDefaults) _pendingDefaults = true;
    });
  }

  List<TimeUnit> _unitsOf(NameResolver? names) {
    final grid = names?.timeGrid.days[_date.weekday] ?? const <TimeUnit>[];
    if (grid.isNotEmpty) return grid;
    // No time grid: the day's own lessons are the units.
    final seen = <int>{};
    return [
      for (final p in _dayLessons ?? const <Period>[])
        if (seen.add(minuteOfDay(p.start)))
          TimeUnit(
            label: '',
            start: minuteOfDay(p.start),
            end: minuteOfDay(p.end),
          ),
    ];
  }

  /// Units overlapping [start]–[end] (minutes of the day).
  (int, int)? _unitRange(List<TimeUnit> units, int start, int end) {
    int? from;
    int? to;
    for (var i = 0; i < units.length; i++) {
      if (units[i].start < end && units[i].end > start) {
        from ??= i;
        to = i;
      }
    }
    return from == null ? null : (from, to!);
  }

  /// The own lessons of the day that match subject and classes.
  List<Period> _matchingLessons() => [
    for (final p in _dayLessons ?? const <Period>[])
      if (_subjectId != null &&
          p.canHoldExam &&
          p.ofType(ElementType.subject).any((s) => s.id == _subjectId) &&
          (_klasseIds.isEmpty ||
              p
                  .ofType(ElementType.klasse)
                  .any((k) => _klasseIds.contains(k.id))))
        p,
  ];

  /// Periods default: the lesson it was started from, else the day's
  /// lessons of that subject and class (the first block of them).
  void _applyDefaultUnits(NameResolver? names) {
    final units = _unitsOf(names);
    _from = _to = null;
    if (units.isEmpty) return;
    final ps = widget.periods;
    if (_fromLesson && dateOnly(ps!.first.start) == _date) {
      final start = ps
          .map((p) => minuteOfDay(p.start))
          .reduce((a, b) => a < b ? a : b);
      final end = ps
          .map((p) => minuteOfDay(p.end))
          .reduce((a, b) => a > b ? a : b);
      final r = _unitRange(units, start, end);
      if (r != null) {
        _from = r.$1;
        _to = r.$2;
      }
      return;
    }
    final match = _matchingLessons();
    if (match.isEmpty) return;
    final r = _unitRange(
      units,
      minuteOfDay(match.first.start),
      minuteOfDay(match.first.end),
    );
    if (r == null) return;
    var (from, to) = r;
    // A double lesson: the following units of the same course too.
    for (final p in match.skip(1)) {
      final n = _unitRange(units, minuteOfDay(p.start), minuteOfDay(p.end));
      if (n == null || n.$1 > to + 1) break;
      to = n.$2 > to ? n.$2 : to;
    }
    _from = from;
    _to = to;
  }

  void _tapUnit(int i) {
    setState(() {
      final from = _from;
      final to = _to;
      if (from == null || to == null) {
        _from = _to = i;
      } else if (i < from) {
        _from = i;
      } else if (i > to) {
        _to = i;
      } else if (from == to) {
        _from = _to = null;
      } else if (i == from) {
        _from = from + 1;
      } else {
        // Inside or the last one: the range ends just before it ([i] == to
        // drops the last unit).
        _to = i == to ? to - 1 : i;
      }
      _roomId = _roomId == _lessonRoom ? _roomId : null;
    });
  }

  ({DateTime start, DateTime end})? _span(List<TimeUnit> units) {
    final from = _from;
    final to = _to;
    if (from == null || to == null || to >= units.length) return null;
    DateTime at(int m) =>
        DateTime(_date.year, _date.month, _date.day, m ~/ 60, m % 60);
    return (start: at(units[from].start), end: at(units[to].end));
  }

  String get _typeName => _type.text.trim();

  bool _canSend(List<TimeUnit> units) =>
      !_sending &&
      _span(units) != null &&
      _klasseIds.isNotEmpty &&
      _subjectId != null &&
      (_name.text.trim().isNotEmpty || _typeName.isNotEmpty);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: addDays(dateOnly(DateTime.now()), -365),
      lastDate: addDays(dateOnly(DateTime.now()), 365),
    );
    if (picked == null || !mounted || dateOnly(picked) == _date) return;
    setState(() {
      _date = dateOnly(picked);
      _from = _to = null;
      _roomId = null;
    });
    await _loadDay(applyDefaults: true);
  }

  Future<void> _pickSubject(NameResolver? names) async {
    final c = _courses;
    final ids = {?_subjectId, ...?c?.subjectIds}.toList();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Subject'),
        children: [
          for (final id in ids)
            SimpleDialogOption(
              key: ValueKey('exam-subject-$id'),
              onPressed: () => Navigator.of(ctx).pop(id),
              child: Text(_elementName(names, ElementType.subject, id)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == _subjectId) return;
    setState(() {
      _subjectId = picked;
      final classes = c?.classesOf(picked) ?? const <int>{};
      // The classes of the day's lesson of that subject, else the only one.
      final day = [
        for (final p in _dayLessons ?? const <Period>[])
          if (p.ofType(ElementType.subject).any((s) => s.id == picked)) p,
      ];
      _klasseIds = day.isNotEmpty
          ? {
              for (final k in day.first.ofType(ElementType.klasse))
                if (k.id != 0) k.id,
            }
          : (classes.length == 1 ? {...classes} : {});
      _students = null;
      _studentIds = {};
      _applyDefaultUnits(names);
    });
  }

  Future<void> _pickRoom(List<TimeUnit> units) async {
    final span = _span(units);
    if (span == null) return;
    final picked = await pickFreeRoom(
      context,
      title: 'Room for the exam',
      subtitle:
          '${dateFormat(context, 'EEE d MMM').format(span.start)} · '
          '${hhmm(minuteOfDay(span.start))} – ${hhmm(minuteOfDay(span.end))}',
      load: () => _repo.freeRoomsBetween(widget.account, span.start, span.end),
      extra: [?_lessonRoom],
      selected: _roomId,
    );
    if (picked != null && mounted) setState(() => _roomId = picked);
  }

  Future<void> _pickStudents() async {
    var students = _students;
    if (students == null) {
      final lessons = _fromLesson ? widget.periods! : _matchingLessons();
      if (lessons.isEmpty) {
        setState(
          () => _error =
              'No lesson of this class on that day to load the pupils from.',
        );
        return;
      }
      setState(() => _loadingStudents = true);
      try {
        final d = await ref
            .read(classRegisterRepositoryProvider)
            .load(widget.account, lessons);
        students = d.students.values.toList()
          ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
      } catch (e) {
        if (mounted) {
          setState(() {
            _loadingStudents = false;
            _error = 'Could not load the pupils: ${teacherToolErrorText(e)}';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _loadingStudents = false;
        _students = students;
      });
    }
    final chosen = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _PupilPicker(students: students!, selected: _studentIds),
    );
    if (chosen != null && mounted) setState(() => _studentIds = chosen);
  }

  Future<void> _send(List<TimeUnit> units) async {
    final span = _span(units);
    if (!_canSend(units) || span == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final own = [
      for (final p in [...?widget.periods, ...?_dayLessons])
        if (p.start.isBefore(span.end) &&
            p.end.isAfter(span.start) &&
            p.ofType(ElementType.subject).any((s) => s.id == _subjectId))
          p,
    ];
    final periodIds = <int>{for (final p in own) p.id}.toList();
    final lessonId = own
        .map((p) => p.lessonId)
        .where((id) => id > 0)
        .firstOrNull;
    try {
      await _repo.createExam(
        widget.account,
        NewExam(
          // An exam's type is a plain string: no id.
          examType: _typeName,
          name: _name.text.trim(),
          text: _text.text.trim(),
          start: span.start,
          end: span.end,
          roomIds: [?_roomId],
          klasseIds: _klasseIds.toList()..sort(),
          studentIds: _studentIds.toList()..sort(),
          teacherIds: [widget.account.elementId],
          subjectId: _subjectId,
          lessonId: lessonId,
          periodIds: periodIds,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = teacherToolErrorText(e);
      });
    }
  }

  static String _elementName(NameResolver? names, ElementType t, int id) =>
      names?.longName(ElementRef(type: t, id: id, orgId: id)) ?? '#$id';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final large = isLargeText(context);
    final names = ref.watch(nameResolverProvider).value;
    if (_pendingDefaults && names != null && _dayLessons != null) {
      _pendingDefaults = false;
      _applyDefaultUnits(names);
    }
    final units = _unitsOf(names);
    final span = _span(units);
    Widget? icon(IconData i) => large ? null : Icon(i);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall),
    );

    final subjectClasses = _subjectId == null
        ? <int>{}
        : {...?_courses?.classesOf(_subjectId!), ..._klasseIds};
    final match = _matchingLessons();

    return Scaffold(
      appBar: AppBar(title: const Text('New exam')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey('exam-type'),
                  controller: _type,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Exam type',
                    hintText: 'e.g. Schularbeit',
                    prefixIcon: const Icon(Icons.category_outlined),
                    border: const OutlineInputBorder(),
                    helperText: !_typesLoaded
                        ? 'Loading known exam types…'
                        : (_types.isEmpty
                              ? 'Type the exam type; none known yet.'
                              : null),
                  ),
                ),
                if (_types.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in _types)
                          ChoiceChip(
                            key: ValueKey('exam-type-${t.id}'),
                            label: Text(t.displayName),
                            selected: _typeName == t.displayName,
                            onSelected: _sending
                                ? null
                                : (_) => setState(
                                    () => _type.text = t.displayName,
                                  ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('exam-name'),
              controller: _name,
              enabled: !_sending,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Bruchrechnung',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const ValueKey('exam-text'),
              controller: _text,
              enabled: !_sending,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Text (optional)',
                hintText: 'Topics, allowed aids',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          section('When'),
          ListTile(
            key: const ValueKey('exam-date'),
            leading: icon(Icons.event_outlined),
            title: const Text('Date'),
            subtitle: Text(dateFormat(context, 'EEEE d MMMM y').format(_date)),
            onTap: _sending ? null : _pickDate,
          ),
          ListTile(
            key: const ValueKey('exam-subject'),
            leading: icon(Icons.menu_book_outlined),
            title: const Text('Subject'),
            subtitle: Text(
              _subjectId == null
                  ? (_courses == null && _coursesError == null
                        ? 'Loading your subjects…'
                        : 'Choose a subject')
                  : _elementName(names, ElementType.subject, _subjectId!),
            ),
            onTap: _sending || (_courses == null && _subjectId == null)
                ? null
                : () => _pickSubject(names),
          ),
          if (_coursesError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Could not load your subjects: '
                      '${teacherToolErrorText(_coursesError!)}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('exam-subjects-retry'),
                    onPressed: _loadCourses,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_courses != null && _courses!.isEmpty && !_fromLesson)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'No lessons found in your timetable of the last and next weeks.',
              ),
            ),
          if (_subjectId != null) ...[
            section('Classes'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in subjectClasses)
                    FilterChip(
                      key: ValueKey('exam-class-$k'),
                      label: Text(
                        names?.shortName(
                              ElementRef(
                                type: ElementType.klasse,
                                id: k,
                                orgId: k,
                              ),
                            ) ??
                            '#$k',
                      ),
                      selected: _klasseIds.contains(k),
                      onSelected: _sending
                          ? null
                          : (on) => setState(() {
                              _klasseIds = {..._klasseIds};
                              on ? _klasseIds.add(k) : _klasseIds.remove(k);
                              _students = null;
                              _studentIds = {};
                            }),
                    ),
                ],
              ),
            ),
          ],
          section('Periods'),
          if (_dayLessons == null && units.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            )
          else if (units.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text('No periods known for this day.'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < units.length; i++)
                    FilterChip(
                      key: ValueKey('exam-unit-$i'),
                      showCheckmark: !large,
                      label: Text(
                        units[i].label.isNotEmpty
                            ? units[i].label
                            : hhmm(units[i].start),
                      ),
                      tooltip:
                          '${hhmm(units[i].start)} – ${hhmm(units[i].end)}',
                      selected:
                          _from != null &&
                          _to != null &&
                          i >= _from! &&
                          i <= _to!,
                      onSelected: _sending ? null : (_) => _tapUnit(i),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                key: const ValueKey('exam-time'),
                span == null
                    ? 'Tap the periods the exam takes (consecutive).'
                    : '${hhmm(minuteOfDay(span.start))} – ${hhmm(minuteOfDay(span.end))}'
                          '${_to! > _from! ? ' · ${_to! - _from! + 1} periods' : ''}',
              ),
            ),
            if (!_fromLesson &&
                _subjectId != null &&
                _dayLessons != null &&
                match.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  key: const ValueKey('exam-no-lesson'),
                  'You have no lesson of this subject and class on that day.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          section('Where and who'),
          ListTile(
            key: const ValueKey('exam-room'),
            leading: icon(Icons.meeting_room_outlined),
            title: const Text('Room'),
            subtitle: Text(
              _roomId == null
                  ? 'No room'
                  : _elementName(names, ElementType.room, _roomId!),
            ),
            trailing: _roomId == null || _sending
                ? null
                : IconButton(
                    key: const ValueKey('exam-room-clear'),
                    tooltip: 'No room',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _roomId = null),
                  ),
            onTap: _sending || span == null ? null : () => _pickRoom(units),
          ),
          ListTile(
            key: const ValueKey('exam-pupils'),
            leading: icon(Icons.groups_outlined),
            title: const Text('Pupils'),
            subtitle: Text(
              _loadingStudents
                  ? 'Loading pupils…'
                  : _studentIds.isEmpty
                  ? 'All pupils of the selected classes'
                  : '${_studentIds.length} of ${_students?.length ?? '?'} pupils',
            ),
            onTap: _sending || _loadingStudents || _klasseIds.isEmpty
                ? null
                : _pickStudents,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ErrorBox(
                'Could not create the exam: $_error',
                key: const ValueKey('exam-error'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('exam-send'),
              onPressed: _canSend(units) ? () => _send(units) : null,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Create exam'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'The exam is created on the school server; it then shows in '
              'the timetable and the exam list.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-select of the pupils taking part; none selected = all.
class _PupilPicker extends StatefulWidget {
  const _PupilPicker({required this.students, required this.selected});
  final List<ClassRegStudent> students;
  final Set<int> selected;

  @override
  State<_PupilPicker> createState() => _PupilPickerState();
}

class _PupilPickerState extends State<_PupilPicker> {
  late Set<int> _ids = widget.selected.isEmpty
      ? {for (final s in widget.students) s.id}
      : {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final all = _ids.length == widget.students.length;
    return AlertDialog(
      title: const Text('Pupils'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            CheckboxListTile(
              key: const ValueKey('exam-pupil-all'),
              title: const Text('All'),
              value: all,
              onChanged: (v) => setState(
                () => _ids = v == true
                    ? {for (final s in widget.students) s.id}
                    : {},
              ),
            ),
            for (final s in widget.students)
              CheckboxListTile(
                key: ValueKey('exam-pupil-${s.id}'),
                title: Text(s.displayName),
                value: _ids.contains(s.id),
                onChanged: (v) => setState(() {
                  _ids = {..._ids};
                  v == true ? _ids.add(s.id) : _ids.remove(s.id);
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('exam-pupils-done'),
          onPressed: _ids.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  // Everyone = all (no list sent).
                  _ids.length == widget.students.length ? <int>{} : _ids,
                ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
