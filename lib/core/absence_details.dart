/// Non-contract additions shared by lib/api and lib/data for the info center.
///
/// Absence reasons and excuse statuses are master data (`absenceReasons`,
/// `excuseStatuses`) that [MasterData] has no fields for. The API layer
/// returns [MasterDataWithLookups] (a [MasterData] subtype) from login and
/// timetable deltas, the data layer persists the lookups it finds there, and
/// resolves [RawAbsence]s against them. This keeps lib/core/info.dart and
/// models.dart unchanged.
library;

import 'info.dart';
import 'interfaces.dart';
import 'models.dart';

/// Absence reason / excuse status names by id (long name, else short name).
class AbsenceLookups {
  const AbsenceLookups({this.reasons = const {}, this.statuses = const {}});

  final Map<int, String> reasons;
  final Map<int, String> statuses;

  bool get isEmpty => reasons.isEmpty && statuses.isEmpty;

  /// [other] wins on conflicting ids.
  AbsenceLookups merge(AbsenceLookups other) => AbsenceLookups(
    reasons: {...reasons, ...other.reasons},
    statuses: {...statuses, ...other.statuses},
  );
}

/// [MasterData] that also carries absence lookups. Returned by the real API;
/// code that only knows [MasterData] keeps working.
class MasterDataWithLookups extends MasterData {
  const MasterDataWithLookups({
    required super.timestamp,
    super.elements,
    super.holidays,
    super.schoolYears,
    super.timeGrid,
    this.lookups = const AbsenceLookups(),
  });

  final AbsenceLookups lookups;
}

/// An absence before its reason/status ids are resolved to names.
class RawAbsence {
  const RawAbsence({
    required this.id,
    required this.start,
    required this.end,
    required this.excused,
    this.reasonId,
    this.inlineReason = '',
    this.text = '',
    this.excuseStatusId,
    this.inlineExcuseStatus = '',
  });

  final int id;
  final DateTime start;
  final DateTime end;
  final bool excused;
  final int? reasonId;

  /// `absenceReason` as sent inline ('' when absent).
  final String inlineReason;
  final String text;
  final int? excuseStatusId;
  final String inlineExcuseStatus;

  /// Ids that [lookups] cannot name (and no inline name covers).
  bool needsLookup(AbsenceLookups lookups) =>
      (inlineReason.isEmpty &&
          reasonId != null &&
          !lookups.reasons.containsKey(reasonId)) ||
      (inlineExcuseStatus.isEmpty &&
          excuseStatusId != null &&
          !lookups.statuses.containsKey(excuseStatusId));

  /// Inline name first, then the lookup by id, else ''.
  AbsenceItem resolve(AbsenceLookups lookups) => AbsenceItem(
    id: id,
    start: start,
    end: end,
    excused: excused,
    reason: inlineReason.isNotEmpty
        ? inlineReason
        : (lookups.reasons[reasonId] ?? ''),
    text: text,
    excuseStatus: inlineExcuseStatus.isNotEmpty
        ? inlineExcuseStatus
        : (lookups.statuses[excuseStatusId] ?? ''),
  );
}

/// Optional API capability: absences with ids plus a way to (re)load the
/// lookup tables (for accounts stored before lookups were persisted).
abstract interface class AbsenceDetailsApi {
  Future<List<RawAbsence>> rawAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required DateTime start,
    required DateTime end,
    int? studentId,
  });

  /// Absence reasons + excuse statuses from the full master data.
  Future<AbsenceLookups> absenceLookups({
    required String host,
    required String school,
    required UntisCredentials auth,
  });
}

/// Optional API capability: parents report an absence for a child.
/// See docs/API.md "Reporting absences" for what is confirmed and assumed.
abstract interface class AbsenceReportApi {
  Future<AbsenceReportOptions> absenceReportOptions({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
  });

  Future<void> reportAbsence({
    required String host,
    required String school,
    required UntisCredentials auth,
    required AbsenceReport report,
  });

  /// The classreg absence list of [studentId] from [start] to [end] (days).
  Future<List<AbsenceRecord>> absenceRecords({
    required String host,
    required String school,
    required UntisCredentials auth,
    required int studentId,
    required DateTime start,
    required DateTime end,
  });

  /// Deletes absences by classreg id.
  Future<void> deleteAbsences({
    required String host,
    required String school,
    required UntisCredentials auth,
    required List<int> ids,
  });
}

/// Everything the app's API object provides.
abstract interface class FullUntisApi
    implements UntisApi, InfoCenterApi, AbsenceDetailsApi, AbsenceReportApi {}
