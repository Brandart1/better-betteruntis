/// The phone's calendars (Android calendar provider / iOS EventKit) behind a
/// small interface, so the sync logic can be tested without a device.
library;

import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A writable calendar on the device.
class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.name,
    this.color,
    this.account,
    this.primary = false,
    this.hidden = false,
    this.local = false,
  });

  final String id;
  final String name;

  /// ARGB, or null if unknown.
  final int? color;

  /// e.g. "me@gmail.com" / "iCloud".
  final String? account;
  final bool primary;

  /// Not shown / not synced in the calendar app (Android VISIBLE = 0). Still
  /// writable, but its events only appear once it is turned on there.
  final bool hidden;

  /// Exists only on this device (Android local account type): not synced
  /// anywhere and not deletable in most calendar apps.
  final bool local;
}

/// One timed event as the sync writes it.
class CalendarEventData {
  const CalendarEventData({
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
    this.location = '',
    this.free = false,
  });

  final String title;

  /// Local wall-clock times.
  final DateTime start;
  final DateTime end;
  final String description;
  final String location;

  /// Shown as "free" instead of "busy" (cancelled lessons).
  final bool free;

  /// Changes whenever anything the calendar shows changes.
  String get fingerprint => [
    title,
    start.toIso8601String(),
    end.toIso8601String(),
    description,
    location,
    free,
  ].join('\u0001');
}

/// No calendar access (denied, or not available on this platform).
class CalendarAccessException implements Exception {
  const CalendarAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class DeviceCalendarApi {
  /// False on platforms without device calendars (web).
  bool get supported;

  /// Asks for full calendar access. Throws [CalendarAccessException] if not
  /// granted.
  Future<void> requestAccess();

  /// Writable, visible calendars.
  Future<List<DeviceCalendarInfo>> calendars();

  /// Creates a calendar (local account on Android, iCloud/local on iOS).
  Future<String> createCalendar(String name, int color);

  Future<void> updateCalendar(String id, {String? name, int? color});

  /// Deletes a calendar with all its events; ignores a missing one.
  Future<void> deleteCalendar(String id);

  Future<String> createEvent(String calendarId, CalendarEventData event);

  /// Returns false if the event no longer exists (deleted by the user).
  Future<bool> updateEvent(String eventId, CalendarEventData event);

  /// Ignores a missing event.
  Future<void> deleteEvent(String eventId);

  /// Asks the accounts on the device to sync their calendars now (Android),
  /// so calendars created elsewhere show up. Best effort; returns a log of
  /// the requests (empty where not supported).
  Future<List<String>> requestSync();

  /// Raw state for the debug report (Android): sync settings per account and
  /// every calendar row with its flags. Empty where not supported.
  Future<Map<String, Object?>> debugInfo();
}

/// Account the app's own calendars are created in (Android).
const kCalendarAccountName = 'BetterBetterUntis';

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

int? _argb(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(
    h.length > 6 ? h.substring(h.length - 6) : h,
    radix: 16,
  );
  return v == null ? null : 0xFF000000 | v;
}

bool _notFound(Object e) =>
    e is dc.DeviceCalendarException &&
    e.errorCode == dc.DeviceCalendarError.notFound;

/// [DeviceCalendarApi] over the device_calendar_plus plugin.
class PluginDeviceCalendar implements DeviceCalendarApi {
  PluginDeviceCalendar();

  dc.DeviceCalendar get _p => dc.DeviceCalendar.instance;

  @override
  bool get supported => !kIsWeb;

  @override
  Future<void> requestAccess() async {
    if (!supported) {
      throw const CalendarAccessException(
        'Calendars are only available in the app.',
      );
    }
    var status = await _p.hasPermissions();
    if (status != dc.CalendarPermissionStatus.granted) {
      status = await _p.requestPermissions();
    }
    if (status != dc.CalendarPermissionStatus.granted) {
      throw const CalendarAccessException(
        'No calendar access. Allow it in the system settings.',
      );
    }
  }

  @override
  Future<List<DeviceCalendarInfo>> calendars() async {
    final all = await _p.listCalendars();
    final deleted = await _deletedIds();
    final out = [
      for (final c in all)
        if (!c.readOnly && !deleted.contains(c.id))
          DeviceCalendarInfo(
            id: c.id,
            name: c.name,
            color: _argb(c.colorHex),
            account: c.accountName,
            primary: c.isPrimary,
            hidden: c.hidden,
            local: c.accountType == 'LOCAL',
          ),
    ];
    // Per account: the main calendar first, then the others by name.
    out.sort((a, b) {
      final byAccount = (a.account ?? '').compareTo(b.account ?? '');
      if (byAccount != 0) return byAccount;
      if (a.primary != b.primary) return a.primary ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Future<String> createCalendar(String name, int color) async {
    final id = await _p.createCalendar(
      name: name,
      colorHex: _hex(color),
      // Groups the app's calendars under one account in calendar apps.
      android: const dc.CalendarOptionsAndroid(
        accountName: kCalendarAccountName,
      ),
    );
    final all = await _p.listCalendars();
    if (!all.any((c) => c.id == id)) {
      throw CalendarAccessException('Could not create the calendar "$name".');
    }
    return id;
  }

  @override
  Future<void> updateCalendar(String id, {String? name, int? color}) async {
    try {
      await _p.updateCalendar(
        id,
        name: name,
        colorHex: color == null ? null : _hex(color),
      );
    } catch (e) {
      if (!_notFound(e)) rethrow;
    }
  }

  @override
  Future<void> deleteCalendar(String id) async {
    try {
      await _p.deleteCalendar(id);
    } catch (e) {
      if (!_notFound(e)) rethrow;
    }
  }

  @override
  Future<String> createEvent(String calendarId, CalendarEventData e) =>
      _p.createEvent(
        calendarId: calendarId,
        title: e.title,
        startDate: e.start,
        endDate: e.end,
        description: e.description.isEmpty ? null : e.description,
        location: e.location.isEmpty ? null : e.location,
        availability: e.free
            ? dc.EventAvailability.free
            : dc.EventAvailability.busy,
      );

  @override
  Future<bool> updateEvent(String eventId, CalendarEventData e) async {
    dc.Patch<String> text(String v) =>
        v.isEmpty ? const dc.Patch.clear() : dc.Patch.set(v);
    try {
      await _p.updateEvent(
        instanceId: eventId,
        title: e.title,
        startDate: e.start,
        endDate: e.end,
        description: text(e.description),
        location: text(e.location),
        availability: e.free
            ? dc.EventAvailability.free
            : dc.EventAvailability.busy,
      );
      return true;
    } catch (err) {
      if (_notFound(err)) return false;
      rethrow;
    }
  }

  @override
  Future<List<String>> requestSync() async {
    if (!_androidApp) return const [];
    try {
      final log = await _channel.invokeListMethod<String>('requestSync');
      return log ?? const [];
    } catch (e) {
      return ['failed: $e'];
    }
  }

  @override
  Future<Map<String, Object?>> debugInfo() async {
    if (!_androidApp) return const {};
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('debugInfo');
      return m ?? const {};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// Calendars deleted elsewhere whose removal wasn't synced yet.
  Future<Set<String>> _deletedIds() async {
    if (!_androidApp) return const {};
    try {
      final ids = await _channel.invokeListMethod<String>('deletedCalendarIds');
      return {...?ids};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    try {
      await _p.deleteEvent(instanceId: eventId);
    } catch (e) {
      if (!_notFound(e)) rethrow;
    }
  }
}

const _channel = MethodChannel('better_betteruntis/calendar');

bool get _androidApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Opens [url] in a web browser app, never in an app that claims the link
/// (Android: Google Calendar catches calendar.google.com). False if no
/// browser was found.
Future<bool> openInBrowser(Uri url) async {
  if (!_androidApp) return false;
  try {
    return await _channel.invokeMethod<String>('openInBrowser', {
          'url': '$url',
        }) !=
        null;
  } catch (_) {
    return false;
  }
}

final deviceCalendarProvider = Provider<DeviceCalendarApi>(
  (_) => PluginDeviceCalendar(),
);
