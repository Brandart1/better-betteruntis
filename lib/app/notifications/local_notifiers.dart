/// [LocalNotifier] implementations: system notifications on Android and iOS
/// (flutter_local_notifications), an in-app snackbar on the web.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications.dart';

/// The notifier for this platform: system notifications on Android / iOS,
/// in-app everywhere else (web).
LocalNotifier createPlatformNotifier() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return PluginLocalNotifier();
  }
  return InAppNotifier();
}

/// System notifications via flutter_local_notifications. Initialization
/// never asks for permission (that happens when the user turns
/// notifications on, see [requestPermission]).
class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  Future<void>? _init;
  bool _launchTaken = false;

  static const channelId = 'changes';
  static const dailyChannelId = 'daily';

  Future<void> _ensureInit() => _init ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(
            '@drawable/ic_launcher_monochrome',
          ),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) _taps.add(p);
        },
      )
      .then((_) {});

  @override
  Future<bool> requestPermission() async {
    await _ensureInit();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // null: Android 12 and older, no runtime permission needed.
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  @override
  Future<void> show(AppNotification n) async {
    await _ensureInit();
    await _plugin.show(
      id: n.id,
      title: n.title,
      body: n.body,
      payload: n.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Changes',
          channelDescription:
              'Substitutions, cancellations, room changes and new messages',
          styleInformation: BigTextStyleInformation(n.body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  @override
  bool get canSchedule =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      defaultTargetPlatform == TargetPlatform.android
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  @override
  Future<void> schedule(AppNotification n, DateTime at) async {
    await _ensureInit();
    final exact = await exactTimeAllowed();
    await _plugin.zonedSchedule(
      id: n.id,
      title: n.title,
      body: n.body,
      payload: n.payload,
      // An instant in UTC: no time zone database needed, and a new one is
      // scheduled every day anyway (summer time).
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          dailyChannelId,
          'Daily summary and reminders',
          channelDescription:
              "Today's changes and tests, and reminders about tests and "
              'homework, at the time you chose',
          styleInformation: BigTextStyleInformation(n.body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _ensureInit();
    await _plugin.cancel(id: id);
  }

  @override
  Future<bool> exactTimeAllowed() async {
    final android = _android;
    if (android == null) return true;
    await _ensureInit();
    return await android.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<void> requestExactTime() async {
    await _ensureInit();
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Stream<String> get taps {
    unawaited(_ensureInit().catchError((_) {}));
    return _taps.stream;
  }

  @override
  Future<String?> takeLaunchPayload() async {
    if (_launchTaken) return null;
    _launchTaken = true;
    await _ensureInit();
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return d.notificationResponse?.payload;
  }
}

/// Web (and any platform without system notifications): notifications are
/// handed to the UI ([shown]), which shows a snackbar while the app is open.
/// Nothing runs while the page is closed.
class InAppNotifier implements LocalNotifier {
  final _shown = StreamController<AppNotification>.broadcast();
  final _taps = StreamController<String>.broadcast();

  /// Notifications for the UI to display.
  Stream<AppNotification> get shown => _shown.stream;

  /// Called by the UI when the user opens an in-app notification.
  void tap(String payload) => _taps.add(payload);

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show(AppNotification n) async => _shown.add(n);

  @override
  bool get canSchedule => false;

  @override
  Future<void> schedule(AppNotification n, DateTime at) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<bool> exactTimeAllowed() async => true;

  @override
  Future<void> requestExactTime() async {}

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> takeLaunchPayload() async => null;
}
