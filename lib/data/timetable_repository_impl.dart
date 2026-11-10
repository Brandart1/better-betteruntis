/// Cache-first [TimetableRepository].
library;

import 'dart:async';

import 'package:drift/drift.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import 'db/database.dart';
import 'master_data_store.dart';
import 'period_codec.dart';

/// Monday 00:00 (local wall clock) of the week containing [day].
DateTime mondayOf(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

class TimetableRepositoryImpl implements TimetableRepository {
  TimetableRepositoryImpl({
    required this.api,
    required this.db,
    required this.accounts,
    DateTime Function()? clock,
    this.maxAge = const Duration(minutes: 5),
  }) : clock = clock ?? DateTime.now,
       _master = MasterDataStore(db);

  final UntisApi api;
  final AppDatabase db;
  final AccountRepository accounts;
  final DateTime Function() clock;

  /// Cached weeks older than this are refreshed in the background.
  final Duration maxAge;

  final MasterDataStore _master;
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<void>> _inFlight = {};
  final _errors = StreamController<UntisException?>.broadcast();
  UntisException? _lastError;

  /// Result of each background refresh started by [watchWeek]: the error, or
  /// null on success. Broadcast; errors here never error the week streams
  /// when cached data exists.
  Stream<UntisException?> get errors => _errors.stream;

  /// Last background-refresh error (null after a successful refresh).
  UntisException? get lastError => _lastError;

  static String _key(String accountId, TimetableTarget t, DateTime monday) =>
      '$accountId|${t.type.apiName}|${t.id}|${dateKey(monday)}';

  SimpleSelectStatement<$CachedWeeksTable, CachedWeekRow> _weekQuery(
    String accountId,
    TimetableTarget target,
    DateTime monday,
  ) => db.select(db.cachedWeeks)
    ..where(
      (t) =>
          t.accountId.equals(accountId) &
          t.targetType.equals(target.type.apiName) &
          t.targetId.equals(target.id) &
          t.weekStart.equals(dateKey(monday)),
    );

  @override
  Stream<List<Period>> watchWeek(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) {
    final monday = mondayOf(weekStart);
    final key = _key(account.id, target, monday);
    StreamSubscription<CachedWeekRow?>? sub;
    late final StreamController<List<Period>> out;
    out = StreamController<List<Period>>(
      onListen: () {
        var first = true;
        sub = _weekQuery(account.id, target, monday).watchSingleOrNull().listen(
          (row) {
            if (row != null) {
              _fetchedAt[key] = DateTime.fromMillisecondsSinceEpoch(
                row.fetchedAt,
              );
              out.add(PeriodCodec.decodeList(row.periodsJson));
            }
            if (!first) return;
            first = false;
            final stale =
                row == null || clock().difference(_fetchedAt[key]!) > maxAge;
            if (!stale) return;
            refresh(account, target, monday).then(
              (_) {
                _lastError = null;
                _errors.add(null);
              },
              onError: (Object e, StackTrace s) {
                final ex = _wrap(e);
                _lastError = ex;
                _errors.add(ex);
                // Without cached data there is nothing to show: surface it.
                if (row == null && !out.isClosed) out.addError(ex, s);
              },
            );
          },
          onError: out.addError,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<void> refresh(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) {
    final monday = mondayOf(weekStart);
    final key = _key(account.id, target, monday);
    // Coalesce concurrent refreshes of the same week.
    return _inFlight[key] ??= _refresh(account, target, monday, key)
        .whenComplete(() {
          _inFlight.remove(key);
        });
  }

  Future<void> _refresh(
    Account given,
    TimetableTarget target,
    DateTime monday,
    String key,
  ) async {
    // Use the stored account: its masterDataTimestamp may be newer.
    final stored = (await accounts.watchAccounts().first).where(
      (a) => a.id == given.id,
    );
    if (stored.isEmpty) return; // deleted meanwhile
    final account = stored.first;

    final TimetableResponse res;
    try {
      res = await api.timetable(
        host: account.host,
        school: account.school.loginName,
        auth: await accounts.credentials(account.id),
        target: target,
        start: monday,
        end: DateTime(monday.year, monday.month, monday.day + 6),
        masterDataTimestamp: account.masterDataTimestamp,
      );
    } catch (e) {
      throw _wrap(e);
    }

    // 1. Master-data delta + new timestamp first, so names are never stale.
    final delta = res.masterDataDelta;
    if (delta != null) {
      await db.transaction(() async {
        await _master.upsertDelta(account.id, delta);
        if (delta.timestamp != account.masterDataTimestamp) {
          await accounts.update(
            account.copyWith(masterDataTimestamp: delta.timestamp),
          );
        }
      });
    }

    // 2. Then the periods.
    final now = clock();
    await db
        .into(db.cachedWeeks)
        .insertOnConflictUpdate(
          CachedWeeksCompanion.insert(
            accountId: account.id,
            targetType: target.type.apiName,
            targetId: target.id,
            weekStart: dateKey(monday),
            periodsJson: PeriodCodec.encodeList(res.periods),
            fetchedAt: now.millisecondsSinceEpoch,
          ),
        );
    _fetchedAt[key] = now;
  }

  @override
  Stream<NameResolver> watchNames(Account account) =>
      _master.watchResolver(account.id);

  /// Synchronous: known once the week was watched or refreshed in this
  /// session. Use [loadLastRefreshed] to read it from the database.
  @override
  DateTime? lastRefreshed(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) => _fetchedAt[_key(account.id, target, mondayOf(weekStart))];

  Future<DateTime?> loadLastRefreshed(
    Account account,
    TimetableTarget target,
    DateTime weekStart,
  ) async {
    final monday = mondayOf(weekStart);
    final row = await _weekQuery(account.id, target, monday).getSingleOrNull();
    if (row == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(row.fetchedAt);
    _fetchedAt[_key(account.id, target, monday)] = at;
    return at;
  }

  Future<void> dispose() => _errors.close();

  static UntisException _wrap(Object e) =>
      e is UntisException ? e : UntisException(0, e.toString());
}
