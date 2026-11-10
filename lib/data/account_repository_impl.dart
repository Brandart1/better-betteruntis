/// [AccountRepository] backed by drift + a [SecretStore].
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/interfaces.dart';
import '../core/models.dart';
import 'db/database.dart';
import 'master_data_store.dart';
import 'secret_store.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this.db, this.secrets) : _master = MasterDataStore(db);

  final AppDatabase db;
  final SecretStore secrets;
  final MasterDataStore _master;

  SimpleSelectStatement<$AccountsTable, AccountRow> get _ordered =>
      db.select(db.accounts)..orderBy([(t) => OrderingTerm.asc(t.position)]);

  @override
  Stream<List<Account>> watchAccounts() =>
      _ordered.watch().map((rows) => rows.map(_fromRow).toList());

  @override
  Stream<Account?> watchActive() {
    final q = db.select(db.accounts).join([
      innerJoin(
        db.appState,
        db.appState.value.equalsExp(db.accounts.id) &
            db.appState.key.equals(AppDatabase.activeAccountKey),
      ),
    ]);
    return q.watch().map(
      (rows) =>
          rows.isEmpty ? null : _fromRow(rows.first.readTable(db.accounts)),
    );
  }

  /// The stored account with [accountId], or null.
  Future<Account?> get(String accountId) async {
    final row = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(accountId))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<String?> activeId() async {
    final row =
        await (db.select(db.appState)
              ..where((t) => t.key.equals(AppDatabase.activeAccountKey)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> _setActiveId(String? id) => db
      .into(db.appState)
      .insertOnConflictUpdate(
        AppStateCompanion.insert(
          key: AppDatabase.activeAccountKey,
          value: Value(id),
        ),
      );

  @override
  Future<void> setActive(String accountId) async {
    if (await get(accountId) == null) {
      throw ArgumentError.value(accountId, 'accountId', 'unknown account');
    }
    await _setActiveId(accountId);
  }

  @override
  Future<Account> add(
    Account account,
    String secret,
    MasterData masterData,
  ) async {
    final stored = account.copyWith(masterDataTimestamp: masterData.timestamp);
    if (!account.anonymous) await secrets.write(account.id, secret);
    await db.transaction(() async {
      final existing = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(account.id))).getSingleOrNull();
      final position = existing?.position ?? await _nextPosition();
      await db
          .into(db.accounts)
          .insertOnConflictUpdate(_toCompanion(stored, position));
      await _master.replaceAll(account.id, masterData);
      await _setActiveId(account.id);
    });
    return stored;
  }

  Future<int> _nextPosition() async {
    final max = db.accounts.position.max();
    final row = await (db.selectOnly(
      db.accounts,
    )..addColumns([max])).getSingle();
    return (row.read(max) ?? -1) + 1;
  }

  @override
  Future<void> update(Account account) async {
    final row = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(account.id))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(account.id, 'account.id', 'unknown account');
    }
    await db
        .into(db.accounts)
        .insertOnConflictUpdate(_toCompanion(account, row.position));
  }

  @override
  Future<void> delete(String accountId) async {
    await db.transaction(() async {
      await (db.delete(db.accounts)..where((t) => t.id.equals(accountId))).go();
      await _master.clear(accountId);
      await (db.delete(
        db.cachedWeeks,
      )..where((t) => t.accountId.equals(accountId))).go();
      final active = await activeId();
      if (active == accountId || active == null) {
        final next = await (_ordered..limit(1)).getSingleOrNull();
        await _setActiveId(next?.id);
      }
    });
    await secrets.delete(accountId);
  }

  @override
  Future<UntisCredentials> credentials(String accountId) async {
    final account = await get(accountId);
    if (account == null) {
      throw ArgumentError.value(accountId, 'accountId', 'unknown account');
    }
    if (account.anonymous) return const UntisCredentials.anonymous();
    final secret = await secrets.read(accountId);
    if (secret == null) {
      throw const UntisException(
        UntisException.invalidPassword,
        'No secret stored for this account; please log in again.',
      );
    }
    return UntisCredentials.user(account.username, secret);
  }

  static Account _fromRow(AccountRow r) => Account(
    id: r.id,
    school: School(
      schoolId: r.schoolId,
      loginName: r.schoolLoginName,
      displayName: r.schoolDisplayName,
      address: r.schoolAddress,
      host: r.schoolHost,
    ),
    username: r.username,
    anonymous: r.anonymous,
    displayName: r.displayName,
    profileName: r.profileName,
    elementType: ElementType.parse(r.elementType),
    elementId: r.elementId,
    klassenIds: _decodeList(r.klassenIdsJson).whereType<int>().toList(),
    rights: _decodeList(r.rightsJson).whereType<String>().toSet(),
    masterDataTimestamp: r.masterDataTimestamp,
    hostOverride: r.hostOverride,
  );

  static List<Object?> _decodeList(String json) {
    try {
      final v = jsonDecode(json);
      return v is List ? v : const [];
    } on FormatException {
      return const [];
    }
  }

  static AccountsCompanion _toCompanion(Account a, int position) =>
      AccountsCompanion.insert(
        id: a.id,
        position: position,
        schoolId: a.school.schoolId,
        schoolLoginName: a.school.loginName,
        schoolDisplayName: a.school.displayName,
        schoolAddress: a.school.address,
        schoolHost: a.school.host,
        username: a.username,
        anonymous: a.anonymous,
        displayName: a.displayName,
        profileName: Value(a.profileName),
        elementType: a.elementType.apiName,
        elementId: a.elementId,
        klassenIdsJson: Value(jsonEncode(a.klassenIds)),
        rightsJson: Value(jsonEncode(a.rights.toList())),
        masterDataTimestamp: Value(a.masterDataTimestamp),
        hostOverride: Value(a.hostOverride),
      );
}
