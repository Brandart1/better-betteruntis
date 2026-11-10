/// Persistence helpers for per-account master data.
library;

import 'package:drift/drift.dart';

import '../core/models.dart';
import 'db/database.dart';
import 'name_resolver_impl.dart';
import 'period_codec.dart';

class MasterDataStore {
  MasterDataStore(this.db);
  final AppDatabase db;

  /// Replaces all master data of [accountId] with [md].
  Future<void> replaceAll(String accountId, MasterData md) =>
      db.transaction(() async {
        await clear(accountId);
        await upsertDelta(accountId, md);
      });

  /// Removes all master data of [accountId].
  Future<void> clear(String accountId) async {
    await (db.delete(
      db.masterElements,
    )..where((t) => t.accountId.equals(accountId))).go();
    await (db.delete(
      db.holidays,
    )..where((t) => t.accountId.equals(accountId))).go();
    await (db.delete(
      db.schoolYears,
    )..where((t) => t.accountId.equals(accountId))).go();
    await (db.delete(
      db.timeGrids,
    )..where((t) => t.accountId.equals(accountId))).go();
  }

  /// Upserts the entries in [md]; nothing is deleted. A non-null time grid
  /// replaces the stored one.
  Future<void> upsertDelta(String accountId, MasterData md) =>
      db.transaction(() async {
        await db.batch((b) {
          b.insertAllOnConflictUpdate(db.masterElements, [
            for (final e in md.elements)
              MasterElementsCompanion.insert(
                accountId: accountId,
                type: e.type.apiName,
                id: e.id,
                name: e.name,
                longName: e.longName,
                foreColor: Value(e.foreColor),
                backColor: Value(e.backColor),
                active: e.active,
                displayAllowed: e.displayAllowed,
              ),
          ]);
          b.insertAllOnConflictUpdate(db.holidays, [
            for (final h in md.holidays)
              HolidaysCompanion.insert(
                accountId: accountId,
                id: h.id,
                name: h.name,
                longName: h.longName,
                startDate: dateKey(h.start),
                endDate: dateKey(h.end),
              ),
          ]);
          b.insertAllOnConflictUpdate(db.schoolYears, [
            for (final y in md.schoolYears)
              SchoolYearsCompanion.insert(
                accountId: accountId,
                id: y.id,
                name: y.name,
                startDate: dateKey(y.start),
                endDate: dateKey(y.end),
              ),
          ]);
          if (md.timeGrid != null) {
            b.insert(
              db.timeGrids,
              TimeGridsCompanion.insert(
                accountId: accountId,
                json: PeriodCodec.encodeTimeGrid(md.timeGrid!),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });

  Future<NameResolverImpl> loadResolver(String accountId) async {
    final elements = await (db.select(
      db.masterElements,
    )..where((t) => t.accountId.equals(accountId))).get();
    final holidays =
        await (db.select(db.holidays)
              ..where((t) => t.accountId.equals(accountId))
              ..orderBy([(t) => OrderingTerm.asc(t.startDate)]))
            .get();
    final grid = await (db.select(
      db.timeGrids,
    )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
    return NameResolverImpl(
      elements: [
        for (final r in elements)
          MasterElement(
            type: ElementType.parse(r.type),
            id: r.id,
            name: r.name,
            longName: r.longName,
            foreColor: r.foreColor,
            backColor: r.backColor,
            active: r.active,
            displayAllowed: r.displayAllowed,
          ),
      ],
      holidays: [
        for (final r in holidays)
          Holiday(
            id: r.id,
            name: r.name,
            longName: r.longName,
            start: parseDateKey(r.startDate),
            end: parseDateKey(r.endDate),
          ),
      ],
      timeGrid: grid == null ? null : PeriodCodec.decodeTimeGrid(grid.json),
    );
  }

  Future<List<SchoolYear>> schoolYears(String accountId) async {
    final rows =
        await (db.select(db.schoolYears)
              ..where((t) => t.accountId.equals(accountId))
              ..orderBy([(t) => OrderingTerm.asc(t.startDate)]))
            .get();
    return [
      for (final r in rows)
        SchoolYear(
          id: r.id,
          name: r.name,
          start: parseDateKey(r.startDate),
          end: parseDateKey(r.endDate),
        ),
    ];
  }

  /// Emits a fresh resolver now and whenever master-data tables change.
  /// (Writes for other accounts also trigger a — content-identical — emission.)
  Stream<NameResolverImpl> watchResolver(String accountId) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {db.masterElements, db.holidays, db.timeGrids},
      )
      .watch()
      .asyncMap((_) => loadResolver(accountId));
}
