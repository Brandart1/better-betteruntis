import 'dart:async';

import '../core/class_register.dart';
import '../core/excuses.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// [ExcuseRepository] on top of [ExcuseApi]. Only the meta is cached (per
/// account, for the session); lists are always loaded fresh.
class ExcuseRepositoryImpl implements ExcuseRepository {
  ExcuseRepositoryImpl({
    required this.api,
    required this.accounts,
    required this.timetables,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final UntisApi api;
  final AccountRepository accounts;
  final TimetableRepository timetables;
  final DateTime Function() clock;

  final _meta = <String, ExcuseMeta>{};

  ExcuseApi get _api {
    final Object a = api;
    if (a is ExcuseApi) return a;
    throw const UntisException(-1, 'Excuses are not supported here.');
  }

  void _check(Account a) {
    if (!hasClassRegister(a)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts can excuse absences.',
      );
    }
  }

  Future<NameResolver?> _names(Account a) async {
    try {
      return await timetables
          .watchNames(a)
          .first
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ExcuseMeta> meta(Account account) async {
    _check(account);
    final cached = _meta[account.id];
    if (cached != null) return cached;
    final auth = await accounts.credentials(account.id);
    var meta = await _api.excuseMeta(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
    );
    // The fallback has no classes: all of the school's, by name.
    if (meta.classes.isEmpty) {
      final names = await _names(account);
      final classes = [
        for (final e
            in names?.elementsOf(ElementType.klasse) ?? const <MasterElement>[])
          ExcuseClass(id: e.id, name: e.name),
      ]..sort((a, b) => a.name.compareTo(b.name));
      meta = meta.copyWith(classes: classes);
    }
    return _meta[account.id] = meta;
  }

  @override
  Future<({DateTime start, DateTime end})> rangeDays(
    Account account,
    ExcuseRange range,
  ) async {
    final today = clock();
    if (range != ExcuseRange.schoolYear) return range.days(today);
    final years = (await _names(account))?.schoolYears ?? const [];
    final d = DateTime(today.year, today.month, today.day);
    final year = years
        .where((y) => !d.isBefore(y.start) && !d.isAfter(y.end))
        .firstOrNull;
    return range.days(today, year: year);
  }

  @override
  Future<List<ExcuseAbsence>> absences(
    Account account, {
    required int classId,
    required ExcuseRange range,
    required ExcuseFilter filter,
  }) async {
    final m = await meta(account);
    final days = await rangeDays(account, range);
    final auth = await accounts.credentials(account.id);
    final list = await _api.excuseAbsences(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      meta: m,
      query: ExcuseQuery(
        classId: classId,
        range: range,
        start: days.start,
        end: days.end,
        filter: filter,
      ),
    );
    // The fallback list is not filtered by the server.
    return [
      for (final a in list)
        if (filter.type == null || a.type == filter.type) a,
    ]..sort((a, b) {
      final c = b.start.compareTo(a.start);
      return c != 0 ? c : a.studentName.compareTo(b.studentName);
    });
  }

  @override
  Future<ExcuseAbsence> save(
    Account account,
    ExcuseAbsence absence, {
    required ExcuseStatus status,
    required String text,
  }) async {
    _check(account);
    if (!absence.excuseStatusEditable) {
      throw const UntisException(
        UntisException.noRight,
        "You can't change the excuse of this absence.",
      );
    }
    final m = await meta(account);
    final auth = await accounts.credentials(account.id);
    final saved = await _api.saveExcuse(
      host: account.host,
      school: account.school.loginName,
      auth: auth,
      meta: m,
      absence: absence,
      status: status,
      text: text,
    );
    return saved ?? absence.withExcuse(status, text.trim());
  }
}
