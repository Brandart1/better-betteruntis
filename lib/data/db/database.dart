/// Local SQLite cache (drift). One database serves all accounts; every row is
/// scoped by `accountId`.
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Accounts. [School] is embedded as `school*` columns. Lists/sets are JSON.
@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  IntColumn get position => integer()();
  IntColumn get schoolId => integer()();
  TextColumn get schoolLoginName => text()();
  TextColumn get schoolDisplayName => text()();
  TextColumn get schoolAddress => text()();
  TextColumn get schoolHost => text()();
  TextColumn get username => text()();
  BoolColumn get anonymous => boolean()();
  TextColumn get displayName => text()();
  TextColumn get profileName => text().nullable()();
  TextColumn get elementType => text()();
  IntColumn get elementId => integer()();
  TextColumn get klassenIdsJson => text().withDefault(const Constant('[]'))();
  TextColumn get rightsJson => text().withDefault(const Constant('[]'))();
  IntColumn get masterDataTimestamp =>
      integer().withDefault(const Constant(0))();
  TextColumn get hostOverride => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MasterElementRow')
class MasterElements extends Table {
  TextColumn get accountId => text()();
  TextColumn get type => text()();
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get longName => text()();
  IntColumn get foreColor => integer().nullable()();
  IntColumn get backColor => integer().nullable()();
  BoolColumn get active => boolean()();
  BoolColumn get displayAllowed => boolean()();

  @override
  Set<Column> get primaryKey => {accountId, type, id};
}

/// Dates are stored as `yyyy-mm-dd` text (wall-clock, no zone).
@DataClassName('HolidayRow')
class Holidays extends Table {
  TextColumn get accountId => text()();
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get longName => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();

  @override
  Set<Column> get primaryKey => {accountId, id};
}

@DataClassName('SchoolYearRow')
class SchoolYears extends Table {
  TextColumn get accountId => text()();
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();

  @override
  Set<Column> get primaryKey => {accountId, id};
}

@DataClassName('TimeGridRow')
class TimeGrids extends Table {
  TextColumn get accountId => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {accountId};
}

/// One cached timetable week. [weekStart] is the Monday as `yyyy-mm-dd`.
@DataClassName('CachedWeekRow')
class CachedWeeks extends Table {
  TextColumn get accountId => text()();
  TextColumn get targetType => text()();
  IntColumn get targetId => integer()();
  TextColumn get weekStart => text()();
  TextColumn get periodsJson => text()();

  /// Milliseconds since epoch (UTC).
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {accountId, targetType, targetId, weekStart};
}

/// Info-center cache: one JSON document per account and section key (e.g.
/// `inbox`, `homework|STUDENT#7|2026-11-09..2026-11-22`). Added in v2.
@DataClassName('InfoCacheRow')
class InfoCache extends Table {
  TextColumn get accountId => text()();
  TextColumn get key => text()();
  TextColumn get json => text()();

  /// Milliseconds since epoch (UTC).
  IntColumn get fetchedAt => integer()();

  @override
  Set<Column> get primaryKey => {accountId, key};
}

/// Master-data absence reasons ([kind] `reason`) and excuse statuses
/// (`status`) by id. Added in v2.
@DataClassName('AbsenceLookupRow')
class AbsenceLookupEntries extends Table {
  TextColumn get accountId => text()();
  TextColumn get kind => text()();
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {accountId, kind, id};
}

/// Key/value app state (e.g. `activeAccountId`).
@DataClassName('AppStateRow')
class AppState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Accounts,
    MasterElements,
    Holidays,
    SchoolYears,
    TimeGrids,
    CachedWeeks,
    AppState,
    InfoCache,
    AbsenceLookupEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the app's on-device database.
  factory AppDatabase.open({String name = 'better_betteruntis'}) =>
      AppDatabase(driftDatabase(name: name));

  /// v1: initial schema. v2: [InfoCache], [AbsenceLookupEntries].
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(infoCache);
        await m.createTable(absenceLookupEntries);
      }
    },
  );

  static const activeAccountKey = 'activeAccountId';
}

/// `yyyy-mm-dd` for a wall-clock date.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Inverse of [dateKey]; returns a local midnight DateTime.
DateTime parseDateKey(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}
