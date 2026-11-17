import 'dart:async';

import '../core/class_lead.dart';
import '../core/class_register.dart';
import '../core/excuses.dart';
import '../core/interfaces.dart';
import '../core/models.dart';

/// [ClassLeadRepository] on top of [ClassLeadApi] (getClassregData2017),
/// with the [ExcuseRepository] for statuses, ranges and saving. Nothing is
/// cached here; the dashboard is always loaded fresh.
class ClassLeadRepositoryImpl implements ClassLeadRepository {
  ClassLeadRepositoryImpl({
    required this.api,
    required this.accounts,
    required this.timetables,
    required this.excuses,
    required this.classRegister,
  });

  final UntisApi api;
  final AccountRepository accounts;
  final TimetableRepository timetables;
  final ExcuseRepository excuses;
  final ClassRegisterRepository classRegister;

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
  Future<List<ExcuseClass>> classes(Account account) async {
    if (!leadsClass(account)) return const [];
    final names = await _names(account);
    final byId = {
      for (final e
          in names?.elementsOf(ElementType.klasse) ?? const <MasterElement>[])
        e.id: e.name,
    };
    // Not in the master data: the Excuses classes may name it.
    if (account.klassenIds.any((id) => id > 0 && byId[id] == null)) {
      try {
        for (final c in (await excuses.meta(account)).classes) {
          byId[c.id] ??= c.name;
        }
      } catch (_) {}
    }
    final out = [
      for (final id in {...account.klassenIds})
        if (id > 0) ExcuseClass(id: id, name: byId[id] ?? 'Class #$id'),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  @override
  Future<ClassLeadDashboard> dashboard(
    Account account,
    ExcuseClass klasse, {
    ExcuseRange range = ExcuseRange.last14,
  }) async {
    if (!hasClassRegister(account)) {
      throw const UntisException(
        UntisException.noRight,
        'Only teacher accounts have a class dashboard.',
      );
    }
    final Object a = api;
    final meta = await excuses.meta(account);
    final days = await excuses.rangeDays(account, range);
    List<ExcuseAbsence> absences;
    var events = const <ClassRegEvent>[];
    var eventsAvailable = true;
    try {
      if (a is! ClassLeadApi) {
        throw const UntisException(-1, 'Not supported here.');
      }
      final auth = await accounts.credentials(account.id);
      final data = await a.classLeadData(
        host: account.host,
        school: account.school.loginName,
        auth: auth,
        klasseId: klasse.id,
        start: days.start,
        end: days.end,
        meta: meta,
      );
      absences = data.absences;
      final reasons = data.events.any((e) => e.reasonName.isEmpty)
          ? await classRegister.eventReasons(account)
          : const <int, String>{};
      events = [
        for (final e in data.events)
          e.reasonName.isNotEmpty || reasons[e.reasonId] == null
              ? e
              : ClassRegEvent(
                  id: e.id,
                  ttId: e.ttId,
                  studentId: e.studentId,
                  studentName: e.studentName,
                  reasonId: e.reasonId,
                  reasonName: reasons[e.reasonId]!,
                  text: e.text,
                  date: e.date,
                  author: e.author,
                ),
      ];
    } on UntisException catch (e) {
      // Refused, offline: say so. Anything else (e.g. the school has no
      // getClassregData2017): the absences from the Excuses list.
      if (e.code == UntisException.noRight || e.isNetwork || e.isTimeout) {
        rethrow;
      }
      absences = await excuses.absences(
        account,
        classId: klasse.id,
        range: range,
        filter: ExcuseFilter.all,
      );
      eventsAvailable = false;
    }
    absences = [...absences]
      ..sort((x, y) {
        final c = y.start.compareTo(x.start);
        return c != 0 ? c : x.studentName.compareTo(y.studentName);
      });
    events = [...events]
      ..sort((x, y) {
        final dx = x.date, dy = y.date;
        if (dx == null || dy == null) {
          return dx == dy ? 0 : (dx == null ? 1 : -1);
        }
        return dy.compareTo(dx);
      });
    return ClassLeadDashboard(
      klasse: klasse,
      range: range,
      start: days.start,
      end: days.end,
      meta: meta,
      absences: absences,
      events: events,
      eventsAvailable: eventsAvailable,
    );
  }
}
