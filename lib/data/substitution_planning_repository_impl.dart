import 'dart:async';

import '../core/class_register.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import '../core/substitution_planning.dart';

/// [SubstitutionPlanningRepository] on top of [SubstitutionPlanningApi].
/// Only the absence form is cached (per account, for the session); lists
/// are always loaded fresh.
class SubstitutionPlanningRepositoryImpl
    implements SubstitutionPlanningRepository {
  SubstitutionPlanningRepositoryImpl({
    required this.api,
    required this.accounts,
    required this.timetables,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final UntisApi api;
  final AccountRepository accounts;
  final TimetableRepository timetables;
  final DateTime Function() clock;

  final _forms = <String, TeacherAbsenceForm>{};
  final _availability = <String, SubstitutionAvailability>{};

  /// At most this many own timetable weeks are refreshed after reporting a
  /// long absence (the rest loads when browsed).
  static const maxRefreshWeeks = 6;

  SubstitutionPlanningApi get _api {
    final Object a = api;
    if (a is SubstitutionPlanningApi) return a;
    throw const UntisException(
      -1,
      'Substitution planning is not supported here.',
    );
  }

  void _check(Account a) {
    if (!hasClassRegister(a)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts can use substitution planning.',
      );
    }
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Refreshes the own timetable weeks from [start] to [end]; failures are
  /// ignored (the change itself went through).
  Future<void> _refresh(Account account, DateTime start, DateTime end) async {
    final target = TimetableTarget(account.elementType, account.elementId);
    var m = _mondayOf(start);
    final last = _mondayOf(end);
    for (var i = 0; i < maxRefreshWeeks && !m.isAfter(last); i++) {
      try {
        await timetables.refresh(account, target, m);
      } catch (_) {}
      m = DateTime(m.year, m.month, m.day + 7);
    }
  }

  @override
  Future<List<SubstitutionRequest>> requests(Account account) async {
    _check(account);
    final auth = await accounts.credentials(account.id);
    final list = await _api.substitutionRequests(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
    );
    return [...list]..sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return a.isPending
          ? a.start.compareTo(b.start)
          : b.start.compareTo(a.start);
    });
  }

  @override
  Future<SubstitutionRequest> answer(
    Account account,
    SubstitutionRequest request, {
    required bool accept,
  }) async {
    _check(account);
    if (!request.isPending) {
      throw UntisException(
        -1,
        'This request is no longer open (${request.state.label}).',
      );
    }
    final auth = await accounts.credentials(account.id);
    await _api.answerSubstitutionRequest(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      request: request,
      accept: accept,
    );
    if (accept) await _refresh(account, request.start, request.end);
    return request.withState(
      accept
          ? SubstitutionRequestState.accepted
          : SubstitutionRequestState.declined,
    );
  }

  @override
  Future<List<TeacherAbsence>> absences(Account account) async {
    _check(account);
    final auth = await accounts.credentials(account.id);
    final list = await _api.teacherAbsences(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
    );
    final now = clock();
    final current = [
      for (final a in list)
        if (a.end.isAfter(now)) a,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final past = [
      for (final a in list)
        if (!a.end.isAfter(now)) a,
    ]..sort((a, b) => b.start.compareTo(a.start));
    return [...current, ...past];
  }

  @override
  Future<TeacherAbsenceForm> form(Account account) async {
    _check(account);
    final cached = _forms[account.id];
    if (cached != null) return cached;
    final auth = await accounts.credentials(account.id);
    return _forms[account.id] = await _api.teacherAbsenceForm(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
    );
  }

  @override
  Future<SubstitutionAvailability> availability(
    Account account, {
    bool refresh = false,
  }) async {
    if (!hasClassRegister(account)) return SubstitutionAvailability.none;
    final cached = _availability[account.id];
    if (cached != null && !refresh) return cached;
    try {
      final auth = await accounts.credentials(account.id);
      return _availability[account.id] = await _api.homeAvailability(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
      );
    } on UntisException catch (e) {
      // 404: the school has no home view, a definite answer (cached).
      if (e.code == -8532) {
        return _availability[account.id] = SubstitutionAvailability.none;
      }
      return SubstitutionAvailability.none;
    } catch (_) {
      return SubstitutionAvailability.none;
    }
  }

  @override
  Future<void> reportAbsence(
    Account account, {
    required DateTime start,
    required DateTime end,
    int? reasonId,
    String note = '',
  }) async {
    _check(account);
    if (!end.isAfter(start)) {
      throw const UntisException(-1, 'The end must be after the start.');
    }
    final auth = await accounts.credentials(account.id);
    await _api.createTeacherAbsence(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      draft: TeacherAbsenceDraft(
        teacherId: account.elementId,
        start: start,
        end: end,
        reasonId: reasonId,
        note: note.trim(),
      ),
    );
    await _refresh(account, start, end);
  }
}
