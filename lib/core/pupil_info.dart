/// What the class register knows about a lesson's pupils beyond their
/// attendance: exemptions ("Befreiungen"), class duties ("Klassendienste"),
/// the seating plan and birthdays.
///
/// All of it comes with getPeriodData2017 (`exemptions`, `classRoles`,
/// `seatingPlan` per lesson, `referencedStudents[].birthDate`), the shape
/// taken from the official app 6.8.1 (UMPeriodData, UMStudentExemption,
/// UMClassRole, UMSeatingPlan, UMStudent). Duty names are master data
/// `duties`. Rendered by lib/ui/classreg/class_register_screen.dart.
library;

/// A pupil's exemption from (part of) a subject, e.g. PE.
class ClassRegExemption {
  const ClassRegExemption({
    required this.studentId,
    this.id,
    this.subjectId,
    this.subjectGroup = '',
    this.reason = '',
    this.text = '',
    this.startDate,
    this.endDate,
    this.startMinute,
    this.endMinute,
    this.weekday,
  });

  final int? id;
  final int studentId;
  final int? subjectId;
  final String subjectGroup;

  /// `exemptionReason`, '' when none.
  final String reason;
  final String text;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Minutes since midnight, when the exemption covers only part of a day.
  final int? startMinute;
  final int? endMinute;

  /// DateTime.weekday when it applies to one weekday only.
  final int? weekday;

  /// Whether it covers [day] (date range and weekday; unknown = yes).
  bool appliesOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (startDate != null && d.isBefore(startDate!)) return false;
    if (endDate != null && d.isAfter(endDate!)) return false;
    if (weekday != null && day.weekday != weekday) return false;
    return true;
  }

  /// "Exempt: medical certificate" style label.
  String get label {
    final why = [reason, text].map((s) => s.trim()).where((s) => s.isNotEmpty);
    return why.isEmpty ? 'Exempt' : 'Exempt: ${why.join(' · ')}';
  }
}

/// A pupil's class duty, e.g. class speaker or board duty.
class ClassRole {
  const ClassRole({
    required this.studentId,
    this.dutyId,
    this.name = '',
    this.text = '',
    this.startDate,
    this.endDate,
  });

  final int studentId;

  /// Master data `duties` id.
  final int? dutyId;

  /// Duty name (resolved from master data `duties`), '' when unknown.
  final String name;
  final String text;
  final DateTime? startDate;
  final DateTime? endDate;

  bool appliesOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (startDate != null && d.isBefore(startDate!)) return false;
    if (endDate != null && d.isAfter(endDate!)) return false;
    return true;
  }

  /// Name, else the free text, else "Class duty".
  String get label {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final t = text.trim();
    return t.isNotEmpty ? t : 'Class duty';
  }

  ClassRole withName(String name) => ClassRole(
    studentId: studentId,
    dutyId: dutyId,
    name: name,
    text: text,
    startDate: startDate,
    endDate: endDate,
  );
}

/// The seating plan of a lesson: [rows] × [columns] seats, pupils by seat.
class SeatingPlan {
  const SeatingPlan({
    required this.rows,
    required this.columns,
    this.id,
    this.name = '',
    this.seats = const {},
  });

  final int? id;
  final String name;
  final int rows;
  final int columns;

  /// Student id by (row, column), both from 0.
  final Map<(int, int), int> seats;

  bool get isEmpty => seats.isEmpty || rows <= 0 || columns <= 0;
}

/// Whether someone born on [birthDate] has their birthday on [day]. A
/// 29 February birthday counts on 28 February in other years.
bool isBirthday(DateTime? birthDate, DateTime day) {
  if (birthDate == null) return false;
  if (birthDate.month == day.month && birthDate.day == day.day) return true;
  final leap = DateTime(day.year, 2, 29).month == 2;
  return !leap &&
      birthDate.month == 2 &&
      birthDate.day == 29 &&
      day.month == 2 &&
      day.day == 28;
}

/// Age on [day] of someone born on [birthDate].
int ageOn(DateTime birthDate, DateTime day) {
  var age = day.year - birthDate.year;
  if (day.month < birthDate.month ||
      (day.month == birthDate.month && day.day < birthDate.day)) {
    age--;
  }
  return age;
}
