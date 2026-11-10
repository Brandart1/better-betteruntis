import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/master_data_store.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late MemorySecretStore secrets;
  late AccountRepositoryImpl repo;

  setUp(() {
    db = memoryDb();
    secrets = MemorySecretStore();
    repo = AccountRepositoryImpl(db, secrets);
  });
  tearDown(() => db.close());

  test('add persists account, secret, master data and activates it', () async {
    final stored = await repo.add(account('a'), 'SECRET', masterData(ts: 123));
    expect(stored.masterDataTimestamp, 123);
    expect((await repo.watchActive().first)!.id, 'a');
    final all = await repo.watchAccounts().first;
    expect(all.single.school.host, 'demo.webuntis.com');
    expect(all.single.klassenIds, [1, 2]);
    expect(all.single.rights, {'R_MY_TIMETABLE'});
    final creds = await repo.credentials('a');
    expect(creds.username, 'user_a');
    expect(creds.secret, 'SECRET');
    final names = await MasterDataStore(db).loadResolver('a');
    expect(
      names.elementsOf(ElementType.teacher, onlyActive: false),
      hasLength(2),
    );
  });

  test('add replaces all master rows of that account', () async {
    await repo.add(account('a'), 's', masterData());
    await repo.add(
      account('a'),
      's',
      masterData(elements: [teacher(9, 'NEW')]),
    );
    final names = await MasterDataStore(db).loadResolver('a');
    expect(names.element(ElementType.teacher, 1), isNull);
    expect(names.element(ElementType.teacher, 9)!.name, 'NEW');
    expect(await repo.watchAccounts().first, hasLength(1));
  });

  test('switching the active account', () async {
    await repo.add(account('a'), 's', masterData());
    await repo.add(account('b'), 's', masterData());
    expect((await repo.watchActive().first)!.id, 'b');
    await repo.setActive('a');
    expect((await repo.watchActive().first)!.id, 'a');
    expect(
      [for (final a in await repo.watchAccounts().first) a.id],
      ['a', 'b'],
    );
  });

  test(
    'deleting the active account falls back to another, then none',
    () async {
      await repo.add(account('a'), 'sa', masterData());
      await repo.add(account('b'), 'sb', masterData());
      await repo.delete('b');
      expect((await repo.watchActive().first)!.id, 'a');
      expect(secrets.values.containsKey('b'), isFalse);
      final names = await MasterDataStore(db).loadResolver('b');
      expect(names.elementsOf(ElementType.teacher, onlyActive: false), isEmpty);
      await repo.delete('a');
      expect(await repo.watchActive().first, isNull);
      expect(await repo.watchAccounts().first, isEmpty);
    },
  );

  test('deleting an inactive account keeps the active one', () async {
    await repo.add(account('a'), 's', masterData());
    await repo.add(account('b'), 's', masterData());
    await repo.delete('a');
    expect((await repo.watchActive().first)!.id, 'b');
  });

  test('anonymous accounts get anonymous credentials', () async {
    await repo.add(account('x', anonymous: true), '', masterData());
    final c = await repo.credentials('x');
    expect(c.anonymous, isTrue);
    expect(secrets.values, isEmpty);
  });

  test('update persists changes', () async {
    final a = await repo.add(account('a'), 's', masterData());
    await repo.update(a.copyWith(profileName: 'Sis'));
    expect((await repo.watchActive().first)!.label, 'Sis');
  });
}
