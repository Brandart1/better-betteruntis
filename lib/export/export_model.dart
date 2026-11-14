/// Plain, format-independent description of a timetable export. Built from
/// periods + names once ([buildExportLessons]) and fed to the CSV, XLSX and
/// PDF generators, which therefore need no repository or resolver.
library;

import 'package:intl/intl.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/settings.dart';

enum ExportFormat {
  csv('csv', 'CSV', 'text/csv'),
  xlsx(
    'xlsx',
    'Excel (.xlsx)',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),
  pdf('pdf', 'PDF', 'application/pdf'),
  ics('ics', 'Calendar (.ics)', 'text/calendar');

  const ExportFormat(this.extension, this.label, this.mimeType);
  final String extension;
  final String label;
  final String mimeType;
}

/// What to export: the repeating timetable or one concrete week.
enum ExportKind { regular, week }

enum LessonStatus {
  regular('Regular'),
  substitution('Substitution'),
  cancelled('Cancelled'),
  exam('Exam');

  const LessonStatus(this.label);
  final String label;
}

/// One lesson (consecutive periods of the same lesson merged).
class ExportLesson {
  const ExportLesson({
    required this.date,
    required this.start,
    required this.end,
    this.lessonNumbers = '',
    this.subject = '',
    this.subjectLong = '',
    this.teachers = const [],
    this.teachersShort = const [],
    this.rooms = const [],
    this.classes = const [],
    this.replaced = const [],
    this.replacedTeachers = const [],
    this.replacedRooms = const [],
    this.status = LessonStatus.regular,
    this.info = '',
    this.color,
    this.borderColor,
  });

  /// Day of the lesson (in a regular export: a day of the reference week,
  /// only its weekday matters).
  final DateTime date;

  /// Minutes since midnight.
  final int start;
  final int end;

  /// Unit labels from the time grid, e.g. "3" or "1–2".
  final String lessonNumbers;
  final String subject;
  final String subjectLong;

  /// "MUE (Anna Müller)" where a long name is known, else "MUE".
  final List<String> teachers;
  final List<String> teachersShort;
  final List<String> rooms;
  final List<String> classes;

  /// Originally planned names that were substituted or removed (shown struck
  /// through in the PDF). Empty in a regular export.
  final List<String> replaced;

  /// The teacher / room part of [replaced].
  final List<String> replacedTeachers;
  final List<String> replacedRooms;
  final LessonStatus status;
  final String info;

  /// ARGB background, or null for "no color".
  final int? color;

  /// ARGB state color drawn as a thick border ([StateColorMode.border]):
  /// [color] is then the lesson's normal color. Null = state shown as fill.
  final int? borderColor;

  int get weekday => date.weekday;

  /// Display name of the subject: short name, else long name.
  String get subjectLabel => subject.isNotEmpty ? subject : subjectLong;
}

/// Everything a generator needs.
class ExportTimetable {
  const ExportTimetable({
    required this.kind,
    required this.elementName,
    required this.schoolName,
    required this.periodLabel,
    required this.weekStart,
    required this.grid,
    required this.weekdays,
    required this.lessons,
    required this.exportedAt,
    this.holidays = const {},
    this.locale,
    this.targetType = ElementType.klasse,
    this.repeatUntil,
    this.skipDays = const [],
  });

  final ExportKind kind;

  /// e.g. "10a" / "Anna Müller".
  final String elementName;
  final String schoolName;

  /// "Regular timetable" or "10 – 14 Nov 2026".
  final String periodLabel;

  /// Monday of the exported (or reference) week.
  final DateTime weekStart;
  final TimeGrid grid;

  /// Weekdays (1 = Mon) shown as columns.
  final List<int> weekdays;
  final List<ExportLesson> lessons;
  final DateTime exportedAt;

  /// Week export only: weekday → holiday name.
  final Map<int, String> holidays;

  /// BCP-47 tag used for day names (falls back to English).
  final String? locale;

  /// Type of the exported element; teacher and room timetables also show
  /// the classes of each lesson.
  final ElementType targetType;

  /// Regular export: last day (inclusive) the weekly lessons repeat on in a
  /// calendar export (end of the school year); null = open-ended.
  final DateTime? repeatUntil;

  /// Regular export: days without lessons (holidays) up to [repeatUntil].
  final List<DateTime> skipDays;

  bool get regular => kind == ExportKind.regular;

  bool get showClasses =>
      targetType != ElementType.klasse && targetType != ElementType.student;

  String get title => '$elementName – $periodLabel';
}

// ---------------------------------------------------------------------------
// Formatting helpers

String hhmmOf(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

DateFormat exportDateFormat(String pattern, String? locale) {
  if (locale != null) {
    try {
      if (DateFormat.localeExists(locale)) return DateFormat(pattern, locale);
    } catch (_) {}
  }
  return DateFormat(pattern, 'en_US');
}

/// "Monday" (or the locale's name) for weekday [d] (1 = Mon).
String weekdayName(int d, String? locale, {bool short = false}) =>
    exportDateFormat(short ? 'EEE' : 'EEEE', locale)
    // 2024-01-01 is a Monday.
    .format(DateTime(2024, 1, d));

/// "10 – 14 Nov 2026" / "27 Oct – 1 Nov 2026" / "29 Dec 2025 – 2 Jan 2026".
String exportWeekRange(DateTime first, DateTime last, [String? locale]) {
  final dmy = exportDateFormat('d MMM yyyy', locale);
  if (first.year != last.year) {
    return '${dmy.format(first)} – ${dmy.format(last)}';
  }
  if (first.month == last.month) {
    return '${exportDateFormat('d', locale).format(first)} – ${dmy.format(last)}';
  }
  return '${exportDateFormat('d MMM', locale).format(first)} – ${dmy.format(last)}';
}

/// `timetable_<element>_<regular|2026-11-09>.<ext>`, safe for any file system.
String exportFileName(
  String elementName,
  ExportKind kind,
  DateTime weekStart,
  ExportFormat format,
) {
  const map = {
    'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue', //
    'ß': 'ss',
  };
  var name = elementName.trim();
  map.forEach((k, v) => name = name.replaceAll(k, v));
  name = name
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
  if (name.length > 40) name = name.substring(0, 40);
  if (name.isEmpty) name = 'export';
  final when = kind == ExportKind.regular
      ? 'regular'
      : DateFormat('yyyy-MM-dd').format(weekStart);
  return 'timetable_${name}_$when.${format.extension}';
}

// ---------------------------------------------------------------------------
// Colors

/// Background colors for exported lessons, from the user's
/// [TimetableSettings] (custom subject and state colors, school colors,
/// fill/border per state) with fixed light defaults suitable for printing.
class ExportPalette {
  const ExportPalette({
    this.useSchoolColors = true,
    this.regular = defaultRegular,
    this.substitution = defaultSubstitution,
    this.cancelled = defaultCancelled,
    this.exam = defaultExam,
    this.subjectColors = const {},
    this.examMode = StateColorMode.fill,
    this.substitutionMode = StateColorMode.fill,
    this.cancelledMode = StateColorMode.fill,
  });

  factory ExportPalette.fromSettings(TimetableSettings s) => ExportPalette(
    useSchoolColors: s.useSchoolColors,
    regular: s.regularColor ?? defaultRegular,
    substitution: s.irregularColor ?? defaultSubstitution,
    cancelled: s.cancelledColor ?? defaultCancelled,
    exam: s.examColor ?? defaultExam,
    subjectColors: s.subjectColors,
    examMode: s.examMode,
    substitutionMode: s.irregularMode,
    cancelledMode: s.cancelledMode,
  );

  static const defaultRegular = 0xFFD8E2FF;
  static const defaultSubstitution = 0xFFFFDDB3;
  static const defaultCancelled = 0xFFE3E3E3;
  static const defaultExam = 0xFFFFDAD6;

  /// Border colors used in [StateColorMode.border] when the state color is
  /// the default: stronger shades that stand out on paper (the default fill
  /// colors are too pale for a border).
  static const defaultSubstitutionBorder = 0xFFE65100;
  static const defaultCancelledBorder = 0xFF757575;
  static const defaultExamBorder = 0xFFBA1A1A;

  final bool useSchoolColors;
  final int regular;
  final int substitution;
  final int cancelled;
  final int exam;

  /// Keyed by [TimetableSettings.subjectKey].
  final Map<String, int> subjectColors;
  final StateColorMode examMode;
  final StateColorMode substitutionMode;
  final StateColorMode cancelledMode;

  /// The lesson's normal color: custom subject color > school color (if
  /// enabled) > regular color.
  int baseColor(int? schoolColor, [String? subject]) {
    if (subject != null) {
      final c = subjectColors[TimetableSettings.subjectKey(subject)];
      if (c != null) return c;
    }
    return useSchoolColors && schoolColor != null ? schoolColor : regular;
  }

  StateColorMode? _mode(LessonStatus status) => switch (status) {
    LessonStatus.regular => null,
    LessonStatus.substitution => substitutionMode,
    LessonStatus.cancelled => cancelledMode,
    LessonStatus.exam => examMode,
  };

  /// Background of a lesson with [status]: the state color in fill mode,
  /// otherwise [baseColor].
  int colorFor(LessonStatus status, int? schoolColor, [String? subject]) {
    if (_mode(status) != StateColorMode.fill) {
      return baseColor(schoolColor, subject);
    }
    return switch (status) {
      LessonStatus.cancelled => cancelled,
      LessonStatus.exam => exam,
      LessonStatus.substitution => substitution,
      LessonStatus.regular => baseColor(schoolColor, subject),
    };
  }

  /// State color as border ([StateColorMode.border]), else null.
  int? borderFor(LessonStatus status) {
    if (_mode(status) != StateColorMode.border) return null;
    int pick(int c, int def, int border) => c == def ? border : c;
    return switch (status) {
      LessonStatus.cancelled => pick(
        cancelled,
        defaultCancelled,
        defaultCancelledBorder,
      ),
      LessonStatus.exam => pick(exam, defaultExam, defaultExamBorder),
      LessonStatus.substitution => pick(
        substitution,
        defaultSubstitution,
        defaultSubstitutionBorder,
      ),
      LessonStatus.regular => null,
    };
  }
}

// ---------------------------------------------------------------------------
// Text

/// Lesson text styling for the XLSX and PDF grids, from the user's
/// [TimetableSettings]. Font sizes are kept as on-screen sizes; generators
/// apply them relative to the app defaults ([subjectScale], [detailScale]) to
/// their own base sizes, so the export keeps the proportions of the app
/// without copying its absolute pixel sizes onto paper.
///
/// Generators take `ExportTextStyle?`: null means their built-in look.
class ExportTextStyle {
  const ExportTextStyle({
    this.centered = true,
    this.subjectSize = defaultSubjectSize,
    this.detailSize = defaultDetailSize,
    this.boldSubject = true,
  });

  factory ExportTextStyle.fromSettings(TimetableSettings s) => ExportTextStyle(
    centered: s.centerText,
    subjectSize: s.subjectFontSize,
    detailSize: s.detailFontSize,
    boldSubject: s.boldSubject,
  );

  static const defaultSubjectSize = 15.0;
  static const defaultDetailSize = 12.0;

  /// Bounds of [subjectScale] / [detailScale] (the settings sliders allow
  /// about 0.73–1.5); keeps text readable and cells from overflowing badly.
  static const minScale = 0.7;
  static const maxScale = 1.5;

  final bool centered;
  final double subjectSize;
  final double detailSize;
  final bool boldSubject;

  static double _scale(double size, double def) {
    final s = size / def;
    if (s.isNaN) return 1;
    return s.clamp(minScale, maxScale).toDouble();
  }

  /// Subject size relative to the app default, clamped.
  double get subjectScale => _scale(subjectSize, defaultSubjectSize);

  /// Detail (teacher, room, …) size relative to the app default, clamped.
  double get detailScale => _scale(detailSize, defaultDetailSize);

  @override
  bool operator ==(Object other) =>
      other is ExportTextStyle &&
      other.centered == centered &&
      other.subjectSize == subjectSize &&
      other.detailSize == detailSize &&
      other.boldSubject == boldSubject;

  @override
  int get hashCode =>
      Object.hash(centered, subjectSize, detailSize, boldSubject);
}

// ---------------------------------------------------------------------------
// Periods → lessons

/// A name the server didn't really resolve ('?', '#12', '---', empty).
bool _unresolved(String n, int id) {
  final t = n.trim();
  return t.isEmpty || t == '?' || t == '---' || t == '#$id';
}

String? _short(NameResolver names, ElementRef r, {bool original = false}) {
  final id = original || r.id == 0 ? r.orgId : r.id;
  final n = names.shortName(r, original: original);
  return _unresolved(n, id) ? null : n.trim();
}

String? _long(NameResolver names, ElementRef r, {bool original = false}) {
  final id = original || r.id == 0 ? r.orgId : r.id;
  final n = names.longName(r, original: original);
  return _unresolved(n, id) ? null : n.trim();
}

String? _teacherLabel(
  NameResolver names,
  ElementRef r, {
  bool original = false,
}) {
  final s = _short(names, r, original: original);
  final l = _long(names, r, original: original);
  if (s == null) return l;
  if (l == null || l == s) return s;
  return '$s ($l)';
}

LessonStatus statusOf(Period p) {
  if (p.isExam) return LessonStatus.exam;
  if (p.isCancelled) return LessonStatus.cancelled;
  if (p.isIrregular) return LessonStatus.substitution;
  return LessonStatus.regular;
}

String _signature(Period p) {
  final keys = [for (final e in p.elements) '${e.type.code}:${e.id}:${e.orgId}']
    ..sort();
  return '${keys.join(',')}|${statusOf(p).index}';
}

/// Lesson-number label for minutes [s]..[e] on [weekday], e.g. "1–2".
String unitLabels(TimeGrid grid, int weekday, int s, int e) {
  var units = grid.days[weekday];
  if (units == null || units.isEmpty) {
    units = grid.days.values.firstWhere(
      (u) => u.isNotEmpty,
      orElse: () => const [],
    );
  }
  final hit = [
    for (final u in units)
      if (u.start < e && u.end > s) u.label,
  ];
  if (hit.isEmpty) return '';
  return hit.length == 1 ? hit.first : '${hit.first}–${hit.last}';
}

int _minute(DateTime d) => d.hour * 60 + d.minute;

/// Converts [periods] into lessons: merges consecutive periods of the same
/// lesson (≤ 20 min gap, same elements and state), resolves names (subjects
/// long + short, teachers "short (long)", unresolved names dropped) and picks
/// colors from [palette] (null = no colors). With [regular] all lessons are
/// reported as regular and one-off texts are left out.
List<ExportLesson> buildExportLessons(
  List<Period> periods,
  NameResolver names, {
  required bool regular,
  TimeGrid? grid,
  ExportPalette? palette = const ExportPalette(),
  bool includeCancelled = true,
}) {
  final g = grid ?? names.timeGrid;
  final sorted =
      [
        for (final p in periods)
          if (includeCancelled || !p.isCancelled) p,
      ]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.end.compareTo(b.end);
      });

  // Merge runs.
  final runs = <List<Period>>[];
  for (final p in sorted) {
    List<Period>? target;
    for (var i = runs.length - 1; i >= 0; i--) {
      final last = runs[i].last;
      if (last.end.isAfter(p.start)) continue;
      final sameDay =
          last.start.year == p.start.year &&
          last.start.month == p.start.month &&
          last.start.day == p.start.day;
      if (sameDay &&
          last.lessonId == p.lessonId &&
          p.start.difference(last.end).inMinutes <= 20 &&
          _signature(last) == _signature(p)) {
        target = runs[i];
        break;
      }
    }
    if (target != null) {
      target.add(p);
    } else {
      runs.add([p]);
    }
  }

  final out = <ExportLesson>[];
  for (final run in runs) {
    final p = run.first;
    final s = _minute(p.start);
    final e = _minute(run.last.end) == 0 && run.last.end.day != p.start.day
        ? 24 * 60
        : _minute(run.last.end);
    final status = regular ? LessonStatus.regular : statusOf(p);

    final current = <ElementRef>[];
    final replaced = <(ElementType, String)>[];
    for (final r in p.elements) {
      switch (r.change) {
        case ElementChange.regular:
        case ElementChange.added:
          current.add(r);
        case ElementChange.substituted:
        case ElementChange.removed:
          if (r.change == ElementChange.substituted) current.add(r);
          if (!regular && r.type != ElementType.subject) {
            final o = _short(names, r, original: true);
            if (o != null) replaced.add((r.type, o));
          }
      }
    }
    List<String> replacedOf(ElementType? t) => <String>{
      for (final (type, n) in replaced)
        if (t == null || type == t) n,
    }.toList();
    List<String> namesOf(ElementType t, String? Function(ElementRef r) pick) =>
        <String>{
          for (final r in current)
            if (r.type == t) ?pick(r),
        }.toList();

    final subjectRefs = p
        .ofType(ElementType.subject)
        .where((r) => r.change != ElementChange.removed);
    final subject = <String>{for (final r in subjectRefs) ?_short(names, r)}
        .join(', ');
    final subjectLong = <String>{for (final r in subjectRefs) ?_long(names, r)}
        .join(', ');

    final info = <String>[
      p.lessonText,
      if (!regular) ...[
        p.substitutionText,
        p.infoText,
        if (p.exam case final x?) ...[x.name, x.text],
      ],
    ].map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().join(' · ');

    // Short name of the first subject, for custom subject colors.
    String? subjectKeyName;
    for (final r in subjectRefs) {
      subjectKeyName ??= _short(names, r);
    }

    int? schoolColor = p.backColor;
    if (schoolColor == null) {
      for (final r in subjectRefs) {
        schoolColor ??= names.element(ElementType.subject, r.id)?.backColor;
      }
    }

    out.add(
      ExportLesson(
        date: DateTime(p.start.year, p.start.month, p.start.day),
        start: s,
        end: e,
        lessonNumbers: unitLabels(g, p.start.weekday, s, e),
        subject: subject,
        subjectLong: subjectLong,
        teachers: namesOf(ElementType.teacher, (r) => _teacherLabel(names, r)),
        teachersShort: namesOf(ElementType.teacher, (r) => _short(names, r)),
        rooms: namesOf(ElementType.room, (r) => _short(names, r)),
        classes: namesOf(ElementType.klasse, (r) => _short(names, r)),
        replaced: replacedOf(null),
        replacedTeachers: replacedOf(ElementType.teacher),
        replacedRooms: replacedOf(ElementType.room),
        status: status,
        info: info,
        color: palette?.colorFor(status, schoolColor, subjectKeyName),
        borderColor: palette?.borderFor(status),
      ),
    );
  }
  out.sort((a, b) {
    var c = a.date.compareTo(b.date);
    if (c != 0) return c;
    c = a.start.compareTo(b.start);
    if (c != 0) return c;
    return a.end.compareTo(b.end);
  });
  return out;
}
