/// Cache-first [TimetableRepository].
library;

import 'dart:async';

import 'package:drift/drift.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import 'db/database.dart';
import 'aggregated_timetable.dart';
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
  final Map<String, Future<List<Period>>> _inFlight = {};
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
  ) => _refreshPeriods(account, target, mondayOf(weekStart)).then((_) {});

  /// Fetches (or aggregates) a week, stores it and returns its periods.
  /// Coalesces concurrent refreshes of the same week.
  Future<List<Period>> _refreshPeriods(
    Account account,
    TimetableTarget target,
    DateTime monday,
  ) {
    final key = _key(account.id, target, monday);
    return _inFlight[key] ??= _refresh(account, target, monday, key)
        .whenComplete(() {
          _inFlight.remove(key);
        });
  }

  Future<Account?> _storedAccount(String id) async {
    final stored = (await accounts.watchAccounts().first).where(
      (a) => a.id == id,
    );
    return stored.isEmpty ? null : stored.first;
  }

  Future<List<Period>> _refresh(
    Account given,
    TimetableTarget target,
    DateTime monday,
    String key,
  ) async {
    // Use the stored account: its masterDataTimestamp may be newer.
    final account = await _storedAccount(given.id);
    if (account == null) return const []; // deleted meanwhile

    final periods = isAggregatable(target.type)
        ? await _refreshAggregatable(account, target, monday)
        : (await _fetchDirect(account, target, monday)).periods;

    // Periods last: deltas and discovered teachers are already stored.
    final now = clock();
    await db
        .into(db.cachedWeeks)
        .insertOnConflictUpdate(
          CachedWeeksCompanion.insert(
            accountId: account.id,
            targetType: target.type.apiName,
            targetId: target.id,
            weekStart: dateKey(monday),
            periodsJson: PeriodCodec.encodeList(periods),
            fetchedAt: now.millisecondsSinceEpoch,
          ),
        );
    _fetchedAt[key] = now;
    return periods;
  }

  /// One getTimetable2017 call. Applies the master-data delta and records
  /// name-only teachers before returning.
  Future<TimetableResponse> _fetchDirect(
    Account account,
    TimetableTarget target,
    DateTime monday,
  ) async {
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

    // Master-data delta + new timestamp first, so names are never stale.
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
    await _discover(account.id, res.periods);
    return res;
  }

  Future<void> _discover(String accountId, Iterable<Period> periods) async {
    final found = discoveredTeachers(periods);
    if (found.isEmpty) return;
    await _master.upsertDiscoveredTeachers(accountId, found.values);
  }

  // ---- Teacher / room timetables ----------------------------------------

  /// At most this many class weeks are fetched at once while aggregating.
  static const aggregationConcurrency = 3;

  /// `accountId|TYPE` for which a direct teacher/room fetch was refused.
  final Set<String> _directDenied = {};

  /// Running class scans per `accountId|week`.
  final Map<String, _ScanRun> _scans = {};

  /// Result of the last class scan per `accountId|week` (for diagnostics).
  final Map<String, ClassScan> _lastScans = {};

  /// Last class scan of that week in this session, or null.
  ClassScan? lastScan(Account account, DateTime weekStart) =>
      _lastScans['${account.id}|${dateKey(mondayOf(weekStart))}'];

  /// Whether a direct timetable request for [type] was refused for [account]
  /// in this session (so that type is built from class timetables).
  bool directAccessDenied(Account account, ElementType type) =>
      _directDenied.contains('${account.id}|${type.apiName}');

  /// Errors that say "not for you" rather than "try again later".
  static bool _deniedError(UntisException e) =>
      !e.isNetwork &&
      !e.isTimeout &&
      !const {-8504, -8520, -8521, -8524}.contains(e.code);

  Future<List<Period>> _refreshAggregatable(
    Account account,
    TimetableTarget target,
    DateTime monday,
  ) async {
    final typeKey = '${account.id}|${target.type.apiName}';
    if (target.id <= 0 || _directDenied.contains(typeKey)) {
      return _aggregate(account, target, monday);
    }
    final TimetableResponse direct;
    try {
      direct = await _fetchDirect(account, target, monday);
    } on UntisException catch (e) {
      if (!_deniedError(e)) rethrow;
      _directDenied.add(typeKey);
      return _aggregate(account, target, monday);
    }
    if (direct.periods.isNotEmpty) return direct.periods;
    final names = await _master.loadResolver(account.id);
    if (names.element(target.type, target.id) == null) return direct.periods;
    // Empty although the element exists: some servers answer an unpermitted
    // request with an empty week. Check the class timetables.
    try {
      final agg = await _aggregate(account, target, monday);
      if (agg.isNotEmpty) _directDenied.add(typeKey);
      return agg;
    } on UntisException {
      return direct.periods; // Genuinely empty as far as we can tell.
    }
  }

  Future<List<Period>> _aggregate(
    Account account,
    TimetableTarget target,
    DateTime monday,
  ) async {
    final scan = await _scanClasses(account, monday);
    return aggregateFor(scan.weeks, target);
  }

  @override
  Future<void> discoverTeachers(
    Account account,
    DateTime weekStart, {
    void Function(int done, int total)? onProgress,
  }) => _scanClasses(account, mondayOf(weekStart), onProgress: onProgress);

  /// Loads every class week of [monday] (cache within [maxAge], else
  /// network). Concurrent calls for the same week share one run.
  Future<ClassScan> _scanClasses(
    Account account,
    DateTime monday, {
    void Function(int done, int total)? onProgress,
  }) {
    final key = '${account.id}|${dateKey(monday)}';
    var run = _scans[key];
    if (run == null) {
      final r = run = _ScanRun();
      _scans[key] = r;
      r.future = _doScan(account, monday, r).then((scan) {
        _lastScans[key] = scan;
        return scan;
      }).whenComplete(() => _scans.remove(key));
    }
    if (onProgress != null) {
      run.listeners.add(onProgress);
      if (run.total > 0) onProgress(run.done, run.total);
    }
    return run.future;
  }

  Future<ClassScan> _doScan(Account account, DateTime monday, _ScanRun run) async {
    final names = await _master.loadResolver(account.id);
    var classes = names.elementsOf(ElementType.klasse);
    if (classes.isEmpty) {
      classes = names.elementsOf(ElementType.klasse, onlyActive: false);
    }
    run.total = classes.length;
    run.notify();
    if (classes.isEmpty) return const ClassScan(weeks: [], total: 0, failed: 0);

    Object? firstError;
    StackTrace? firstStack;
    final results = await runLimited(classes, aggregationConcurrency, (c) async {
      try {
        return await _classWeek(account, c.id, monday);
      } catch (e, s) {
        firstError ??= e;
        firstStack ??= s;
        return null;
      } finally {
        run.done++;
        run.notify();
      }
    });
    final weeks = results.nonNulls.toList();
    if (weeks.isEmpty) {
      Error.throwWithStackTrace(_wrap(firstError!), firstStack!);
    }
    // Class weeks served from cache never went through _fetchDirect.
    await _discover(account.id, weeks.expand((w) => w));
    return ClassScan(
      weeks: weeks,
      total: classes.length,
      failed: classes.length - weeks.length,
    );
  }

  Future<List<Period>> _classWeek(
    Account account,
    int classId,
    DateTime monday,
  ) async {
    final t = TimetableTarget(ElementType.klasse, classId);
    final row = await _weekQuery(account.id, t, monday).getSingleOrNull();
    if (row != null) {
      final at = DateTime.fromMillisecondsSinceEpoch(row.fetchedAt);
      if (clock().difference(at) <= maxAge) {
        return PeriodCodec.decodeList(row.periodsJson);
      }
    }
    return _refreshPeriods(account, t, monday);
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

  /// Code 0 means "network" to the UI, so internal failures must not use it —
  /// otherwise a bug in our code shows up as "No connection".
  static UntisException _wrap(Object e) =>
      e is UntisException ? e : UntisException(-1, 'Internal error: $e');
}

class _ScanRun {
  late final Future<ClassScan> future;
  final listeners = <void Function(int done, int total)>[];
  int done = 0;
  int total = 0;

  void notify() {
    for (final l in List.of(listeners)) {
      l(done, total);
    }
  }
}
