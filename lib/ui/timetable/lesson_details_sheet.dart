import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import 'lesson_layout.dart';
import 'timetable_utils.dart';

/// Opens the lesson details for [blocks] (several = overlapping lessons, shown
/// in a pager) starting at [index].
Future<void> showLessonDetails(
  BuildContext context, {
  required List<LessonBlock> blocks,
  required int index,
  required NameResolver names,
  ValueChanged<TimetableTarget>? onOpenElement,
}) {
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
  });

  final List<LessonBlock> blocks;
  final NameResolver names;
  final int initialIndex;
  final ValueChanged<TimetableTarget>? onOpenElement;

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
class LessonDetailsPage extends StatelessWidget {
  const LessonDetailsPage({
    super.key,
    required this.block,
    required this.names,
    this.onOpenElement,
  });

  final LessonBlock block;
  final NameResolver names;
  final ValueChanged<TimetableTarget>? onOpenElement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = block.first;
    final subjects = p.ofType(ElementType.subject).toList();
    final title = subjects.isNotEmpty
        ? subjects.map((s) => names.longName(s, original: s.id == 0)).join(', ')
        : (p.lessonText.isNotEmpty ? p.lessonText : 'Lesson');
    final numbers = lessonNumbers(names.timeGrid, block.start, block.end);
    final when = [
      dateFormat(context, 'EEE d MMM').format(block.start),
      '${hhmm(minuteOfDay(block.start))} – ${hhmm(minuteOfDay(block.end))}',
      if (numbers.isNotEmpty) 'Lesson $numbers',
    ].join(' · ');

    final texts = <String>{
      for (final q in block.periods) ...[q.substitutionText, q.lessonText, q.infoText],
      if (p.exam != null) ...[p.exam!.name, p.exam!.text],
    }.where((t) => t.trim().isNotEmpty && t != title).toList();
    final homework = <int, Homework>{
      for (final h in block.periods.expand((q) => q.homework)) h.id: h,
    }.values.toList();
    final link = block.periods.map((q) => q.onlineLink).firstWhereOrNull(
          (l) => l != null && l.isNotEmpty,
        );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(when, style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        _StatusChips(block: block),
        _ElementSection('Teachers', ElementType.teacher, p, names, onOpenElement),
        _ElementSection('Classes', ElementType.klasse, p, names, onOpenElement),
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
              leading: Icon(h.completed ? Icons.check_circle : Icons.menu_book_outlined),
              title: Text(h.text),
              subtitle: Text([
                'Due ${dateFormat(context, 'EEE d MMM').format(h.endDate)}',
                if (h.remark.isNotEmpty) h.remark,
              ].join(' · ')),
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
            const Row(children: [
              Icon(Icons.wifi),
              SizedBox(width: 8),
              Text('Online lesson'),
            ]),
        ],
      ],
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.block});
  final LessonBlock block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[
      if (block.isCancelled)
        _chip(Icons.block, 'Cancelled', cs.errorContainer, cs.onErrorContainer),
      if (block.isExam)
        _chip(Icons.assignment_outlined, 'Exam', cs.errorContainer, cs.onErrorContainer),
      if (!block.isCancelled && block.isIrregular)
        _chip(Icons.swap_horiz, 'Substitution', cs.tertiaryContainer, cs.onTertiaryContainer),
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
  const _ElementSection(this.title, this.type, this.period, this.names, this.onOpen);

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
              for (final r in refs) ElementChip(element: r, names: names, onOpen: onOpen),
            ],
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
      ElementChange.regular || ElementChange.added =>
        TextSpan(text: names.longName(r)),
      ElementChange.substituted => TextSpan(children: [
          TextSpan(text: names.longName(r, original: true), style: struck),
          const TextSpan(text: ' → '),
          TextSpan(text: names.longName(r)),
        ]),
      ElementChange.removed =>
        TextSpan(text: names.longName(r, original: true), style: struck),
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
      onPressed: onOpen == null || id <= 0 // <0: name-only (REST) element, no timetable
          ? null
          : () => onOpen!(TimetableTarget(r.type, id)),
    );
  }
}
