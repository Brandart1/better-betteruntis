import 'package:better_betteruntis/core/absence_details.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/master_data_store.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The schema shipped as version 1 (dumped from sqlite_master).
const _v1 = [
  '''CREATE TABLE "accounts" ("id" TEXT NOT NULL, "position" INTEGER NOT NULL, "school_id" INTEGER NOT NULL, "school_login_name" TEXT NOT NULL, "school_display_name" TEXT NOT NULL, "school_address" TEXT NOT NULL, "school_host" TEXT NOT NULL, "username" TEXT NOT NULL, "anonymous" INTEGER NOT NULL CHECK ("anonymous" IN (0, 1)), "display_name" TEXT NOT NULL, "profile_name" TEXT NULL, "element_type" TEXT NOT NULL, "element_id" INTEGER NOT NULL, "klassen_ids_json" TEXT NOT NULL DEFAULT '[]', "rights_json" TEXT NOT NULL DEFAULT '[]', "master_data_timestamp" INTEGER NOT NULL DEFAULT 0, "host_override" TEXT NULL, PRIMARY KEY ("id"))''',
  '''CREATE TABLE "master_elements" ("account_id" TEXT NOT NULL, "type" TEXT NOT NULL, "id" INTEGER NOT NULL, "name" TEXT NOT NULL, "long_name" TEXT NOT NULL, "fore_color" INTEGER NULL, "back_color" INTEGER NULL, "active" INTEGER NOT NULL CHECK ("active" IN (0, 1)), "display_allowed" INTEGER NOT NULL CHECK ("display_allowed" IN (0, 1)), PRIMARY KEY ("account_id", "type", "id"))''',
  '''CREATE TABLE "holidays" ("account_id" TEXT NOT NULL, "id" INTEGER NOT NULL, "name" TEXT NOT NULL, "long_name" TEXT NOT NULL, "start_date" TEXT NOT NULL, "end_date" TEXT NOT NULL, PRIMARY KEY ("account_id", "id"))''',
  '''CREATE TABLE "school_years" ("account_id" TEXT NOT NULL, "id" INTEGER NOT NULL, "name" TEXT NOT NULL, "start_date" TEXT NOT NULL, "end_date" TEXT NOT NULL, PRIMARY KEY ("account_id", "id"))''',
  '''CREATE TABLE "time_grids" ("account_id" TEXT NOT NULL, "json" TEXT NOT NULL, PRIMARY KEY ("account_id"))''',
  '''CREATE TABLE "cached_weeks" ("account_id" TEXT NOT NULL, "target_type" TEXT NOT NULL, "target_id" INTEGER NOT NULL, "week_start" TEXT NOT NULL, "periods_json" TEXT NOT NULL, "fetched_at" INTEGER NOT NULL, PRIMARY KEY ("account_id", "target_type", "target_id", "week_start"))''',
  '''CREATE TABLE "app_state" ("key" TEXT NOT NULL, "value" TEXT NULL, PRIMARY KEY ("key"))''',
];

void main() {
  test('a v1 database upgrades to v2 without losing data', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final s in _v1) {
            raw.execute(s);
          }
          raw.execute(
            "INSERT INTO accounts (id, position, school_id, school_login_name, "
            "school_display_name, school_address, school_host, username, "
            "anonymous, display_name, element_type, element_id) VALUES "
            "('acc1', 0, 42, 'demo-school', 'Demo', '', 'demo.webuntis.com', "
            "'max', 0, 'Max Muster', 'STUDENT', 7)",
          );
          raw.execute(
            "INSERT INTO cached_weeks VALUES "
            "('acc1', 'STUDENT', 7, '2026-11-09', '[]', 1)",
          );
          raw.execute(
            "INSERT INTO app_state VALUES ('activeAccountId', 'acc1')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    final accounts = await db.select(db.accounts).get();
    expect(accounts.single.displayName, 'Max Muster');
    expect(await db.select(db.cachedWeeks).get(), hasLength(1));
    expect((await db.select(db.appState).getSingle()).value, 'acc1');

    // New tables exist and work.
    await db
        .into(db.infoCache)
        .insert(
          InfoCacheCompanion.insert(
            accountId: 'acc1',
            key: 'inbox',
            json: '[]',
            fetchedAt: 1,
          ),
        );
    await MasterDataStore(db)
        .upsertLookups('acc1', const AbsenceLookups(reasons: {1: 'Illness'}));
    expect(await db.select(db.infoCache).get(), hasLength(1));
    expect((await MasterDataStore(db).loadLookups('acc1')).reasons, {
      1: 'Illness',
    });
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });

  test('fresh database creates every table at the current version', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((r) => r.read<String>('name'))
        .get();
    expect(tables, containsAll(['info_cache', 'absence_lookup_entries']));
    await db
        .into(db.infoCache)
        .insert(
          InfoCacheCompanion.insert(
            accountId: 'x',
            key: 'k',
            json: '{}',
            fetchedAt: 0,
          ),
          mode: InsertMode.insertOrReplace,
        );
  });
}
