import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_controller.dart';
import 'sync_engine.dart';

/// Syncs the lesson notes of every syncing account when the app starts and
/// whenever it comes back to the foreground (see [SyncEngine.syncAll]).
/// Local note changes are synced by the engine itself (debounced).
class SyncAutoTrigger extends ConsumerStatefulWidget {
  const SyncAutoTrigger({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SyncAutoTrigger> createState() => _SyncAutoTriggerState();
}

class _SyncAutoTriggerState extends ConsumerState<SyncAutoTrigger>
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
    if (!mounted) return;
    final c = ref.read(syncControllerProvider.notifier);
    if (c is SyncEngine) unawaited(c.syncAll().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
