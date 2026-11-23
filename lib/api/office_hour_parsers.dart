/// Parsers and payloads for booking office hours (official app 6.8.1:
/// GetOfficeHourRegistrationsResponse {teacherText, userText,
/// timeSlots:[{startTime, endTime, state FREE|OTHER|SELF}]},
/// SubmitOfficeHourRegistrationRequest {periodId, teacherId,
/// startDateTime, endDateTime, teacherText, userText}).
library;

import '../core/info.dart';
import '../core/office_hour_booking.dart';
import 'parsers.dart';
import 'teacher_tools_parsers.dart';

/// getOfficeHourRegistrations2017 / submitOfficeHourRegistration2017
/// answer. Slot times are "THH:mm" on [day] (a full date-time is taken as
/// it is); slots without times are skipped, an unknown state counts as
/// taken by someone else.
OfficeHourSlots parseOfficeHourSlots(Object? raw, DateTime day) {
  final j = raw is Map ? raw : const {};
  DateTime? at(Object? v) {
    if (v is String && RegExp(r'\d{4}-\d{2}-\d{2}T').hasMatch(v)) {
      return parseDateTime(v);
    }
    final m = parseTime(v);
    return m == null
        ? null
        : DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
  }

  final slots = <OfficeHourSlot>[];
  final list = j['timeSlots'];
  for (final s in list is List ? list : const []) {
    if (s is! Map) continue;
    final start = at(s['startTime']);
    final end = at(s['endTime']);
    if (start == null || end == null) continue;
    slots.add(
      OfficeHourSlot(
        start: start,
        end: end.isBefore(start) ? start : end,
        state: switch ('${s['state']}'.toUpperCase()) {
          'FREE' => OfficeHourSlotState.free,
          'SELF' => OfficeHourSlotState.self,
          _ => OfficeHourSlotState.other,
        },
      ),
    );
  }
  slots.sort((a, b) => a.start.compareTo(b.start));
  String text(Object? v) => v is String ? v.trim() : '';
  return OfficeHourSlots(
    slots: slots,
    teacherText: text(j['teacherText']),
    userText: text(j['userText']),
  );
}

/// The office hour's day (for slot times).
DateTime officeHourDay(OfficeHourItem o) =>
    DateTime(o.start.year, o.start.month, o.start.day);

/// getOfficeHourRegistrations2017 params.
Map<String, Object?> officeHourSlotsParams(OfficeHourItem o) => {
  'periodId': o.id,
  'teacherId': o.teacherId,
};

/// submitOfficeHourRegistration2017 params: the slot as local
/// `yyyy-MM-ddTHH:mmZ` (literal Z, like the official app).
Map<String, Object?> bookOfficeHourParams(
  OfficeHourItem o,
  OfficeHourSlot slot, {
  required String userText,
  String teacherText = '',
}) => {
  'periodId': o.id,
  'teacherId': o.teacherId,
  'startDateTime': '${formatUntisDateTime(slot.start)}Z',
  'endDateTime': '${formatUntisDateTime(slot.end)}Z',
  'teacherText': teacherText,
  'userText': userText.trim(),
};

/// deleteOfficeHourRegistration2017 params.
Map<String, Object?> cancelOfficeHourParams(
  OfficeHourItem o, {
  String userText = '',
}) => {'periodId': o.id, 'teacherId': o.teacherId, 'userText': userText.trim()};
