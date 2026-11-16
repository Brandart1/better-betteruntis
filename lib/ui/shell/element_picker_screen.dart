import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/teacher_tools.dart';
import '../classreg/room_booking_screen.dart'
    show ErrorBox, teacherToolErrorText;
import '../classreg/time_range_field.dart';
import '../common/search_field.dart';
import '../common/large_text.dart';
import '../timetable/timetable_utils.dart';

enum _FreeMode { off, now, next, custom }

/// Search + tabs over master data; tapping opens that element's timetable.
/// The Rooms tab can show only the rooms free during this / the next lesson
/// or a chosen time.
class ElementPickerScreen extends ConsumerStatefulWidget {
  const ElementPickerScreen({super.key});

  @override
  ConsumerState<ElementPickerScreen> createState() =>
      _ElementPickerScreenState();
}

class _ElementPickerScreenState extends ConsumerState<ElementPickerScreen> {
  static const _tabs = [
    (ElementType.klasse, 'Classes', Icons.groups_outlined),
    (ElementType.teacher, 'Teachers', Icons.school_outlined),
    (ElementType.room, 'Rooms', Icons.meeting_room_outlined),
  ];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(nameResolverProvider).value;
    final account = ref.watch(activeAccountProvider).value;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AppSearchField(
              fieldKey: const ValueKey('browse-search'),
              hintText: 'Search classes, teachers, rooms',
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          // Large text: text-only tabs that scroll, instead of clipped
          // labels and an overflowing icon + text column.
          bottom: isLargeText(context)
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in _tabs) Tab(text: t.$2)],
                )
              : TabBar(
                  tabs: [
                    for (final t in _tabs) Tab(icon: Icon(t.$3), text: t.$2),
                  ],
                ),
        ),
        body: names == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  for (final t in _tabs)
                    _ElementList(
                      header: _header(t.$1, _browsable(names, t.$1), account),
                      elements: _browsable(names, t.$1)
                          .where(
                            (e) =>
                                _query.isEmpty ||
                                e.name.toLowerCase().contains(_query) ||
                                e.longName.toLowerCase().contains(_query),
                          )
                          // Free-room filter: only the free rooms.
                          .where(
                            (e) =>
                                t.$1 != ElementType.room ||
                                _freeIds == null ||
                                _freeIds!.contains(e.id),
                          )
                          .toList(),
                    ),
                ],
              ),
      ),
    );
  }

  /// Teacher/room timetables are rebuilt from class timetables when the
  /// account may not view them directly.
  static bool _builtFromClasses(ElementType type, Account? account) {
    if (type != ElementType.teacher && type != ElementType.room) return false;
    final rights = account?.rights ?? const <String>{};
    return !rights.any((r) => r.startsWith('TT_VIEW:R:${type.code}:'));
  }

  List<Widget> _header(
    ElementType type,
    List<MasterElement> all,
    Account? account,
  ) {
    final onlyDiscovered = all.every((e) => e.id < 0);
    return [
      // A refusal keeps the bar (with its error) until the screen closes.
      if (type == ElementType.room &&
          account != null &&
          (_freeFilterAvailable(account) || _freeError != null))
        _freeFilterBar(account),
      if (type == ElementType.teacher && onlyDiscovered && account != null)
        _DiscoverCard(
          scanning: _scanning,
          progress: _progress,
          error: _scanError,
          found: all.length,
          onScan: () => _discover(account),
        ),
      if (_builtFromClasses(type, account))
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Built from class timetables — may miss lessons without a class.',
                ),
              ),
            ],
          ),
        ),
    ];
  }

  // ---- Free-room filter (Browse → Rooms) ---------------------------------
  // getAvailableRooms2017, as the official app's free-room tab uses it. Off
  // by default; any failure shows the error and turns it off, and a "no
  // right" answer hides it for the session.

  /// Accounts whose server refused getAvailableRooms2017 (this session).
  static final _freeFilterRefused = <String>{};

  _FreeMode _freeMode = _FreeMode.off;
  TimeRange? _freeRange;
  Set<int>? _freeIds;
  bool _freeLoading = false;
  String? _freeNote;
  String? _freeError;
  int _freeRequest = 0;

  static bool _freeFilterAvailable(Account? a) =>
      a != null && !a.anonymous && !_freeFilterRefused.contains(a.id);

  Future<void> _setFreeMode(_FreeMode mode, Account account) async {
    final grid = ref.read(nameResolverProvider).value?.timeGrid;
    final now = ref.read(teacherToolsClockProvider)();
    TimeRange? range;
    String? note;
    switch (mode) {
      case _FreeMode.off:
        break;
      case _FreeMode.now:
        final u = unitAt(grid, now);
        if (u == null) {
          note = 'No lesson is running right now.';
        } else {
          range = TimeRange(dateOnly(now), u.start, u.end);
        }
      case _FreeMode.next:
        final u = nextUnitAfter(grid, now);
        if (u == null) {
          note = 'No more lessons today.';
        } else {
          range = TimeRange(dateOnly(now), u.start, u.end);
        }
      case _FreeMode.custom:
        range = await _askRange(grid, now);
        if (range == null) return;
    }
    final request = ++_freeRequest;
    setState(() {
      _freeMode = range == null ? _FreeMode.off : mode;
      _freeRange = range;
      _freeIds = null;
      _freeNote = note;
      _freeError = null;
      _freeLoading = range != null;
    });
    if (range == null) return;
    try {
      final r = await ref
          .read(teacherToolsRepositoryProvider)
          .freeRoomsAt(account, range.startTime, range.endTime);
      if (!mounted || request != _freeRequest) return;
      if (r.errors.isNotEmpty) {
        throw UntisException(-1, r.errors.map((e) => e.message).join('\n'));
      }
      setState(() {
        _freeLoading = false;
        _freeIds = r.roomIds.toSet();
      });
    } catch (e) {
      if (!mounted || request != _freeRequest) return;
      if (e is UntisException && e.code == UntisException.noRight) {
        _freeFilterRefused.add(account.id);
      }
      setState(() {
        _freeLoading = false;
        _freeMode = _FreeMode.off;
        _freeRange = null;
        _freeIds = null;
        _freeError =
            'Could not load the free rooms: ${teacherToolErrorText(e)}';
      });
    }
  }

  Future<TimeRange?> _askRange(TimeGrid? grid, DateTime now) {
    final next = nextUnitAfter(grid, now);
    var value =
        _freeRange ??
        (next == null
            ? TimeRange(
                dateOnly(now),
                minuteOfDay(now),
                (minuteOfDay(now) + 60).clamp(0, 24 * 60 - 1),
              )
            : TimeRange(dateOnly(now), next.start, next.end));
    return showDialog<TimeRange>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Free rooms when?'),
          content: SingleChildScrollView(
            child: TimeRangeField(
              value: value,
              grid: grid,
              onChanged: (v) => setDialog(() => value = v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('freefilter-apply'),
              onPressed: value.isValid
                  ? () => Navigator.of(c).pop(value)
                  : null,
              child: const Text('Show free rooms'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freeFilterBar(Account account) {
    final grid = ref.watch(nameResolverProvider).value?.timeGrid;
    final hasGrid = grid != null && !grid.isFallback;
    final range = _freeRange;
    String? summary;
    if (range != null) {
      final numbers = grid == null
          ? ''
          : lessonNumbers(grid, range.startTime, range.endTime);
      summary = [
        dateFormat(context, 'EEE d MMM').format(range.date),
        '${hhmm(range.start)}–${hhmm(range.end)}',
        if (numbers.isNotEmpty) 'lesson $numbers',
      ].join(' · ');
    }
    Widget chip(_FreeMode m, String label) => ChoiceChip(
      key: ValueKey('freefilter-${m.name}'),
      label: Text(label),
      selected: _freeMode == m,
      onSelected: _freeLoading ? null : (_) => _setFreeMode(m, account),
    );
    return Padding(
      key: const ValueKey('freefilter'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Free rooms', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(_FreeMode.off, 'All rooms'),
              if (hasGrid) chip(_FreeMode.now, 'This lesson'),
              if (hasGrid) chip(_FreeMode.next, 'Next lesson'),
              chip(_FreeMode.custom, 'Custom…'),
            ],
          ),
          if (_freeLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(key: ValueKey('freefilter-busy')),
            ),
          if (summary != null && !_freeLoading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                key: const ValueKey('freefilter-summary'),
                'Free $summary: ${_freeIds?.length ?? 0} '
                '${_freeIds?.length == 1 ? 'room' : 'rooms'}',
              ),
            ),
          if (_freeNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_freeNote!, key: const ValueKey('freefilter-note')),
            ),
          if (_freeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ErrorBox(
                _freeError!,
                key: const ValueKey('freefilter-error'),
              ),
            ),
        ],
      ),
    );
  }

  bool _scanning = false;
  (int, int)? _progress;
  String? _scanError;

  Future<void> _discover(Account account) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _progress = null;
      _scanError = null;
    });
    try {
      await ref
          .read(timetableRepositoryProvider)
          .discoverTeachers(
            account,
            DateTime.now(),
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = (done, total));
            },
          );
    } on UntisException catch (e) {
      if (mounted) {
        setState(
          () => _scanError = e.isNetwork || e.isTimeout
              ? 'No connection. Try again later.'
              : 'Scan failed: ${e.message}',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({
    required this.scanning,
    required this.progress,
    required this.error,
    required this.found,
    required this.onScan,
  });

  final bool scanning;
  final (int, int)? progress;
  final String? error;
  final int found;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Teachers aren't shared with students at your school. Scan all "
              'class timetables of this week to find them.',
            ),
            const SizedBox(height: 12),
            if (scanning) ...[
              LinearProgressIndicator(
                value: p == null || p.$2 == 0 ? null : p.$1 / p.$2,
              ),
              const SizedBox(height: 8),
              Text(
                p == null
                    ? 'Scanning classes…'
                    : 'Scanning ${p.$1} / ${p.$2} classes…',
              ),
            ] else ...[
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.manage_search),
                label: Text(found == 0 ? 'Scan classes' : 'Scan again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ElementList extends StatelessWidget {
  const _ElementList({required this.elements, this.header = const []});
  final List<MasterElement> elements;
  final List<Widget> header;

  @override
  Widget build(BuildContext context) {
    if (elements.isEmpty && header.isEmpty) {
      return const Center(
        child: Text('Nothing here — your school may not share this list.'),
      );
    }
    return ListView.builder(
      itemCount: header.length + (elements.isEmpty ? 1 : elements.length),
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        if (elements.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nothing here yet.')),
          );
        }
        final e = elements[i - header.length];
        return ListTile(
          title: Text(e.longName),
          subtitle: e.longName == e.name ? null : Text(e.name),
          onTap: () => context.push('/timetable/${e.type.apiName}/${e.id}'),
        );
      },
    );
  }
}

/// Elements offered in the picker. Schools often flag teachers and rooms as
/// not displayable for students (`displayAllowed: false`); their timetables are
/// rebuilt from class timetables, so list every active one anyway.
List<MasterElement> _browsable(NameResolver names, ElementType type) =>
    type == ElementType.teacher || type == ElementType.room
    ? names.elementsOf(type, onlyActive: false).where((e) => e.active).toList()
    : names.elementsOf(type);
