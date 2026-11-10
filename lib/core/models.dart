/// Domain models shared by the API, data and UI layers.
///
/// These are the contract between layers: the API layer maps raw JSON into
/// these, the data layer persists them, the UI renders them. Keep them free of
/// Flutter imports.
library;

import 'package:collection/collection.dart';

/// Untis element types. JSON uses the string names; [code] is Untis' numeric id.
enum ElementType {
  klasse('CLASS', 1),
  teacher('TEACHER', 2),
  subject('SUBJECT', 3),
  room('ROOM', 4),
  student('STUDENT', 5),
  unknown('UNKNOWN', -1);

  const ElementType(this.apiName, this.code);
  final String apiName;
  final int code;

  /// Tolerant parse: unknown strings map to [unknown] instead of throwing.
  static ElementType parse(Object? raw) =>
      values.firstWhereOrNull((e) => e.apiName == raw || e.code == raw) ??
      unknown;
}

/// A master-data entry (class, teacher, subject or room).
class MasterElement {
  const MasterElement({
    required this.type,
    required this.id,
    required this.name,
    required this.longName,
    this.foreColor,
    this.backColor,
    this.active = true,
    this.displayAllowed = true,
  });

  final ElementType type;
  final int id;

  /// Short name, e.g. "MUE", "5a", "R101". Never empty — see [ElementNames].
  final String name;

  /// Long name, e.g. "Anna Müller". Never empty — falls back to [name].
  final String longName;

  /// ARGB colors (0xAARRGGBB) or null when the school sends none.
  final int? foreColor;
  final int? backColor;

  /// Only for filtering pickers. NEVER use these to hide names in a timetable.
  final bool active;
  final bool displayAllowed;
}

/// How an element in a period relates to the planned timetable.
enum ElementChange { regular, substituted, removed, added }

/// A reference from a period to an element. [orgId] is the originally planned
/// element; `id != orgId` is a substitution, `id == 0` means removed.
class ElementRef {
  const ElementRef({
    required this.type,
    required this.id,
    required this.orgId,
    this.inlineName,
    this.inlineLongName,
  });

  final ElementType type;
  final int id;
  final int orgId;

  /// Names the server may embed directly in the period element. Used as a
  /// fallback when the id is missing from master data (teacher-bug fix).
  final String? inlineName;
  final String? inlineLongName;

  ElementChange get change {
    if (id == 0 && orgId != 0) return ElementChange.removed;
    if (orgId == 0 && id != 0) return ElementChange.added;
    if (id != orgId) return ElementChange.substituted;
    return ElementChange.regular;
  }
}

/// Flags from a period's `is` array, parsed tolerantly.
enum PeriodFlag {
  regular,
  irregular,
  cancelled,
  exam,
  breakSupervision,
  officeHour,
  unknown;

  static PeriodFlag parse(Object? raw) => switch (raw) {
    'REGULAR' => regular,
    'IRREGULAR' => irregular,
    'CANCELLED' => cancelled,
    'EXAM' => exam,
    'BREAK_SUPERVISION' => breakSupervision,
    'OFFICE_HOUR' || 'OFFICE_HOUR_REGISTRATION' => officeHour,
    _ => unknown,
  };
}

class Homework {
  const Homework({
    required this.id,
    required this.lessonId,
    required this.startDate,
    required this.endDate,
    required this.text,
    this.remark = '',
    this.completed = false,
  });

  final int id;
  final int lessonId;
  final DateTime startDate;
  final DateTime endDate;
  final String text;
  final String remark;
  final bool completed;
}

class Exam {
  const Exam({required this.id, this.type = '', this.name = '', this.text = ''});
  final int id;
  final String type;
  final String name;
  final String text;
}

/// One timetable period (lesson). Times are local wall-clock (no zone).
class Period {
  const Period({
    required this.id,
    required this.lessonId,
    required this.start,
    required this.end,
    required this.elements,
    required this.flags,
    this.lessonText = '',
    this.substitutionText = '',
    this.infoText = '',
    this.foreColor,
    this.backColor,
    this.homework = const [],
    this.exam,
    this.isOnline = false,
    this.onlineLink,
  });

  final int id;
  final int lessonId;
  final DateTime start;
  final DateTime end;
  final List<ElementRef> elements;
  final Set<PeriodFlag> flags;
  final String lessonText;
  final String substitutionText;
  final String infoText;
  final int? foreColor;
  final int? backColor;
  final List<Homework> homework;
  final Exam? exam;
  final bool isOnline;
  final String? onlineLink;

  Iterable<ElementRef> ofType(ElementType t) =>
      elements.where((e) => e.type == t);

  bool get isCancelled => flags.contains(PeriodFlag.cancelled);
  bool get isExam => flags.contains(PeriodFlag.exam) || exam != null;
  bool get isIrregular =>
      flags.contains(PeriodFlag.irregular) ||
      elements.any((e) => e.change != ElementChange.regular);
}

class TimeUnit {
  const TimeUnit({required this.label, required this.start, required this.end});
  final String label;

  /// Minutes since midnight.
  final int start;
  final int end;
}

/// School time grid. [days] maps DateTime.weekday (1 = Mon) to its units.
class TimeGrid {
  const TimeGrid(this.days);
  final Map<int, List<TimeUnit>> days;

  /// Fallback when the school sends none: Mon–Fri, hourly 06:00–22:00.
  factory TimeGrid.fallback() => TimeGrid({
    for (var d = 1; d <= 5; d++)
      d: [
        for (var h = 6; h < 22; h++)
          TimeUnit(label: '${h - 5}', start: h * 60, end: (h + 1) * 60),
      ],
  });
}

class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.longName,
    required this.start,
    required this.end,
  });
  final int id;
  final String name;
  final String longName;
  final DateTime start;

  /// Inclusive end date.
  final DateTime end;
}

class SchoolYear {
  const SchoolYear({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });
  final int id;
  final String name;
  final DateTime start;
  final DateTime end;
}

/// Full or delta master data, as returned by getUserData2017/getTimetable2017.
class MasterData {
  const MasterData({
    required this.timestamp,
    this.elements = const [],
    this.holidays = const [],
    this.schoolYears = const [],
    this.timeGrid,
  });

  final int timestamp;
  final List<MasterElement> elements;
  final List<Holiday> holidays;
  final List<SchoolYear> schoolYears;
  final TimeGrid? timeGrid;
}

/// Result of the school search.
class School {
  const School({
    required this.schoolId,
    required this.loginName,
    required this.displayName,
    required this.address,
    required this.host,
  });

  final int schoolId;
  final String loginName;
  final String displayName;
  final String address;

  /// Resolved API host (mobileServiceUrl/serverUrl logic already applied).
  final String host;
}

/// A logged-in profile. Multiple accounts (also across schools) are allowed.
/// The shared secret is NOT stored here — it lives in secure storage, keyed by
/// [id].
class Account {
  const Account({
    required this.id,
    required this.school,
    required this.username,
    required this.anonymous,
    required this.displayName,
    this.profileName,
    this.elementType = ElementType.student,
    this.elementId = 0,
    this.klassenIds = const [],
    this.rights = const {},
    this.masterDataTimestamp = 0,
    this.hostOverride,
  });

  /// Local identifier (not an Untis id).
  final String id;
  final School school;
  final String username;
  final bool anonymous;

  /// From userData.displayName, e.g. "Max Mustermann".
  final String displayName;

  /// Optional user-chosen label, e.g. "Little sister".
  final String? profileName;

  /// The account's own timetable element.
  final ElementType elementType;
  final int elementId;
  final List<int> klassenIds;
  final Set<String> rights;
  final int masterDataTimestamp;
  final String? hostOverride;

  String get label =>
      (profileName?.trim().isNotEmpty ?? false) ? profileName! : displayName;
  String get host => hostOverride ?? school.host;

  Account copyWith({
    String? profileName,
    int? masterDataTimestamp,
    String? displayName,
    ElementType? elementType,
    int? elementId,
  }) => Account(
    id: id,
    school: school,
    username: username,
    anonymous: anonymous,
    displayName: displayName ?? this.displayName,
    profileName: profileName ?? this.profileName,
    elementType: elementType ?? this.elementType,
    elementId: elementId ?? this.elementId,
    klassenIds: klassenIds,
    rights: rights,
    masterDataTimestamp: masterDataTimestamp ?? this.masterDataTimestamp,
    hostOverride: hostOverride,
  );
}

/// Which timetable is being viewed: an element of an account.
class TimetableTarget {
  const TimetableTarget(this.type, this.id);
  final ElementType type;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is TimetableTarget && other.type == type && other.id == id;
  @override
  int get hashCode => Object.hash(type, id);
}
