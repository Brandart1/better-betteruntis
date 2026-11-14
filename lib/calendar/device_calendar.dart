/// The phone's calendars (Android calendar provider / iOS EventKit) behind a
/// small interface, so the sync logic can be tested without a device.
library;

import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A writable calendar on the device.
class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.name,
    this.color,
    this.account,
    this.primary = false,
  });

  final String id;
  final String name;

  /// ARGB, or null if unknown.
  final int? color;

  /// e.g. "me@gmail.com" / "iCloud".
  final String? account;
  final bool primary;
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
}

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
    return [
      for (final c in all)
        if (!c.readOnly && !c.hidden)
          DeviceCalendarInfo(
            id: c.id,
            name: c.name,
            color: _argb(c.colorHex),
            account: c.accountName,
            primary: c.isPrimary,
          ),
    ];
  }

  @override
  Future<String> createCalendar(String name, int color) =>
      _p.createCalendar(name: name, colorHex: _hex(color));

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
  Future<void> deleteEvent(String eventId) async {
    try {
      await _p.deleteEvent(instanceId: eventId);
    } catch (e) {
      if (!_notFound(e)) rethrow;
    }
  }
}

final deviceCalendarProvider = Provider<DeviceCalendarApi>(
  (_) => PluginDeviceCalendar(),
);
