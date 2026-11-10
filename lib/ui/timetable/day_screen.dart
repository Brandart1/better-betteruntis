import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'day_timeline.dart';
import 'lesson_details_sheet.dart';
import 'open_element.dart';
import 'timetable_utils.dart';
import 'week_data_view.dart';

/// Full-screen single-day view; swipe left/right between [weekdays].
class DayScreen extends ConsumerStatefulWidget {
  const DayScreen({
    super.key,
    required this.date,
    required this.target,
    this.weekdays = const [1, 2, 3, 4, 5],
    this.onOpenElement,
  });

  final DateTime date;
  final TimetableTarget target;

  /// Weekdays (1 = Mon) the pager steps through.
  final List<int> weekdays;
  final OpenElementCallback? onOpenElement;

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  final _controller = PageController(initialPage: kPagerOrigin);
  late int _page = kPagerOrigin;
  late final DateTime _monday = mondayOf(widget.date);
  late final List<int> _days = widget.weekdays.isEmpty
      ? const [1, 2, 3, 4, 5]
      : (widget.weekdays.toSet().toList()..sort());

  /// Position of the initial date in [_days] (nearest following day if absent).
  late final int _basePos = () {
    final i = _days.indexWhere((d) => d >= widget.date.weekday);
    return i == -1 ? _days.length - 1 : i;
  }();

  DateTime _dateFor(int page) {
    final n = _days.length;
    final idx = _basePos + page - kPagerOrigin;
    final week = (idx / n).floor();
    final pos = idx - week * n;
    return addDays(_monday, week * 7 + _days[pos] - 1);
  }

  int _pageFor(DateTime date) {
    final weeks = weekOffset(_monday, date);
    var pos = _days.indexWhere((d) => d >= date.weekday);
    if (pos == -1) pos = _days.length - 1;
    return kPagerOrigin + weeks * _days.length + pos - _basePos;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if ((page - _page).abs() <= 2) {
      _controller.animateToPage(page,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    } else {
      _controller.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider).value;
    final date = _dateFor(_page);
    final todayPage = _pageFor(DateTime.now());
    final open = widget.onOpenElement ?? defaultOpenElement;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          dateFormat(context, 'EEEE, d MMMM').format(date),
          key: const ValueKey('day-label'),
        ),
        actions: [
          IconButton(
            tooltip: 'Today',
            onPressed: _page == todayPage ? null : () => _goTo(todayPage),
            icon: const Icon(Icons.today),
          ),
        ],
      ),
      body: account == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, i) {
                final d = _dateFor(i);
                return WeekDataView(
                  key: ValueKey(d),
                  account: account,
                  target: widget.target,
                  weekStart: mondayOf(d),
                  builder: (context, periods, names) => DayTimeline(
                    date: d,
                    periods: periods,
                    names: names,
                    onLessonTap: (blocks, index) => showLessonDetails(
                      context,
                      blocks: blocks,
                      index: index,
                      names: names,
                      onOpenElement: (t) => open(context, t),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
