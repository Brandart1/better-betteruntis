import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/teacher_tools.dart';
import '../common/large_text.dart';

/// Opens the free-room picker of one of the teacher's own lesson blocks
/// ([periods]: one lesson, or the periods of a double lesson) to replace
/// [replacing] (a room the lesson has now), or to add a room when null.
/// Resolves to a confirmation text when the room was changed, else null.
Future<String?> openRoomBooking(
  BuildContext context, {
  required Account account,
  required List<Period> periods,
  required String title,
  required String subtitle,
  ElementRef? replacing,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => RoomBookingScreen(
      account: account,
      periods: periods,
      title: title,
      subtitle: subtitle,
      replacing: replacing,
    ),
  ),
);

/// Runs [action] of the lesson sheet's room row: replace / add open the
/// free-room picker, remove asks first and sends right away. Shows the
/// outcome (or the server's error) as a snack bar.
Future<void> runRoomAction(
  BuildContext context,
  WidgetRef ref, {
  required Account account,
  required List<Period> periods,
  required RoomAction action,
  required String title,
  required String subtitle,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (action.kind != RoomEditKind.remove) {
    final done = await openRoomBooking(
      context,
      account: account,
      periods: periods,
      title: title,
      subtitle: subtitle,
      replacing: action.kind == RoomEditKind.replace ? action.room : null,
    );
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return;
  }
  final room = action.room!;
  final names = ref.read(nameResolverProvider).value;
  final name = names?.longName(room) ?? '#${room.id}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Remove $name?'),
      content: Text(
        '$title, $subtitle'
        '${periods.length > 1 ? ' (${periods.length} lessons)' : ''}\n\n'
        'The lesson will no longer have this room.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('roomremove-confirm'),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final edit = RoomEdit.remove(room.id);
  try {
    final r = await ref
        .read(teacherToolsRepositoryProvider)
        .changeRoom(
          account,
          periods,
          orgRoomId: edit.orgRoomId,
          roomId: edit.roomId,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          r.ok
              ? 'Room removed: $name.'
              : 'Could not remove the room: '
                    '${r.errors.map((e) => e.message).join('\n')}',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not remove the room: ${teacherToolErrorText(e)}'),
      ),
    );
  }
}

/// Full-screen picker of a free room. [load] gives the free rooms; rooms in
/// [extra] (e.g. the lesson's own room) are listed first as "Current".
/// Resolves to the chosen room id.
Future<int?> pickFreeRoom(
  BuildContext context, {
  required Future<FreeRooms> Function() load,
  String title = 'Choose a room',
  String? subtitle,
  List<int> extra = const [],
  int? selected,
}) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    builder: (c) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FreeRoomList(
        load: load,
        header: subtitle == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(subtitle),
              ),
        extra: extra,
        selected: selected,
        onPick: (id) => Navigator.of(c).pop(id),
      ),
    ),
  ),
);

/// Error text of [e] as the forms show it.
String teacherToolErrorText(Object e) => e is UntisException
    ? (e.code == 0 || e.code == -1
          ? e.message
          : '${e.message} (error ${e.code})')
    : e.toString();

/// A box with an error (or warning) text in the error colors.
class ErrorBox extends StatelessWidget {
  const ErrorBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: cs.onErrorContainer)),
    );
  }
}

/// Searchable list of the free rooms [load] returns. Names come from the
/// master data; ids it doesn't know show as "#id".
class FreeRoomList extends ConsumerStatefulWidget {
  const FreeRoomList({
    super.key,
    required this.load,
    required this.onPick,
    this.header,
    this.extra = const [],
    this.selected,
    this.enabled = true,
    this.pinned = const [],
    this.pinnedLabel = 'Planned room',
  });

  /// Free rooms listed first, marked [pinnedLabel] (e.g. the planned room).
  final List<int> pinned;
  final String pinnedLabel;

  final Future<FreeRooms> Function() load;
  final ValueChanged<int> onPick;
  final Widget? header;

  /// Listed first, marked "Current" (not part of the free rooms).
  final List<int> extra;
  final int? selected;
  final bool enabled;

  @override
  ConsumerState<FreeRoomList> createState() => _FreeRoomListState();
}

class _FreeRoomListState extends ConsumerState<FreeRoomList> {
  final _search = TextEditingController();
  FreeRooms? _rooms;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _rooms = null;
      _error = null;
    });
    try {
      final r = await widget.load();
      if (mounted) setState(() => _rooms = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(nameResolverProvider).value;
    final large = isLargeText(context);
    String long(int id) {
      final ref = ElementRef(type: ElementType.room, id: id, orgId: id);
      return names?.longName(ref) ?? '#$id';
    }

    String short(int id) {
      final ref = ElementRef(type: ElementType.room, id: id, orgId: id);
      return names?.shortName(ref) ?? '';
    }

    final query = _search.text.trim().toLowerCase();
    bool matches(int id) =>
        query.isEmpty ||
        long(id).toLowerCase().contains(query) ||
        short(id).toLowerCase().contains(query);

    final rooms = _rooms;
    final free = rooms == null
        ? const <int>[]
        : ([
            for (final id in rooms.roomIds)
              if (!widget.extra.contains(id) && matches(id)) id,
          ]..sort((a, b) {
            final pa = widget.pinned.contains(a) ? 0 : 1;
            final pb = widget.pinned.contains(b) ? 0 : 1;
            if (pa != pb) return pa - pb;
            return long(a).toLowerCase().compareTo(long(b).toLowerCase());
          }));
    final extra = [
      for (final id in widget.extra)
        if (matches(id)) id,
    ];

    Widget tile(int id, {bool current = false}) {
      final l = long(id);
      final s = short(id);
      final selected = widget.selected == id;
      return ListTile(
        key: ValueKey('freeroom-$id'),
        enabled: widget.enabled,
        leading: large
            ? null
            : Icon(selected ? Icons.check_circle : Icons.meeting_room_outlined),
        title: Text(l),
        subtitle: Text(
          [
            if (s.isNotEmpty && s != l) s,
            if (current) 'Current',
            if (!current && widget.pinned.contains(id)) widget.pinnedLabel,
            if (selected && large) 'Selected',
          ].join(' · '),
        ),
        selected: selected,
        onTap: () => widget.onPick(id),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ?widget.header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const ValueKey('freeroom-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search rooms',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        for (final id in extra) tile(id, current: true),
        if (rooms == null && _error == null)
          const Padding(
            key: ValueKey('freeroom-loading'),
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ErrorBox(
                  'Could not load the free rooms: '
                  '${teacherToolErrorText(_error!)}',
                  key: const ValueKey('freeroom-error'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('freeroom-retry'),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (rooms != null) ...[
          for (final e in rooms.errors)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ErrorBox(
                e.message,
                key: const ValueKey('freeroom-server-error'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Free rooms (${free.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (free.isEmpty)
            Padding(
              key: const ValueKey('freeroom-empty'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                query.isEmpty
                    ? (rooms.slotCount > 1
                          ? 'No room is free on all ${rooms.slotCount} dates.'
                          : 'The server lists no free rooms for this time.')
                    : 'No free room matches "${_search.text.trim()}".',
              ),
            ),
          for (final id in free) tile(id),
          if (rooms.partlyFree.isNotEmpty)
            Padding(
              key: const ValueKey('freeroom-partly'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                rooms.partlyFree.length == 1
                    ? '1 more room is free on some of the '
                          '${rooms.slotCount} dates only.'
                    : '${rooms.partlyFree.length} more rooms are free on '
                          'some of the ${rooms.slotCount} dates only.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

/// Replaces a room of one of the teacher's own lessons ([replacing], a
/// room the lesson has now) or adds one ([replacing] null): the rooms free
/// during the whole block, searchable; tap one and confirm. The planned
/// room is listed first when it is free again (that undoes a change).
class RoomBookingScreen extends ConsumerStatefulWidget {
  const RoomBookingScreen({
    super.key,
    required this.account,
    required this.periods,
    required this.title,
    required this.subtitle,
    this.replacing,
  });

  final Account account;
  final List<Period> periods;
  final String title;
  final String subtitle;

  /// The room being replaced; null: a room is added.
  final ElementRef? replacing;

  @override
  ConsumerState<RoomBookingScreen> createState() => _RoomBookingScreenState();
}

class _RoomBookingScreenState extends ConsumerState<RoomBookingScreen> {
  bool _sending = false;
  String? _error;

  TeacherToolsRepository get _repo => ref.read(teacherToolsRepositoryProvider);

  String _name(int id) {
    final names = ref.read(nameResolverProvider).value;
    return names?.longName(
          ElementRef(type: ElementType.room, id: id, orgId: id),
        ) ??
        '#$id';
  }

  List<ElementRef> get _rooms => currentRoomsOf(widget.periods.first);

  Future<void> _book(int roomId) async {
    final old = widget.replacing;
    if (old != null && roomId == old.id) return;
    final name = _name(roomId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          old == null ? 'Add $name?' : 'Replace ${_name(old.id)} with $name?',
        ),
        content: Text(
          '${widget.title}, ${widget.subtitle}'
          '${widget.periods.length > 1 ? ' (${widget.periods.length} lessons)' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('roombook-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(old == null ? 'Add' : 'Replace'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    // orgRoomId is the room the lesson has now (not the planned one).
    final edit = old == null
        ? RoomEdit.add(roomId)
        : RoomEdit.replace(old.id, roomId);
    try {
      final r = await _repo.changeRoom(
        widget.account,
        widget.periods,
        orgRoomId: edit.orgRoomId,
        roomId: edit.roomId,
      );
      if (!mounted) return;
      if (r.ok) {
        Navigator.of(context).pop(
          old == null
              ? 'Room added: $name. The server accepted the change.'
              : 'Room booked: $name. The server accepted the change.',
        );
        return;
      }
      setState(() {
        _sending = false;
        _error = r.errors.map((e) => e.message).join('\n');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = teacherToolErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final old = widget.replacing;
    final rooms = _rooms;
    final names = ref.watch(nameResolverProvider).value;
    String label(int id) =>
        names?.longName(
          ElementRef(type: ElementType.room, id: id, orgId: id),
        ) ??
        '#$id';
    // Planned rooms the lesson doesn't have now: offered first.
    final planned = [
      for (final e in widget.periods.first.elements)
        if (e.type == ElementType.room &&
            e.orgId != 0 &&
            !rooms.any((r) => r.id == e.orgId))
          e.orgId,
    ];
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          Text(widget.subtitle),
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('roombook-current'),
            rooms.isEmpty
                ? 'This lesson has no room yet.'
                : '${rooms.length == 1 ? 'Room' : 'Rooms'}: '
                      '${rooms.map((r) => r.id != r.orgId && r.orgId != 0 ? '${label(r.id)} (planned: ${label(r.orgId)})' : label(r.id)).join(', ')}',
          ),
          if (old != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                key: const ValueKey('roombook-replacing'),
                'Choose the room that replaces ${label(old.id)}.',
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                key: ValueKey('roombook-adding'),
                'Choose a room to add to this lesson.',
              ),
            ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(key: ValueKey('roombook-sending')),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ErrorBox(
                'Could not book the room: $_error',
                key: const ValueKey('roombook-error'),
              ),
            ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(old == null ? 'Add a room' : 'Replace ${label(old.id)}'),
      ),
      body: FreeRoomList(
        load: () => _repo.freeRoomsForLesson(widget.account, widget.periods),
        header: header,
        enabled: !_sending,
        selected: old?.id,
        pinned: planned,
        onPick: _book,
      ),
    );
  }
}
