import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/class_register.dart';
import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../classreg/class_register_screen.dart';
import '../classreg/open_lessons_screen.dart';
import '../export/export_sheet.dart';
import 'day_timeline.dart';
import 'lesson_details_sheet.dart';
import 'lesson_layout.dart';
import 'open_element.dart';
import 'timetable_providers.dart';
import 'timetable_utils.dart';
import 'viewing_target.dart';
import 'week_data_view.dart';
import 'week_grid.dart';

/// Week pager with a zoomed-in day mode. [target] null = the active
/// account's own timetable.
///
/// Tapping a day header zooms into that day (the column expands to full
/// width); in day mode the app bar shows the date, swiping moves between
/// days, and tapping the date (app bar or day header) or pressing back zooms
/// out to the week containing the current day.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({
    super.key,
    this.target,
    this.onOpenElement,
    this.drawer,
  });

  final TimetableTarget? target;

  /// Navigation drawer (provided by the app shell for the home route).
  final Widget? drawer;
  final OpenElementCallback? onOpenElement;

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen>
    with SingleTickerProviderStateMixin {
  final _weekController = PageController(initialPage: kPagerOrigin);

  /// Week page; in day mode the week containing [_day].
  int _page = kPagerOrigin;

  /// Monday of the current week, fixed for the lifetime of the screen so page
  /// indices stay stable.
  final DateTime _origin = mondayOf(DateTime.now());

  /// Day mode: the displayed day (null = week mode).
  DateTime? _day;
  PageController? _dayController;

  /// Weekdays (1 = Mon) the day pager steps through; fixed per day session.
  List<int> _days = const [1, 2, 3, 4, 5];

  /// 0 = week, 1 = day; drives the expand/collapse transition.
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  int _zoomColumn = 0;
  int _zoomColumns = 5;

  DateTime _weekStart(int page) => addDays(_origin, 7 * (page - kPagerOrigin));

  DateTime _dateForDayPage(int page) {
    final n = _days.length;
    final idx = page - kPagerOrigin;
    final week = (idx / n).floor();
    return addDays(_origin, week * 7 + _days[idx - week * n] - 1);
  }

  /// Day page of [date]; a day not in [_days] maps to the next shown day.
  int _dayPageFor(DateTime date) {
    var weeks = weekOffset(_origin, date);
    var pos = _days.indexWhere((d) => d >= date.weekday);
    if (pos == -1) {
      pos = 0;
      weeks++;
    }
    return kPagerOrigin + weeks * _days.length + pos;
  }

  @override
  void dispose() {
    _weekController.dispose();
    _dayController?.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _animate(PageController c, int from, int to) {
    if (!c.hasClients) return;
    if ((to - from).abs() <= 2) {
      c.animateToPage(
        to,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      c.jumpToPage(to);
    }
  }

  void _goToWeek(int page) => _animate(_weekController, _page, page);

  void _goToDate(DateTime date) {
    if (_day != null) {
      _animate(_dayController!, _dayPageFor(_day!), _dayPageFor(date));
    } else {
      _goToWeek(kPagerOrigin + weekOffset(_origin, date));
    }
  }

  void _enterDay(DateTime date, List<int> weekdays) {
    if (_day != null || _zoom.isAnimating) return;
    final days = {...weekdays, date.weekday}.toList()..sort();
    _days = days;
    _dayController?.dispose(); // its pager is unmounted (zoom is at 0)
    _dayController = PageController(initialPage: _dayPageFor(date));
    setState(() {
      _day = date;
      _zoomColumn = days.indexOf(date.weekday);
      _zoomColumns = days.length;
    });
    _zoom.forward();
  }

  void _exitDay() {
    final day = _day;
    if (day == null || _zoom.isAnimating) return;
    final page = kPagerOrigin + weekOffset(_origin, day);
    if (_weekController.hasClients && page != _weekController.page?.round()) {
      _weekController.jumpToPage(page);
    }
    setState(() {
      _page = page;
      _day = null;
      _zoomColumn = _days.indexOf(day.weekday).clamp(0, _days.length - 1);
      _zoomColumns = _days.length;
    });
    _zoom.reverse();
  }

  void _onDayPageChanged(int p) {
    final d = _dateForDayPage(p);
    setState(() {
      _day = d;
      _page = kPagerOrigin + weekOffset(_origin, d);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial =
        _day ?? (_page == kPagerOrigin ? dateOnly(now) : _weekStart(_page));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null && mounted) _goToDate(picked);
  }

  void _openElement(TimetableTarget t) =>
      (widget.onOpenElement ?? defaultOpenElement)(context, t);

  void _showDetails(List<LessonBlock> blocks, int index, NameResolver names) {
    final account = ref.read(activeAccountProvider).value;
    final target = widget.target ?? account?.personalTarget;
    // Teachers: class register of lessons in their own timetable.
    final ownTeacherTimetable =
        account != null &&
        hasClassRegister(account) &&
        target == TimetableTarget(ElementType.teacher, account.elementId);
    showLessonDetails(
      context,
      blocks: blocks,
      index: index,
      names: names,
      onOpenElement: _openElement,
      onOpenClassRegister: !ownTeacherTimetable
          ? null
          : (block) {
              final periods = block.periods
                  .where((p) => !p.isCancelled)
                  .toList();
              if (periods.isEmpty) return;
              final p = periods.first;
              openClassRegister(
                context,
                account: account,
                periods: periods,
                title: classRegLessonTitle(p, names),
                subtitle: classRegLessonSubtitle(
                  context,
                  periods.first.start,
                  periods.last.end,
                  p,
                  names,
                ),
              );
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(activeAccountProvider);
    final account = accountAsync.value;
    final names = ref.watch(nameResolverProvider).value;
    // Only this flag changes the layout; colors/fonts rebuild the cards only.
    final showCancelled = ref.watch(
      timetableSettingsProvider.select((s) => s.showCancelled),
    );

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Timetable')),
        body: Center(
          child: accountAsync.isLoading
              ? const CircularProgressIndicator()
              : const Text('No account selected'),
        ),
      );
    }
    final target = widget.target ?? account.personalTarget;
    if (target == null) {
      return Scaffold(
        drawer: widget.drawer,
        appBar: AppBar(title: const Text('Timetable')),
        body: const NoPersonalTimetable(),
      );
    }
    // Parent accounts: "My timetable" is a child's; say whose.
    final child = widget.target == null ? account.activeChild : null;

    // Keep the neighbouring weeks subscribed so swiping shows data instantly.
    for (final p in [_page - 1, _page + 1]) {
      ref.listen(
        weekPeriodsProvider(WeekRequest(account, target, _weekStart(p))),
        (_, _) {},
      );
    }

    final theme = Theme.of(context);
    final weekdays = visibleWeekdays(
      names?.timeGrid ?? TimeGrid.fallback(),
      const [],
    );
    final ws = _weekStart(_page);
    final element = widget.target == null
        ? null
        : names?.element(target.type, target.id);
    final day = _day;

    final Widget title;
    final bool atToday;
    if (day != null) {
      atToday = _dayPageFor(day) == _dayPageFor(DateTime.now());
      title = Semantics(
        button: true,
        hint: 'Back to week overview',
        child: InkWell(
          key: const ValueKey('day-title'),
          onTap: _exitDay,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    dateFormat(context, 'EEE, d MMM').format(day),
                    key: const ValueKey('day-label'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_less,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      atToday = _page == kPagerOrigin;
      title = Text(
        formatWeekRange(
          context,
          addDays(ws, weekdays.first - 1),
          addDays(ws, weekdays.last - 1),
        ),
        key: const ValueKey('week-label'),
      );
    }

    final weekPager = PageView.builder(
      key: const ValueKey('week-pager'),
      controller: _weekController,
      onPageChanged: (p) => setState(() => _page = p),
      itemBuilder: (context, i) {
        final weekStart = _weekStart(i);
        return WeekDataView(
          key: ValueKey(weekStart),
          account: account,
          target: target,
          weekStart: weekStart,
          builder: (context, periods, names) {
            final model = WeekModel.build(
              weekStart,
              periods,
              names,
              showCancelled: showCancelled,
            );
            return WeekGrid(
              model: model,
              names: names,
              onDayTap: (date) => _enterDay(date, model.weekdays),
              onLessonTap: (blocks, index) =>
                  _showDetails(blocks, index, names),
            );
          },
        );
      },
    );

    final dayController = _dayController;
    final dayPager = dayController == null
        ? null
        : ColoredBox(
            color: theme.colorScheme.surface,
            child: PageView.builder(
              key: const ValueKey('day-pager'),
              controller: dayController,
              onPageChanged: _onDayPageChanged,
              itemBuilder: (context, i) {
                final d = _dateForDayPage(i);
                return WeekDataView(
                  key: ValueKey(d),
                  account: account,
                  target: target,
                  weekStart: mondayOf(d),
                  builder: (context, periods, names) => DayTimeline(
                    date: d,
                    periods: periods,
                    names: names,
                    showCancelled: showCancelled,
                    onHeaderTap: _exitDay,
                    onLessonTap: (blocks, index) =>
                        _showDetails(blocks, index, names),
                  ),
                );
              },
            ),
          );

    final body = AnimatedBuilder(
      animation: _zoom,
      builder: (context, _) {
        final v = _zoom.value;
        final t = Curves.easeInOutCubic.transform(v);
        final align = Alignment(
          _zoomColumns <= 1 ? 0 : -1 + 2 * (_zoomColumn + 0.5) / _zoomColumns,
          -1,
        );
        return IgnorePointer(
          ignoring: _zoom.isAnimating,
          child: Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(
                key: const ValueKey('week-layer'),
                child: Offstage(
                  offstage: v >= 1,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1 + 0.06 * t,
                      alignment: align,
                      child: weekPager,
                    ),
                  ),
                ),
              ),
              if (v > 0 && dayPager != null)
                KeyedSubtree(
                  key: const ValueKey('day-layer'),
                  child: ClipRect(
                    clipper: _ColumnRevealClipper(
                      t: t,
                      column: _zoomColumn,
                      columns: _zoomColumns,
                      left: kTimeColumnWidth,
                    ),
                    child: Opacity(
                      opacity: Curves.easeOut.transform(
                        (v * 2).clamp(0.0, 1.0),
                      ),
                      child: dayPager,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    return ViewingTarget(
      target: widget.target,
      child: PopScope(
        canPop: day == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitDay();
        },
        child: Scaffold(
          drawer: widget.drawer,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (element != null)
                  Text(element.longName, style: theme.textTheme.labelMedium)
                else if (child != null)
                  Text(
                    child.displayName,
                    key: const ValueKey('child-label'),
                    style: theme.textTheme.labelMedium,
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Today',
                onPressed: atToday ? null : () => _goToDate(DateTime.now()),
                icon: const Icon(Icons.today),
              ),
              IconButton(
                tooltip: 'Jump to date',
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
              ),
              PopupMenuButton<void>(
                key: const ValueKey('timetable-menu'),
                tooltip: 'More',
                itemBuilder: (_) => [
                  PopupMenuItem<void>(
                    key: const ValueKey('export-action'),
                    onTap: () => showExportSheet(
                      context,
                      account: account,
                      target: target,
                      initialWeek: day ?? ws,
                      elementName: child?.displayName,
                    ),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text('Export…'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: body,
        ),
      ),
    );
  }
}

/// Clips the day layer from the tapped week column ([t] = 0) to the full
/// width ([t] = 1).
class _ColumnRevealClipper extends CustomClipper<Rect> {
  const _ColumnRevealClipper({
    required this.t,
    required this.column,
    required this.columns,
    required this.left,
  });

  final double t;
  final int column;
  final int columns;
  final double left;

  @override
  Rect getClip(Size size) {
    if (t >= 1) return Offset.zero & size;
    final colW = (size.width - left) / (columns < 1 ? 1 : columns);
    final from = Rect.fromLTWH(left + column * colW, 0, colW, size.height);
    return Rect.lerp(from, Offset.zero & size, t)!;
  }

  @override
  bool shouldReclip(_ColumnRevealClipper old) =>
      old.t != t ||
      old.column != column ||
      old.columns != columns ||
      old.left != left;
}

/// Shown instead of "My timetable" when the account has no timetable of its
/// own and no children to show (e.g. a parent account without linked pupils,
/// or one added before children were stored).
class NoPersonalTimetable extends StatelessWidget {
  const NoPersonalTimetable({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('no-personal-timetable'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No personal timetable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "This account doesn't have a timetable of its own, and no "
              'children are linked to it. Parent accounts: if you added this '
              'account before, remove it and log in again to load your '
              'children.\n\nYou can still open any class, teacher or room.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('browse-timetables'),
              onPressed: () => GoRouter.maybeOf(context)?.push('/browse'),
              icon: const Icon(Icons.search),
              label: const Text('Browse timetables'),
            ),
          ],
        ),
      ),
    );
  }
}
