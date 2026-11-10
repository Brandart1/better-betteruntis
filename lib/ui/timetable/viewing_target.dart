import 'package:flutter/widgets.dart';

import '../../core/models.dart';

/// Which timetable is on screen, so lesson cards can show what matters for
/// it (e.g. classes and teachers in a room's timetable instead of the room).
class ViewingTarget extends InheritedWidget {
  const ViewingTarget({super.key, required this.target, required super.child});

  final TimetableTarget? target;

  static TimetableTarget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ViewingTarget>()?.target;

  @override
  bool updateShouldNotify(ViewingTarget old) => old.target != target;
}

/// True when [room] is struck through in [p]: the lesson was moved to another
/// room, the room was dropped, or the lesson is cancelled. The room is then
/// actually free, so the class shouldn't be shown as being there.
bool roomVacated(Period p, int room) =>
    p.isCancelled ||
    p.ofType(ElementType.room).any((r) => r.orgId == room && r.id != room);
