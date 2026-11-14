import 'package:better_betteruntis/calendar/device_calendar.dart';

class FakeCalendar {
  FakeCalendar(this.name, this.color, {this.own = false, this.local = true});
  String name;
  int color;
  final bool own;
  final bool local;
  final events = <String, CalendarEventData>{};
}

/// In-memory [DeviceCalendarApi] that records every write.
class FakeDeviceCalendar implements DeviceCalendarApi {
  FakeDeviceCalendar({this.granted = true}) {
    cals['personal'] = FakeCalendar(
      'Personal',
      0xFF00AA00,
      own: true,
      local: false,
    );
  }

  bool granted;
  final cals = <String, FakeCalendar>{};
  final log = <String>[];
  int _ids = 0;

  /// Throw on the n-th createEvent (1-based), for partial-failure tests.
  int? failOnCreate;
  int _creates = 0;

  Iterable<CalendarEventData> eventsIn(String id) =>
      cals[id]?.events.values ?? const [];

  int get eventCount => cals.values.fold(0, (n, c) => n + c.events.length);

  /// Deletes an event as the user would in the calendar app.
  void userDeletes(String eventId) {
    for (final c in cals.values) {
      c.events.remove(eventId);
    }
  }

  @override
  bool get supported => true;

  @override
  Future<void> requestAccess() async {
    if (!granted) throw const CalendarAccessException('No calendar access.');
  }

  @override
  Future<List<DeviceCalendarInfo>> calendars() async => [
    for (final e in cals.entries)
      DeviceCalendarInfo(
        id: e.key,
        name: e.value.name,
        color: e.value.color,
        local: e.value.local,
      ),
  ];

  @override
  Future<String> createCalendar(String name, int color) async {
    final id = 'cal${++_ids}';
    cals[id] = FakeCalendar(name, color);
    log.add('createCalendar $name');
    return id;
  }

  @override
  Future<void> updateCalendar(String id, {String? name, int? color}) async {
    final c = cals[id];
    if (c == null) return;
    if (name != null) c.name = name;
    if (color != null) c.color = color;
    log.add('updateCalendar $id');
  }

  @override
  Future<void> deleteCalendar(String id) async {
    cals.remove(id);
    log.add('deleteCalendar $id');
  }

  @override
  Future<String> createEvent(String calendarId, CalendarEventData e) async {
    _creates++;
    if (failOnCreate == _creates) throw StateError('calendar full');
    final c = cals[calendarId];
    if (c == null) throw StateError('no calendar $calendarId');
    final id = 'ev${++_ids}';
    c.events[id] = e;
    log.add('createEvent');
    return id;
  }

  @override
  Future<bool> updateEvent(String eventId, CalendarEventData e) async {
    for (final c in cals.values) {
      if (c.events.containsKey(eventId)) {
        c.events[eventId] = e;
        log.add('updateEvent');
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    for (final c in cals.values) {
      c.events.remove(eventId);
    }
    log.add('deleteEvent');
  }

  int syncRequests = 0;

  @override
  Future<void> requestSync() async => syncRequests++;
}
