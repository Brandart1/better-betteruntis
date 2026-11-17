/// Android background check: a periodic WorkManager task (workmanager
/// package) that runs the same [ChangeChecker] as the app, in a background
/// isolate, with the stored credentials. iOS gets no background check
/// (background fetch is unreliable there); it checks on start / resume.
library;

import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../api/untis_api_impl.dart';
import '../../core/change_sources.dart';
import '../../core/notifications.dart';
import '../../data/account_repository_impl.dart';
import '../../data/db/database.dart';
import '../../data/info_center_repository_impl.dart';
import '../../data/timetable_repository_impl.dart';
import '../../dev/fake_accounts.dart';
import '../platform/platform_services.dart';
import '../routing_api.dart';
import 'local_notifiers.dart';

/// Unique WorkManager name of the periodic check.
const backgroundCheckName = 'bbu-change-check';

/// How often Android runs the check (WorkManager may delay it, e.g. in
/// Doze; the minimum WorkManager allows is 15 minutes).
const backgroundCheckInterval = Duration(minutes: 45);

/// A background check right after an app check (or the other way round) is
/// skipped.
const backgroundMinInterval = Duration(minutes: 10);

bool get backgroundChecksSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void>? _initialized;

Future<void> _ensureInitialized() =>
    _initialized ??= Workmanager().initialize(notificationCallbackDispatcher);

/// Schedules ([enabled]) or cancels the periodic check. No-op where
/// [backgroundChecksSupported] is false. Never throws.
Future<void> scheduleBackgroundChecks({required bool enabled}) async {
  if (!backgroundChecksSupported) return;
  try {
    await _ensureInitialized();
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        backgroundCheckName,
        backgroundCheckName,
        frequency: backgroundCheckInterval,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(backgroundCheckName);
    }
  } catch (e) {
    debugPrint('Background check scheduling failed: $e');
  }
}

/// Entry point of the background isolate.
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await runBackgroundCheck();
    } catch (e) {
      debugPrint('Background check failed: $e');
    }
    // Always "success": a failed check is simply retried next period.
    return true;
  });
}

/// Builds the data layer like main.dart (same database, secrets, settings)
/// and runs one check over all accounts with notifications on.
Future<void> runBackgroundCheck() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final settings = await openSettingsStore();
  final prefs = NotificationPrefs.fromJson(
    await settings.read(NotificationPrefs.storeKey),
  );
  if (!prefs.anyEnabled) return;

  final api = RoutingUntisApi(
    real: UntisApiImpl(isIos: false, interceptors: platformInterceptors()),
    demo: FakeUntisApi(),
  );
  final db = AppDatabase.open();
  try {
    final accounts = AccountRepositoryImpl(db, createSecretStore());
    final timetables = TimetableRepositoryImpl(
      api: api,
      db: db,
      accounts: accounts,
    );
    final info = InfoCenterRepositoryImpl(api: api, db: db, accounts: accounts);
    final checker = ChangeChecker(
      sources: defaultChangeSources(timetables: timetables, info: info),
      stateStore: createNotificationStateStore(),
      notifier: PluginLocalNotifier(),
    );
    final list = await accounts.watchAccounts().first;
    await checker
        .run(list, prefs, minInterval: backgroundMinInterval)
        .timeout(const Duration(minutes: 8));
    await timetables.dispose();
  } finally {
    await db.close();
  }
}
