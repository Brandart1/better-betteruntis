/// App side of the notifications: checks for changes on start, on resume
/// and every [NotificationAutoCheck.foregroundInterval] while the app is in
/// the foreground; opens the right screen when a notification is tapped;
/// keeps the Android background check scheduled while any account has
/// notifications on; and on the web shows notifications as snackbars.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/notifications/local_notifiers.dart';
import '../../core/change_sources.dart';
import '../../core/daily_notifications.dart';
import '../../core/info.dart';
import '../../core/lesson_notes.dart';
import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../infocenter/info_providers.dart';
import '../timetable/timetable_providers.dart';
import 'router.dart';

/// For in-app notifications (web) shown outside any Scaffold.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final notificationServiceProvider = Provider<NotificationService>(
  NotificationService.new,
);

class NotificationService {
  NotificationService(this.ref);

  final Ref ref;
  ChangeChecker? _checker;

  ChangeChecker get _check => _checker ??= ChangeChecker(
    sources: defaultChangeSources(
      timetables: ref.read(timetableRepositoryProvider),
      info: ref.read(infoCenterRepositoryProvider),
    ),
    daily: RepositoryDailyPlanner(
      timetables: ref.read(timetableRepositoryProvider),
      info: ref.read(infoCenterRepositoryProvider),
      notes: () async {
        await ref.read(lessonNotesProvider.notifier).ready;
        return ref.read(lessonNotesProvider);
      },
    ),
    stateStore: ref.read(notificationStateStoreProvider),
    notifier: ref.read(localNotifierProvider),
  );

  /// Checks all accounts with notifications on (none: does nothing and
  /// touches no repository). Never throws.
  Future<List<AppNotification>> check({
    Duration minInterval = Duration.zero,
  }) async {
    try {
      final prefsNotifier = ref.read(notificationPrefsProvider.notifier);
      await prefsNotifier.ready;
      final prefs = ref.read(notificationPrefsProvider);
      if (!prefs.anyEnabled) return const [];
      final accounts = await ref
          .read(accountRepositoryProvider)
          .watchAccounts()
          .first;
      return await _check.run(accounts, prefs, minInterval: minInterval);
    } catch (e) {
      debugPrint('Notification check failed: $e');
      return const [];
    }
  }

  /// Opens what a tapped notification is about: switches to its account,
  /// then shows the changed day of "My timetable" or the inbox.
  Future<void> open(String payload) async {
    final t = NotificationTarget.parse(payload);
    if (t == null) return;
    final repo = ref.read(accountRepositoryProvider);
    final accounts = await repo.watchAccounts().first;
    if (!accounts.any((a) => a.id == t.accountId)) return;
    final active = await repo.watchActive().first;
    if (active?.id != t.accountId) await repo.setActive(t.accountId);
    final router = ref.read(routerProvider);
    router.go('/');
    if (t.kind == NotificationTarget.inboxKind) {
      ref.read(infoTabProvider.notifier).set(InfoTab.messages);
      unawaited(router.push('/info'));
    } else if (t.day != null) {
      ref.read(timetableJumpProvider.notifier).set(t.day);
    }
  }
}

/// Wraps the app (inside MaterialApp): runs [NotificationService.check] at
/// the right times, handles taps and keeps the background check scheduled.
class NotificationAutoCheck extends ConsumerStatefulWidget {
  const NotificationAutoCheck({super.key, required this.child});
  final Widget child;

  static const foregroundInterval = Duration(minutes: 15);

  /// Start / resume don't check again within this time.
  static const resumeMinInterval = Duration(minutes: 3);

  @override
  ConsumerState<NotificationAutoCheck> createState() =>
      _NotificationAutoCheckState();
}

class _NotificationAutoCheckState extends ConsumerState<NotificationAutoCheck>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _prefsCheck;
  StreamSubscription<String>? _taps;
  StreamSubscription<AppNotification>? _inApp;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier = ref.read(localNotifierProvider);
    final service = ref.read(notificationServiceProvider);
    _taps = notifier.taps.listen((p) => unawaited(service.open(p)));
    if (notifier is InAppNotifier) _inApp = notifier.shown.listen(_showInApp);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    if (!mounted) return;
    final notifier = ref.read(localNotifierProvider);
    final service = ref.read(notificationServiceProvider);
    try {
      final launch = await notifier.takeLaunchPayload();
      if (launch != null) await service.open(launch);
    } catch (_) {}
    if (!mounted) return;
    await ref.read(notificationPrefsProvider.notifier).ready;
    if (!mounted) return;
    final on = ref.read(notificationPrefsProvider).anyEnabled;
    // Re-register on every start (keeps the task after app updates).
    if (on) unawaited(ref.read(backgroundSchedulerProvider)(enabled: true));
    _updateTimer(on);
    if (on) {
      unawaited(
        service.check(minInterval: NotificationAutoCheck.resumeMinInterval),
      );
    }
  }

  void _updateTimer(bool on) {
    if (!on) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(NotificationAutoCheck.foregroundInterval, (_) {
      if (!_resumed || !mounted) return;
      unawaited(
        ref
            .read(notificationServiceProvider)
            .check(minInterval: const Duration(minutes: 5)),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && ref.read(notificationPrefsProvider).anyEnabled) {
      unawaited(
        ref
            .read(notificationServiceProvider)
            .check(minInterval: NotificationAutoCheck.resumeMinInterval),
      );
    }
  }

  void _showInApp(AppNotification n) {
    final messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final notifier = ref.read(localNotifierProvider);
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('in-app-notification'),
        duration: const Duration(seconds: 10),
        persist: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(n.body, maxLines: 6, overflow: TextOverflow.ellipsis),
          ],
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            if (notifier is InAppNotifier) notifier.tap(n.payload);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _prefsCheck?.cancel();
    unawaited(_taps?.cancel());
    unawaited(_inApp?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationPrefsProvider.select((p) => p.anyEnabled), (
      before,
      on,
    ) {
      if (before == on) return;
      unawaited(ref.read(backgroundSchedulerProvider)(enabled: on));
      _updateTimer(on);
    });
    // New time or reminders: schedule again (a moment later, so dragging
    // through options doesn't start a check each).
    ref.listen(notificationPrefsProvider, (before, now) {
      if (before == now) return;
      _prefsCheck?.cancel();
      _prefsCheck = Timer(const Duration(seconds: 2), () {
        if (mounted) unawaited(ref.read(notificationServiceProvider).check());
      });
    });
    return widget.child;
  }
}
