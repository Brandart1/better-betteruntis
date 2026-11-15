import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/calendar_sync_service.dart';
import '../../calendar/device_calendar.dart';

/// Runs due calendar syncs when the app starts and whenever it comes back
/// to the foreground (each sync at most every [kAutoSyncInterval]).
class CalendarAutoSync extends ConsumerStatefulWidget {
  const CalendarAutoSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CalendarAutoSync> createState() => _CalendarAutoSyncState();
}

class _CalendarAutoSyncState extends ConsumerState<CalendarAutoSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, so start-up isn't slowed down.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _sync() {
    if (!mounted || !ref.read(deviceCalendarProvider).supported) return;
    unawaited(
      ref.read(calendarSyncsProvider.notifier).syncDue().catchError((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
