/// Excuse management for (class) teachers: list the absences of a class and
/// mark them excused / not excused with an excuse text, like the official
/// app's "student absence administration" (SAA).
///
/// Calls (from the decompiled official app, not yet seen with a real
/// teacher account): `GET view/v1/classreg/absences/meta`,
/// `POST view/v4/classreg/absences` (list) and `PUT view/v3/classreg/absences`
/// (save). Schools without these (HTTP 404) fall back to the class absence
/// list ([ClassAbsencesApi]) and JSON-RPC `submitExcuse2017`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';

/// What an excuse status means (`excuseStatuses[].type`).
enum ExcuseStatusType {
  open('OPEN', 'Open'),
  notExcused('NOT_EXCUSED', 'Not excused'),
  excused('EXCUSED', 'Excused');

  const ExcuseStatusType(this.apiName, this.label);
  final String apiName;
  final String label;

  static ExcuseStatusType? parse(Object? v) {
    final s = '$v'.trim().toUpperCase();
    for (final t in values) {
      if (t.apiName == s) return t;
    }
    return null;
  }
}

/// One excuse status of the school, e.g. "entschuldigt" (EXCUSED).
class ExcuseStatus {
  const ExcuseStatus({
    required this.id,
    required this.name,
    required this.type,
  });

  final int id;
  final String name;
  final ExcuseStatusType type;

  @override
  bool operator ==(Object other) =>
      other is ExcuseStatus &&
      other.id == id &&
      other.name == name &&
      other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

/// A class the teacher may see absences of.
class ExcuseClass {
  const ExcuseClass({required this.id, required this.name});
  final int id;
  final String name;
}

/// `absences/meta`: classes, excuse statuses and reasons.
class ExcuseMeta {
  const ExcuseMeta({
    this.classes = const [],
    this.statuses = const [],
    this.reasons = const {},
    this.defaultExcuseStatusId,
    this.rest = true,
  });

  final List<ExcuseClass> classes;
  final List<ExcuseStatus> statuses;
  final Map<int, String> reasons;
  final int? defaultExcuseStatusId;

  /// False: the school has no SAA REST calls; lists come from the class
  /// absence list and saving uses submitExcuse2017.
  final bool rest;

  List<ExcuseStatus> statusesOf(ExcuseStatusType t) => [
    for (final s in statuses)
      if (s.type == t) s,
  ];

  ExcuseStatus? status(int? id) =>
      id == null ? null : statuses.where((s) => s.id == id).firstOrNull;

  ExcuseMeta copyWith({List<ExcuseClass>? classes}) => ExcuseMeta(
    classes: classes ?? this.classes,
    statuses: statuses,
    reasons: reasons,
    defaultExcuseStatusId: defaultExcuseStatusId,
    rest: rest,
  );
}

/// The ranges of the Excuses screen (SAA `dateRangeType`).
enum ExcuseRange {
  last14('Last 14 days', 'LAST_14_DAYS'),
  week('This week', 'WEEK'),
  month('This month', 'MONTH'),
  last30('Last 30 days', 'LAST_30_DAYS'),
  schoolYear('School year', 'SCHOOL_YEAR');

  const ExcuseRange(this.label, this.apiName);
  final String label;
  final String apiName;

  /// The days (inclusive) this range covers on [today]; the school year
  /// falls back to the last 12 months when [year] is unknown.
  ({DateTime start, DateTime end}) days(DateTime today, {SchoolYear? year}) {
    final t = DateTime(today.year, today.month, today.day);
    DateTime back(int n) => DateTime(t.year, t.month, t.day - n);
    return switch (this) {
      last14 => (start: back(13), end: t),
      last30 => (start: back(29), end: t),
      week => (start: back(t.weekday - 1), end: back(t.weekday - 7)),
      month => (
        start: DateTime(t.year, t.month),
        end: DateTime(t.year, t.month + 1, 0),
      ),
      schoolYear =>
        year == null
            ? (start: DateTime(t.year - 1, t.month, t.day + 1), end: t)
            : (
                start: DateTime(
                  year.start.year,
                  year.start.month,
                  year.start.day,
                ),
                end: DateTime(year.end.year, year.end.month, year.end.day),
              ),
    };
  }
}

/// Which absences the list shows.
enum ExcuseFilter {
  open('Open', ExcuseStatusType.open),
  notExcused('Not excused', ExcuseStatusType.notExcused),
  excused('Excused', ExcuseStatusType.excused),
  all('All', null);

  const ExcuseFilter(this.label, this.type);
  final String label;

  /// SAA `excuseStatusType`; null = all.
  final ExcuseStatusType? type;
}

/// A list request: class, days (inclusive), range type and filter.
class ExcuseQuery {
  const ExcuseQuery({
    required this.classId,
    required this.range,
    required this.start,
    required this.end,
    this.filter = ExcuseFilter.open,
  });

  final int classId;
  final ExcuseRange range;
  final DateTime start;
  final DateTime end;
  final ExcuseFilter filter;
}

/// One absence of a pupil (SAA `SaaAbsenceDto`).
class ExcuseAbsence {
  const ExcuseAbsence({
    required this.id,
    this.studentId,
    this.studentName = '',
    required this.start,
    required this.end,
    this.reasonId,
    this.reasonName = '',
    this.text = '',
    this.status,
    this.excuseText = '',
    this.excuseStatusEditable = true,
    this.raw = const {},
  });

  final int id;
  final int? studentId;
  final String studentName;
  final DateTime start;
  final DateTime end;
  final int? reasonId;
  final String reasonName;

  /// The absence's note.
  final String text;

  /// Null: no status set (open).
  final ExcuseStatus? status;
  final String excuseText;

  /// The server lets this account change the excuse.
  final bool excuseStatusEditable;

  /// The listed dto as the server sent it; a save sends it back with only
  /// the excuse fields changed. Empty for the JSON-RPC fallback.
  final Map<String, Object?> raw;

  ExcuseStatusType get type => status?.type ?? ExcuseStatusType.open;

  ExcuseAbsence withExcuse(ExcuseStatus? status, String excuseText) =>
      ExcuseAbsence(
        id: id,
        studentId: studentId,
        studentName: studentName,
        start: start,
        end: end,
        reasonId: reasonId,
        reasonName: reasonName,
        text: text,
        status: status,
        excuseText: excuseText,
        excuseStatusEditable: excuseStatusEditable,
        raw: raw,
      );
}

/// Optional API capability: the SAA calls (with their fallbacks).
abstract interface class ExcuseApi {
  /// Classes, excuse statuses, reasons. Falls back to master data statuses
  /// (types guessed from their names, no classes) when the school has no
  /// SAA meta call ([ExcuseMeta.rest] false).
  Future<ExcuseMeta> excuseMeta({
    required String host,
    required String school,
    required UntisCredentials auth,
  });

  /// Absences of [query]'s class; [meta] maps statuses.
  Future<List<ExcuseAbsence>> excuseAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required ExcuseMeta meta,
    required ExcuseQuery query,
  });

  /// Sets [absence]'s excuse to [status] with [text]. Throws an
  /// [UntisException] when the server reports conflicts (not saved) or
  /// refuses. Returns the absence as the server has it now, when sent.
  Future<ExcuseAbsence?> saveExcuse({
    required String host,
    required String school,
    required UntisCredentials auth,
    required ExcuseMeta meta,
    required ExcuseAbsence absence,
    required ExcuseStatus status,
    required String text,
  });
}

abstract interface class ExcuseRepository {
  /// Cached per account; classes from master data when the server sends
  /// none. Throws [UntisException].
  Future<ExcuseMeta> meta(Account account);

  /// Absences of [classId] in [range] matching [filter], newest first.
  Future<List<ExcuseAbsence>> absences(
    Account account, {
    required int classId,
    required ExcuseRange range,
    required ExcuseFilter filter,
  });

  /// The days [range] covers today (school year from master data).
  Future<({DateTime start, DateTime end})> rangeDays(
    Account account,
    ExcuseRange range,
  );

  /// Saves the excuse; returns the absence as it is now.
  Future<ExcuseAbsence> save(
    Account account,
    ExcuseAbsence absence, {
    required ExcuseStatus status,
    required String text,
  });
}

final excuseRepositoryProvider = Provider<ExcuseRepository>(
  (ref) => throw UnimplementedError('override excuseRepositoryProvider'),
);
