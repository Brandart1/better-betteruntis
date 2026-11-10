import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'day_screen.dart';
import 'lesson_details_sheet.dart';
import 'open_element.dart';
import 'timetable_providers.dart';
import 'timetable_utils.dart';
import 'week_data_view.dart';
import 'week_grid.dart';

/// Week pager. [target] null = the active account's own timetable.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key, this.target, this.onOpenElement, this.drawer});

  final TimetableTarget? target;

  /// Navigation drawer (provided by the app shell for the home route).
  final Widget? drawer;
  final OpenElementCallback? onOpenElement;

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  final _controller = PageController(initialPage: kPagerOrigin);
  int _page = kPagerOrigin;

  /// Monday of the current week, fixed for the lifetime of the screen so page
  /// indices stay stable.
  final DateTime _origin = mondayOf(DateTime.now());

  DateTime _weekStart(int page) => addDays(_origin, 7 * (page - kPagerOrigin));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (!_controller.hasClients) return;
    if ((page - _page).abs() <= 2) {
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpToPage(page);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _weekStart(_page);
    final picked = await showDatePicker(
      context: context,
      initialDate: _page == kPagerOrigin ? dateOnly(now) : current,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) _goTo(kPagerOrigin + weekOffset(_origin, picked));
  }

  void _openElement(TimetableTarget t) =>
      (widget.onOpenElement ?? defaultOpenElement)(context, t);

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(activeAccountProvider);
    final account = accountAsync.value;
    final names = ref.watch(nameResolverProvider).value;

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
    final target =
        widget.target ?? TimetableTarget(account.elementType, account.elementId);

    // Keep the neighbouring weeks subscribed so swiping shows data instantly.
    for (final p in [_page - 1, _page + 1]) {
      ref.listen(
        weekPeriodsProvider(WeekRequest(account, target, _weekStart(p))),
        (_, _) {},
      );
    }

    final weekdays = visibleWeekdays(names?.timeGrid ?? TimeGrid.fallback(), const []);
    final ws = _weekStart(_page);
    final label =
        formatWeekRange(context, addDays(ws, weekdays.first - 1), addDays(ws, weekdays.last - 1));
    final element = widget.target == null ? null : names?.element(target.type, target.id);

    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, key: const ValueKey('week-label')),
            if (element != null)
              Text(element.longName, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Today',
            onPressed: _page == kPagerOrigin ? null : () => _goTo(kPagerOrigin),
            icon: const Icon(Icons.today),
          ),
          IconButton(
            tooltip: 'Jump to date',
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (p) => setState(() => _page = p),
        itemBuilder: (context, i) {
          final weekStart = _weekStart(i);
          return WeekDataView(
            key: ValueKey(weekStart),
            account: account,
            target: target,
            weekStart: weekStart,
            builder: (context, periods, names) {
              final model = WeekModel.build(weekStart, periods, names);
              return WeekGrid(
                model: model,
                names: names,
                onDayTap: (date) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DayScreen(
                      date: date,
                      target: target,
                      weekdays: model.weekdays,
                      onOpenElement: widget.onOpenElement,
                    ),
                  ),
                ),
                onLessonTap: (blocks, index) => showLessonDetails(
                  context,
                  blocks: blocks,
                  index: index,
                  names: names,
                  onOpenElement: _openElement,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
