import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    (ElementType.subject, 'Subjects', Icons.menu_book_outlined),
  ];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(nameResolverProvider).value;
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
                      elements: names
                          .elementsOf(t.$1)
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
}

class _ElementList extends StatelessWidget {
  const _ElementList({required this.elements});
  final List<MasterElement> elements;

  @override
  Widget build(BuildContext context) {
    if (elements.isEmpty) {
      return const Center(child: Text('Nothing here — your school may not share this list.'));
    }
    return ListView.builder(
      itemCount: elements.length,
      itemBuilder: (context, i) {
        final e = elements[i];
        return ListTile(
          title: Text(e.longName),
          subtitle: e.longName == e.name ? null : Text(e.name),
          onTap: () => context.push('/timetable/${e.type.apiName}/${e.id}'),
        );
      },
    );
  }
}
