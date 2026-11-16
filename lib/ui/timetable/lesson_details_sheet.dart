import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calendar/calendar_sync_service.dart';
import '../../core/accessibility.dart';
import '../../core/colleague_lessons.dart';
import '../../core/interfaces.dart';
import '../../core/lesson_notes.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/teacher_tools.dart';
import 'lesson_layout.dart';
import 'lesson_style.dart';
import 'timetable_utils.dart';

/// The lesson sheet's room row: [action] on [block].
typedef RoomActionCallback = void Function(
  LessonBlock block,
  RoomAction action,
);

/// Opens the lesson details for [blocks] (several = overlapping lessons, shown
/// in a pager) starting at [index].
Future<void> showLessonDetails(
  BuildContext context, {
  required List<LessonBlock> blocks,
  required int index,
  required NameResolver names,
  ValueChanged<TimetableTarget>? onOpenElement,
  ValueChanged<LessonBlock>? onOpenClassRegister,
  RoomActionCallback? onRoomAction,
  ValueChanged<LessonBlock>? onCreateExam,
  ValueChanged<LessonBlock>? onEditLessonInfo,
  int? ownTeacherId,
}) {
  ValueChanged<LessonBlock>? closing(
    BuildContext sheetContext,
    ValueChanged<LessonBlock>? cb,
  ) => cb == null
      ? null
      : (b) {
          Navigator.of(sheetContext).pop();
          cb(b);
        };

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => LessonDetailsSheet(
      blocks: blocks,
      initialIndex: index,
      names: names,
      onOpenElement: onOpenElement == null
          ? null
          : (t) {
              Navigator.of(sheetContext).pop();
              onOpenElement(t);
            },
      onOpenClassRegister: onOpenClassRegister == null
          ? null
          : (b) {
              Navigator.of(sheetContext).pop();
              onOpenClassRegister(b);
            },
      onRoomAction: onRoomAction == null
          ? null
          : (b, a) {
              Navigator.of(sheetContext).pop();
              onRoomAction(b, a);
            },
      onCreateExam: closing(sheetContext, onCreateExam),
      onEditLessonInfo: closing(sheetContext, onEditLessonInfo),
      ownTeacherId: ownTeacherId,
    ),
  );
}

/// Bottom-sheet content: one [LessonDetailsPage] or a pager of them.
class LessonDetailsSheet extends StatefulWidget {
  const LessonDetailsSheet({
    super.key,
    required this.blocks,
    required this.names,
    this.initialIndex = 0,
    this.onOpenElement,
    this.onOpenClassRegister,
    this.onRoomAction,
    this.onCreateExam,
    this.onEditLessonInfo,
    this.ownTeacherId,
  });

  final List<LessonBlock> blocks;
  final NameResolver names;
  final int initialIndex;
  final ValueChanged<TimetableTarget>? onOpenElement;

  /// Teachers' own timetable: opens the class register of a block.
  final ValueChanged<LessonBlock>? onOpenClassRegister;

  /// Teachers' own timetable: replace / remove / add a room of a block
  /// (offered until the lesson starts).
  final RoomActionCallback? onRoomAction;

  /// Teachers with the class register: creates an exam on the server
  /// (replaces the device-only "Mark as exam").
  final ValueChanged<LessonBlock>? onCreateExam;

  /// Teachers with the class register: edits the lesson info everyone sees
  /// on the server (replaces the device-only "Add details").
  final ValueChanged<LessonBlock>? onEditLessonInfo;

  /// Set in a teacher's own timetable: lessons someone else gives say so,
  /// and colleagues' lessons get none of the own-lesson actions.
  final int? ownTeacherId;

  @override
  State<LessonDetailsSheet> createState() => _LessonDetailsSheetState();
}

class _LessonDetailsSheetState extends State<LessonDetailsSheet> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    final pages = [
      for (final b in widget.blocks)
        LessonDetailsPage(
          block: b,
          names: widget.names,
          onOpenElement: widget.onOpenElement,
          onOpenClassRegister: widget.onOpenClassRegister,
          onRoomAction: widget.onRoomAction,
          onCreateExam: widget.onCreateExam,
          onEditLessonInfo: widget.onEditLessonInfo,
          ownTeacherId: widget.ownTeacherId,
        ),
    ];
    if (pages.length == 1) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: pages.first,
      );
    }
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Text(
            '${_page + 1} / ${pages.length}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}

/// Details of one (possibly merged) lesson.
class LessonDetailsPage extends ConsumerWidget {
  const LessonDetailsPage({
    super.key,
    required this.block,
    required this.names,
    this.onOpenElement,
    this.onOpenClassRegister,
    this.onRoomAction,
    this.onCreateExam,
    this.onEditLessonInfo,
    this.ownTeacherId,
  });

  final LessonBlock block;
  final NameResolver names;
  final ValueChanged<TimetableTarget>? onOpenElement;
  final ValueChanged<LessonBlock>? onOpenClassRegister;
  final RoomActionCallback? onRoomAction;
  final ValueChanged<LessonBlock>? onCreateExam;
  final ValueChanged<LessonBlock>? onEditLessonInfo;

  /// See [LessonDetailsSheet.ownTeacherId].
  final int? ownTeacherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A colleague's lesson in the teacher's own timetable (shown faded):
    // read-only, none of the own-lesson actions. Lessons a substitute holds
    // for them keep theirs (the class register opens read-only).
    final me = ownTeacherId;
    final colleague = me != null && isColleagueLesson(this.block.first, me);
    final notOwn = me != null && !teachesLesson(this.block.first, me);
    final onOpenClassRegister = colleague ? null : this.onOpenClassRegister;
    final onRoomAction = colleague ? null : this.onRoomAction;
    final onCreateExam = colleague ? null : this.onCreateExam;
    final onEditLessonInfo = colleague ? null : this.onEditLessonInfo;
    // The sheet stays open while the user edits their notes: apply the
    // current ones instead of those the block was built with.
    final notes = ref.watch(lessonNotesProvider);
    final block = LessonBlock([
      for (final q in this.block.periods)
        if (q.noteKey case final key?)
          q.withUserNote(
            noteKey: key,
            userExam: notes[key]?.exam ?? false,
            userNote: notes[key]?.text ?? '',
            userHomework: notes[key]?.homework ?? '',
          )
        else
          q,
    ]);
    final noteKeys = [for (final q in block.periods) ?q.noteKey];
    final theme = Theme.of(context);
    final settings = ref.watch(timetableSettingsProvider);
    final accent = LessonStyle.of(
      theme.colorScheme,
      block,
      settings,
      names,
      ref.watch(accessibilityProvider.select((a) => a.highContrast)),
    );
    final p = block.first;
    final subjects = p.ofType(ElementType.subject).toList();
    final title = subjects.isNotEmpty
        ? subjects.map((s) => names.longName(s, original: s.id == 0)).join(', ')
        : (p.customTitle.isNotEmpty ? p.customTitle : 'Lesson');
    final numbers = lessonNumbers(names.timeGrid, block.start, block.end);
    final when = [
      dateFormat(context, 'EEE d MMM').format(block.start),
      '${hhmm(minuteOfDay(block.start))} – ${hhmm(minuteOfDay(block.end))}',
      if (numbers.isNotEmpty) 'Lesson $numbers',
    ].join(' · ');

    final texts = <String>{
      for (final q in block.periods) ...[
        q.substitutionText,
        q.lessonText,
        q.infoText,
      ],
      if (p.exam != null) ...[p.exam!.name, p.exam!.text],
    }.where((t) => t.trim().isNotEmpty && t.trim() != title).toList();
    final homework = <int, Homework>{
      for (final h in block.periods.expand((q) => q.homework)) h.id: h,
    }.values.toList();
    final link = block.periods
        .map((q) => q.onlineLink)
        .firstWhereOrNull((l) => l != null && l.isNotEmpty);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('details-accent'),
                width: 6,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: accent.background,
                  border: accent.border == null
                      ? null
                      : Border.all(color: accent.border!, width: 1.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      when,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _StatusChips(block: block, settings: settings),
        if (notOwn) _NotOwnNote(period: p, names: names, colleague: colleague),
        // No class register for supervisions or lessons without a class.
        if (onOpenClassRegister != null &&
            !block.isCancelled &&
            block.periods.any((q) => !q.isCancelled && q.canHoldExam))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.tonalIcon(
              key: const ValueKey('details-classreg'),
              onPressed: () => onOpenClassRegister(this.block),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Absences & lesson topic'),
            ),
          ),
        if (onCreateExam != null &&
            !block.isCancelled &&
            // Never in supervisions or anything without a class.
            block.periods.any((q) => !q.isCancelled && q.canHoldExam) &&
            !block.periods.any((q) => q.isSchoolExam))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('lesson-exam-create'),
              onPressed: () => onCreateExam(this.block),
              icon: const Icon(Icons.assignment_add),
              label: const Text('Create exam'),
            ),
          ),
        if (noteKeys.isNotEmpty || onEditLessonInfo != null)
          _UserNoteSection(
            block: block,
            noteKeys: noteKeys,
            serverExams: onCreateExam != null,
            onEditLessonInfo: onEditLessonInfo == null
                ? null
                : () => onEditLessonInfo(this.block),
          ),
        _ElementSection(
          'Teachers',
          ElementType.teacher,
          p,
          names,
          onOpenElement,
        ),
        _ElementSection('Classes', ElementType.klasse, p, names, onOpenElement),
        if (onRoomAction != null && !block.isCancelled)
          _RoomSection(
            period: p,
            names: names,
            onOpen: onOpenElement,
            // Rooms can only change before the lesson starts.
            editable: ref
                .watch(teacherToolsClockProvider)()
                .isBefore(block.start),
            onAction: (a) => onRoomAction(this.block, a),
          )
        else
          _ElementSection('Rooms', ElementType.room, p, names, onOpenElement),
        for (final t in texts)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        if (homework.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Homework', style: theme.textTheme.titleSmall),
          for (final h in homework)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                h.completed ? Icons.check_circle : Icons.menu_book_outlined,
              ),
              title: Text(h.text),
              subtitle: Text(
                [
                  'Due ${dateFormat(context, 'EEE d MMM').format(h.endDate)}',
                  if (h.remark.isNotEmpty) h.remark,
                ].join(' · '),
              ),
            ),
        ],
        if (p.isOnline || link != null) ...[
          const SizedBox(height: 16),
          if (link != null)
            FilledButton.tonalIcon(
              onPressed: () => launchUrl(
                Uri.parse(link),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Join online lesson'),
            )
          else
            const Row(
              children: [
                Icon(Icons.wifi),
                SizedBox(width: 8),
                Text('Online lesson'),
              ],
            ),
        ],
      ],
    );
  }
}

/// "Taught by …" on a lesson in a teacher's own timetable that someone else
/// gives.
class _NotOwnNote extends StatelessWidget {
  const _NotOwnNote({
    required this.period,
    required this.names,
    required this.colleague,
  });

  final Period period;
  final NameResolver names;

  /// A colleague's lesson (else one a substitute holds for the teacher).
  final bool colleague;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = [
      for (final t in period.ofType(ElementType.teacher))
        if (t.id != 0) names.longName(t),
    ].join(', ');
    final text = colleague
        ? '${who.isEmpty ? 'Another teacher' : who} teaches this lesson. '
              'It shows in your timetable because you teach this subject in '
              'this class.'
        : who.isEmpty
        ? "You don't give this lesson."
        : '$who holds this lesson instead of you.';
    return Padding(
      key: const ValueKey('details-not-own'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.block, required this.settings});
  final LessonBlock block;
  final TimetableSettings settings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    (Color, Color) colors(int? custom, Color bg, Color fg) =>
        custom == null ? (bg, fg) : (Color(custom), onColorFor(Color(custom)));
    final (cBg, cFg) = colors(
      settings.cancelledColor,
      cs.errorContainer,
      cs.onErrorContainer,
    );
    final (eBg, eFg) = colors(
      settings.examColor,
      cs.errorContainer,
      cs.onErrorContainer,
    );
    final (iBg, iFg) = colors(
      settings.irregularColor,
      cs.tertiaryContainer,
      cs.onTertiaryContainer,
    );
    final (sDefBg, sDefFg, _) = supervisionDefaults(cs);
    final (sBg, sFg) = colors(settings.supervisionColor, sDefBg, sDefFg);
    final (rDefBg, rDefFg, _) = roomBookingDefaults(cs);
    final (rBg, rFg) = colors(settings.roomBookingColor, rDefBg, rDefFg);
    final chips = <Widget>[
      if (block.isCancelled) _chip(Icons.block, 'Cancelled', cBg, cFg),
      if (block.isExam)
        _chip(
          Icons.assignment_outlined,
          block.periods.any((p) => p.isSchoolExam) ? 'Exam' : 'Custom exam',
          eBg,
          eFg,
        ),
      if (!block.isCancelled && block.isIrregular)
        _chip(Icons.swap_horiz, 'Substitution', iBg, iFg),
      if (!block.isCancelled && block.first.isBreakSupervision)
        _chip(Icons.visibility_outlined, 'Supervision', sBg, sFg),
      if (!block.isCancelled && block.first.isRoomBooking)
        _chip(Icons.meeting_room_outlined, 'Room booking', rBg, rFg),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  Widget _chip(IconData icon, String label, Color bg, Color fg) => Chip(
    avatar: Icon(icon, size: 18, color: fg),
    label: Text(label, style: TextStyle(color: fg)),
    backgroundColor: bg,
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
  );
}

class _ElementSection extends StatelessWidget {
  const _ElementSection(
    this.title,
    this.type,
    this.period,
    this.names,
    this.onOpen,
  );

  final String title;
  final ElementType type;
  final Period period;
  final NameResolver names;
  final ValueChanged<TimetableTarget>? onOpen;

  @override
  Widget build(BuildContext context) {
    final refs = period.ofType(type).toList();
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in refs)
                ElementChip(element: r, names: names, onOpen: onOpen),
            ],
          ),
        ],
      ),
    );
  }
}

/// The rooms of an own lesson, each with ⟳ (replace) and × (remove), and +
/// (add) after them; only while [editable] (before the lesson starts).
class _RoomSection extends StatelessWidget {
  const _RoomSection({
    required this.period,
    required this.names,
    required this.onOpen,
    required this.editable,
    required this.onAction,
  });

  final Period period;
  final NameResolver names;
  final ValueChanged<TimetableTarget>? onOpen;
  final bool editable;
  final ValueChanged<RoomAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refs = period.ofType(ElementType.room).toList();
    Widget icon(String key, IconData i, String tip, VoidCallback onTap) =>
        IconButton(
          key: ValueKey(key),
          icon: Icon(i, size: 20),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    return Padding(
      key: const ValueKey('details-rooms'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rooms', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in refs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ElementChip(
                        element: r,
                        names: names,
                        onOpen: onOpen,
                      ),
                    ),
                    // Removed rooms (id 0) have nothing to replace.
                    if (editable && r.id != 0) ...[
                      icon(
                        'room-replace-${r.id}',
                        Icons.autorenew,
                        'Replace ${names.longName(r)}',
                        () => onAction(RoomAction.replace(r)),
                      ),
                      icon(
                        'room-remove-${r.id}',
                        Icons.close,
                        'Remove ${names.longName(r)}',
                        () => onAction(RoomAction.remove(r)),
                      ),
                    ],
                  ],
                ),
              if (editable)
                icon(
                  'room-add',
                  Icons.add,
                  'Add a room',
                  () => onAction(const RoomAction.add()),
                ),
            ],
          ),
          if (refs.isEmpty && !editable) const Text('No room'),
          if (!editable)
            Padding(
              key: const ValueKey('details-rooms-locked'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rooms can be changed until the lesson starts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip for a teacher/class/room. Substitutions show "old → new" with the old
/// name struck through; tapping opens that element's timetable.
class ElementChip extends StatelessWidget {
  const ElementChip({
    super.key,
    required this.element,
    required this.names,
    this.onOpen,
  });

  final ElementRef element;
  final NameResolver names;
  final ValueChanged<TimetableTarget>? onOpen;

  @override
  Widget build(BuildContext context) {
    final r = element;
    const struck = TextStyle(decoration: TextDecoration.lineThrough);
    final InlineSpan label = switch (r.change) {
      ElementChange.regular ||
      ElementChange.added => TextSpan(text: names.longName(r)),
      ElementChange.substituted => TextSpan(
        children: [
          TextSpan(text: names.longName(r, original: true), style: struck),
          const TextSpan(text: ' → '),
          TextSpan(text: names.longName(r)),
        ],
      ),
      ElementChange.removed => TextSpan(
        text: names.longName(r, original: true),
        style: struck,
      ),
    };
    final id = r.id != 0 ? r.id : r.orgId;
    return ActionChip(
      avatar: Icon(switch (r.type) {
        ElementType.teacher => Icons.person_outline,
        ElementType.klasse => Icons.groups_outlined,
        ElementType.room => Icons.meeting_room_outlined,
        _ => Icons.label_outline,
      }, size: 18),
      label: Text.rich(label),
      // id 0: nothing to open. Negative ids are name-only teachers, whose
      // timetable is rebuilt from class timetables, so they open too.
      onPressed: onOpen == null || id == 0
          ? null
          : () => onOpen!(TimetableTarget(r.type, id)),
    );
  }
}

/// Asks for lesson details (e.g. "mündliche Wiederholung", exam topics)
/// or, with another [hint], the user's homework. Returns the text, or null
/// when cancelled/skipped.
Future<String?> askLessonDetails(
  BuildContext context, {
  required String title,
  String initial = '',
  String dismissLabel = 'Cancel',
  String hint = 'e.g. mündliche Wiederholung, topics, pages',
}) => showDialog<String>(
  context: context,
  builder: (_) => _LessonDetailsDialog(
    title: title,
    initial: initial,
    dismissLabel: dismissLabel,
    hint: hint,
  ),
);

/// Hint of the homework dialog.
const homeworkHint = 'e.g. p. 12, exercises 3–5';

/// Saves the user's [note] for [keys] (all periods of a lesson) and brings
/// calendars synced from the app up to date.
void saveLessonNote(WidgetRef ref, List<String> keys, LessonNote note) {
  ref.read(lessonNotesProvider.notifier).set(keys, note);
  unawaited(
    ref
        .read(calendarSyncsProvider.notifier)
        .syncDue(force: true)
        .catchError((_) {}),
  );
}

class _LessonDetailsDialog extends StatefulWidget {
  const _LessonDetailsDialog({
    required this.title,
    required this.initial,
    required this.dismissLabel,
    required this.hint,
  });
  final String title;
  final String initial;
  final String dismissLabel;
  final String hint;

  @override
  State<_LessonDetailsDialog> createState() => _LessonDetailsDialogState();
}

class _LessonDetailsDialogState extends State<_LessonDetailsDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('lesson-details-field'),
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        // Sync limit (worker: 4 000 characters per note).
        maxLength: 4000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: 'Only for you, not sent to the school.',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('lesson-details-dismiss'),
          onPressed: () => Navigator.pop(context),
          child: Text(widget.dismissLabel),
        ),
        FilledButton(
          key: const ValueKey('lesson-details-save'),
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The user's own additions: lesson details, homework and the custom exam
/// mark.
class _UserNoteSection extends ConsumerWidget {
  const _UserNoteSection({
    required this.block,
    required this.noteKeys,
    this.serverExams = false,
    this.onEditLessonInfo,
  });
  final LessonBlock block;
  final List<String> noteKeys;

  /// Teachers: "Add details" edits the lesson info on the server, which
  /// everyone sees, instead of a note on this device.
  final VoidCallback? onEditLessonInfo;

  /// Teachers with the class register create exams on the server ("Create
  /// exam" above), so the device-only "Mark as exam" is not offered.
  final bool serverExams;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = block.first;
    final note = LessonNote(
      exam: p.userExam,
      text: p.userNote,
      homework: p.userHomework,
    );
    final schoolExam = block.periods.any((q) => q.isSchoolExam);
    final serverInfo = block.first.infoText.trim();

    void save(LessonNote n) => saveLessonNote(ref, noteKeys, n);

    Future<void> editDetails() async {
      final text = await askLessonDetails(
        context,
        title: note.text.isEmpty ? 'Add lesson details' : 'Edit lesson details',
        initial: note.text,
      );
      if (text == null) return;
      save(note.copyWith(text: text));
    }

    Future<void> editHomework() async {
      final text = await askLessonDetails(
        context,
        title: note.homework.isEmpty ? 'Add homework' : 'Edit homework',
        initial: note.homework,
        hint: homeworkHint,
      );
      if (text == null) return;
      save(note.copyWith(homework: text));
    }

    Future<void> markExam() async {
      save(note.copyWith(exam: true));
      final text = await askLessonDetails(
        context,
        title: 'Exam details',
        initial: note.text,
        dismissLabel: 'Skip',
      );
      if (text == null) return;
      save(note.copyWith(exam: true, text: text));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note.text.isNotEmpty)
            Card.outlined(
              key: const ValueKey('lesson-user-note'),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(note.text),
                subtitle: Text(
                  onEditLessonInfo == null
                      ? 'Your details'
                      : 'Your details · only on this device',
                ),
                trailing: IconButton(
                  key: const ValueKey('lesson-details-remove'),
                  tooltip: 'Remove details',
                  icon: const Icon(Icons.close),
                  onPressed: () => save(note.copyWith(text: '')),
                ),
                onTap: editDetails,
              ),
            ),
          if (note.homework.isNotEmpty) ...[
            if (note.text.isNotEmpty) const SizedBox(height: 8),
            Card.outlined(
              key: const ValueKey('lesson-user-homework'),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(note.homework),
                subtitle: const Text('Your homework'),
                trailing: IconButton(
                  key: const ValueKey('lesson-homework-remove'),
                  tooltip: 'Remove homework',
                  icon: const Icon(Icons.close),
                  onPressed: () => save(note.copyWith(homework: '')),
                ),
                onTap: editHomework,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onEditLessonInfo != null)
                TextButton.icon(
                  key: const ValueKey('lesson-info-edit'),
                  onPressed: onEditLessonInfo,
                  icon: Icon(
                    serverInfo.isEmpty ? Icons.add : Icons.edit_outlined,
                  ),
                  label: Text(
                    serverInfo.isEmpty ? 'Add details' : 'Edit details',
                  ),
                )
              else
                TextButton.icon(
                  key: const ValueKey('lesson-details-edit'),
                  onPressed: editDetails,
                  icon: Icon(
                    note.text.isEmpty ? Icons.add : Icons.edit_outlined,
                  ),
                  label: Text(
                    note.text.isEmpty ? 'Add details' : 'Edit details',
                  ),
                ),
              TextButton.icon(
                key: const ValueKey('lesson-homework-edit'),
                onPressed: editHomework,
                icon: Icon(
                  note.homework.isEmpty ? Icons.add : Icons.edit_outlined,
                ),
                label: Text(
                  note.homework.isEmpty ? 'Add homework' : 'Edit homework',
                ),
              ),
              if (note.exam)
                TextButton.icon(
                  key: const ValueKey('lesson-exam-remove'),
                  onPressed: () => save(note.copyWith(exam: false)),
                  icon: Icon(
                    Icons.assignment_late_outlined,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Remove custom exam',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else if (!schoolExam && !serverExams)
                TextButton.icon(
                  key: const ValueKey('lesson-exam-add'),
                  onPressed: markExam,
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Mark as exam'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
