import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/interfaces.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Search + tabs over master data; tapping opens that element's timetable.
class ElementPickerScreen extends ConsumerStatefulWidget {
  const ElementPickerScreen({super.key});

  @override
  ConsumerState<ElementPickerScreen> createState() => _ElementPickerScreenState();
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
          title: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Search timetables',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final t in _tabs) Tab(icon: Icon(t.$3), text: t.$2)],
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
      return const Center(child: Text('Nothing here — your school may not share this list.'));
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
