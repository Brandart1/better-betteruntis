/// Cache-first [InfoCenterRepository] backed by the [InfoCache] table.
///
/// Every section is one JSON document per account and key. A stream first
/// emits the cached value (`refreshing: true`), then the network result, or
/// the cached value again with the error. Within [maxAge] of the last fetch
/// the cached value is emitted alone (no request) unless `force` is set.
///
/// Absence names: when the API also implements [AbsenceDetailsApi] (the real
/// and demo APIs do), absences are fetched with their reason/status ids and
/// resolved here against the lookups persisted from master data (login and
/// timetable deltas, see MasterDataStore). Inline names win. If an id is
/// unknown (e.g. an account stored before lookups were persisted), the
/// lookups are loaded once per session via `absenceLookups` and stored.
library;

import 'dart:async';

import 'package:drift/drift.dart';

import '../core/absence_details.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/models.dart';
import 'db/database.dart';
import 'info_codec.dart';
import 'master_data_store.dart';

class InfoCenterRepositoryImpl implements InfoCenterRepository {
  /// [api] must implement [InfoCenterApi] (see [FullUntisApi]).
  InfoCenterRepositoryImpl({
    required this.api,
    required this.db,
    required this.accounts,
    DateTime Function()? clock,
    this.maxAge = const Duration(minutes: 10),
  }) : clock = clock ?? DateTime.now,
       _master = MasterDataStore(db) {
    if (api is! InfoCenterApi) {
      throw ArgumentError.value(api, 'api', 'does not implement InfoCenterApi');
    }
  }

  final UntisApi api;
  final AppDatabase db;
  final AccountRepository accounts;
  final DateTime Function() clock;

  /// Cached sections younger than this are not refreshed (unless forced).
  final Duration maxAge;

  final MasterDataStore _master;
  final Map<String, Future<(Object?, DateTime)>> _inFlight = {};

  /// Accounts whose absence lookups were (re)loaded in this session.
  final Set<String> _lookupsLoaded = {};

  InfoCenterApi get _info => api as InfoCenterApi;

  // ---- Generic cache-first section ---------------------------------------

  Stream<Cached<T>> _section<T>(
    Account a,
    String key,
    InfoCodec<T> codec,
    Future<T> Function(UntisCredentials auth) fetch, {
    required bool force,
  }) async* {
    final row =
        await (db.select(db.infoCache)
              ..where((t) => t.accountId.equals(a.id) & t.key.equals(key)))
            .getSingleOrNull();
    final cached = row == null ? null : codec.decode(row.json);
    final cachedAt = cached == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row!.fetchedAt);
    if (!force && cachedAt != null && clock().difference(cachedAt) < maxAge) {
      yield Cached(data: cached, fetchedAt: cachedAt);
      return;
    }
    yield Cached(data: cached, fetchedAt: cachedAt, refreshing: true);
    try {
      final flightKey = '${a.id}|$key';
      final (fresh, at) = await (_inFlight[flightKey] ??=
          _fetchAndStore(a, key, codec, fetch).whenComplete(() {
            // Block body: returning the removed future would make
            // whenComplete wait for itself.
            _inFlight.remove(flightKey);
          }));
      yield Cached(data: fresh as T, fetchedAt: at);
    } catch (e) {
      yield Cached(data: cached, fetchedAt: cachedAt, error: _wrap(e));
    }
  }

  Future<(Object?, DateTime)> _fetchAndStore<T>(
    Account a,
    String key,
    InfoCodec<T> codec,
    Future<T> Function(UntisCredentials auth) fetch,
  ) async {
    final data = await fetch(await accounts.credentials(a.id));
    final now = clock();
    if (await _exists(a.id)) {
      await db
          .into(db.infoCache)
          .insertOnConflictUpdate(
            InfoCacheCompanion.insert(
              accountId: a.id,
              key: key,
              json: codec.encode(data),
              fetchedAt: now.millisecondsSinceEpoch,
            ),
          );
    }
    return (data, now);
  }

  Future<bool> _exists(String accountId) async =>
      (await accounts.watchAccounts().first).any((a) => a.id == accountId);

  Stream<Cached<List<E>>> _empty<E>() =>
      Stream.value(Cached(data: <E>[], fetchedAt: clock()));

  static String _range(DateTime s, DateTime e) =>
      '${dateKey(s)}..${dateKey(e)}';

  static TimetableTarget _own(Account a) =>
      TimetableTarget(a.elementType, a.elementId);

  // ---- Sections ------------------------------------------------------------

  @override
  Stream<Cached<List<Message>>> messagesOfDay(
    Account a,
    DateTime day, {
    bool force = false,
  }) => _section(
    a,
    'messagesOfDay|${dateKey(day)}',
    messagesCodec,
    (auth) => api.messagesOfDay(
      host: a.host,
      school: a.school.loginName,
      auth: auth,
      date: day,
    ),
    force: force,
  );

  @override
  Stream<Cached<List<InboxMessage>>> inbox(Account a, {bool force = false}) {
    if (a.anonymous) return _empty();
    return _section(
      a,
      'inbox',
      inboxCodec,
      (auth) =>
          _info.inbox(host: a.host, school: a.school.loginName, auth: auth),
      force: force,
    );
  }

  /// Network first (the message may have changed); falls back to the copy
  /// cached by an earlier open.
  @override
  Future<InboxMessageDetail> inboxMessage(Account a, int id) async {
    if (a.anonymous) {
      throw const UntisException(UntisException.noRight, 'No inbox');
    }
    final key = 'inboxMessage|$id';
    try {
      final (data, _) = await _fetchAndStore(
        a,
        key,
        inboxDetailCodec,
        (auth) => _info.inboxMessage(
          host: a.host,
          school: a.school.loginName,
          auth: auth,
          id: id,
        ),
      );
      return data! as InboxMessageDetail;
    } catch (e) {
      final row =
          await (db.select(db.infoCache)
                ..where((t) => t.accountId.equals(a.id) & t.key.equals(key)))
              .getSingleOrNull();
      final cached = row == null ? null : inboxDetailCodec.decode(row.json);
      if (cached != null) return cached;
      throw _wrap(e);
    }
  }

  @override
  Stream<Cached<List<HomeworkItem>>> homework(
    Account a,
    DateTime start,
    DateTime end, {
    bool force = false,
  }) {
    if (a.anonymous) return _empty();
    final t = _own(a);
    return _section(
      a,
      'homework|${t.type.apiName}#${t.id}|${_range(start, end)}',
      homeworkCodec,
      (auth) => _info.homework(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        target: t,
        start: start,
        end: end,
      ),
      force: force,
    );
  }

  @override
  Stream<Cached<List<ExamItem>>> exams(
    Account a,
    DateTime start,
    DateTime end, {
    bool force = false,
  }) {
    final t = _own(a);
    return _section(
      a,
      'exams|${t.type.apiName}#${t.id}|${_range(start, end)}',
      examsCodec,
      (auth) => _info.exams(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        target: t,
        start: start,
        end: end,
      ),
      force: force,
    );
  }

  @override
  Stream<Cached<List<AbsenceItem>>> absences(
    Account a,
    DateTime start,
    DateTime end, {
    bool force = false,
  }) {
    if (a.anonymous) return _empty();
    return _section(
      a,
      'absences|${_range(start, end)}',
      absencesCodec,
      (auth) => _fetchAbsences(a, auth, start, end),
      force: force,
    );
  }

  Future<List<AbsenceItem>> _fetchAbsences(
    Account a,
    UntisCredentials auth,
    DateTime start,
    DateTime end,
  ) async {
    final Object details = api;
    if (details is! AbsenceDetailsApi) {
      return _info.absences(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        start: start,
        end: end,
      );
    }
    final raw = await details.rawAbsences(
      host: a.host,
      school: a.school.loginName,
      auth: auth,
      start: start,
      end: end,
    );
    var lookups = await _master.loadLookups(a.id);
    if (raw.any((r) => r.needsLookup(lookups)) && _lookupsLoaded.add(a.id)) {
      try {
        final loaded = await details.absenceLookups(
          host: a.host,
          school: a.school.loginName,
          auth: auth,
        );
        if (await _exists(a.id)) await _master.upsertLookups(a.id, loaded);
        lookups = lookups.merge(loaded);
      } catch (_) {
        // Names stay empty; the absences themselves are still shown.
      }
    }
    return [for (final r in raw) r.resolve(lookups)];
  }

  @override
  Stream<Cached<List<OfficeHourItem>>> officeHours(
    Account a,
    DateTime start, {
    bool force = false,
  }) {
    if (a.klassenIds.isEmpty) return _empty();
    final klasse = a.klassenIds.first;
    return _section(
      a,
      'officeHours|$klasse|${dateKey(start)}',
      officeHoursCodec,
      (auth) => _info.officeHours(
        host: a.host,
        school: a.school.loginName,
        auth: auth,
        klasseId: klasse,
        start: start,
      ),
      force: force,
    );
  }

  /// Removes all cached info of [accountId] (also done by account deletion).
  Future<void> clear(String accountId) => (db.delete(
    db.infoCache,
  )..where((t) => t.accountId.equals(accountId))).go();

  /// Code 0 means "network" to the UI, so internal failures must not use it.
  static UntisException _wrap(Object e) =>
      e is UntisException ? e : UntisException(-1, 'Internal error: $e');
}
