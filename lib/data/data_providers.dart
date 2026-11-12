/// ProviderScope overrides wiring the data layer into lib/core/providers.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/class_register.dart';
import '../core/info.dart';
import '../core/interfaces.dart';
import '../core/providers.dart';
import 'account_repository_impl.dart';
import 'class_register_repository_impl.dart';
import 'db/database.dart';
import 'info_center_repository_impl.dart';
import 'secret_store.dart';
import 'timetable_repository_impl.dart';

/// The app database. Overridden by [dataOverrides]; tests may override it with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Overrides for [accountRepositoryProvider], [timetableRepositoryProvider]
/// and [infoCenterRepositoryProvider] (the latter needs an API that also
/// implements [InfoCenterApi]; reading it otherwise throws).
///
/// [api] defaults to whatever [untisApiProvider] resolves to (main.dart
/// overrides that). [database], [secrets] and [clock] are for tests/demo.
List<Override> dataOverrides({
  UntisApi? api,
  AppDatabase? database,
  SecretStore? secrets,
  DateTime Function()? clock,
}) => [
  if (database != null) appDatabaseProvider.overrideWithValue(database),
  if (secrets != null) secretStoreProvider.overrideWithValue(secrets),
  accountRepositoryProvider.overrideWith(
    (ref) => AccountRepositoryImpl(
      ref.watch(appDatabaseProvider),
      ref.watch(secretStoreProvider),
    ),
  ),
  timetableRepositoryProvider.overrideWith((ref) {
    final repo = TimetableRepositoryImpl(
      api: api ?? ref.watch(untisApiProvider),
      db: ref.watch(appDatabaseProvider),
      accounts: ref.watch(accountRepositoryProvider),
      clock: clock,
    );
    ref.onDispose(repo.dispose);
    return repo;
  }),
  infoCenterRepositoryProvider.overrideWith(
    (ref) => InfoCenterRepositoryImpl(
      api: api ?? ref.watch(untisApiProvider),
      db: ref.watch(appDatabaseProvider),
      accounts: ref.watch(accountRepositoryProvider),
      clock: clock,
    ),
  ),
  classRegisterRepositoryProvider.overrideWith(
    (ref) => ClassRegisterRepositoryImpl(
      api: api ?? ref.watch(untisApiProvider),
      accounts: ref.watch(accountRepositoryProvider),
      timetables: ref.watch(timetableRepositoryProvider),
      clock: clock,
    ),
  ),
];
