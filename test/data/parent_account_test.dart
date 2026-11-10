import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/data/account_repository_impl.dart';
import 'package:better_betteruntis/data/db/database.dart';
import 'package:better_betteruntis/data/secret_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'migration_test.dart' show v1Schema;

const _kids = [
  AccountChild(id: 11, displayName: 'Child A', klasseId: 3),
  AccountChild(id: 12, displayName: 'Child B'),
];

Account parent({
  List<AccountChild> children = _kids,
  int? selected,
  ElementType type = ElementType.unknown,
}) => Account(
  id: 'p',
  school: school,
  username: 'parent',
  anonymous: false,
  displayName: 'Parent',
  elementType: type,
  elementId: 900,
  children: children,
  selectedChildId: selected,
);

void main() {
  group('personal target', () {
    test('students and teachers keep their own element', () {
      final s = account('s');
      expect(s.hasOwnTimetable, isTrue);
      expect(s.personalTarget, const TimetableTarget(ElementType.student, 7));
      expect(s.activeChild, isNull);
      expect(s.personalKlasseId, 1);
      // Even with children listed, an own timetable wins.
      final t = parent(type: ElementType.teacher);
      expect(t.personalTarget, const TimetableTarget(ElementType.teacher, 900));
    });

    test('parents get the first child by default', () {
      final p = parent();
      expect(p.hasOwnTimetable, isFalse);
      expect(p.activeChild!.id, 11);
      expect(p.personalTarget, const TimetableTarget(ElementType.student, 11));
      expect(p.personalKlasseId, 3);
    });

    test('the selected child wins; an unknown selection falls back', () {
      expect(parent(selected: 12).personalTarget!.id, 12);
      expect(parent(selected: 12).personalKlasseId, isNull);
      expect(parent(selected: 99).personalTarget!.id, 11);
    });

    test('no children and no own element -> no target', () {
      expect(parent(children: const []).personalTarget, isNull);
      expect(
        const Account(
          id: 'x',
          school: school,
          username: 'u',
          anonymous: false,
          displayName: 'x',
          elementType: ElementType.student,
        ).personalTarget,
        isNull,
        reason: 'id 0 is not a timetable',
      );
    });
  });

  group('repository', () {
    late AppDatabase db;
    late AccountRepositoryImpl repo;
    setUp(() {
      db = memoryDb();
      repo = AccountRepositoryImpl(db, MemorySecretStore());
    });
    tearDown(() => db.close());

    test('children and the selected child round-trip', () async {
      await repo.add(parent(), 's', masterData());
      var a = (await repo.watchActive().first)!;
      expect(a.children, _kids);
      expect(a.selectedChildId, isNull);

      await repo.update(a.copyWith(selectedChildId: 12));
      a = (await repo.watchActive().first)!;
      expect(a.selectedChildId, 12);
      expect(a.personalTarget!.id, 12);
    });

    test('students store no children', () async {
      await repo.add(account('s'), 's', masterData());
      final a = (await repo.watchActive().first)!;
      expect(a.children, isEmpty);
      expect(a.personalTarget!.id, 7);
    });
  });

  group('migration to v3', () {
    Future<void> check(List<String> schema, int version) async {
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            for (final s in schema) {
              raw.execute(s);
            }
            raw.execute(
              "INSERT INTO accounts (id, position, school_id, "
              "school_login_name, school_display_name, school_address, "
              "school_host, username, anonymous, display_name, element_type, "
              "element_id) VALUES ('acc1', 0, 42, 'demo-school', 'Demo', '', "
              "'demo.webuntis.com', 'max', 0, 'Max Muster', 'STUDENT', 7)",
            );
            raw.execute('PRAGMA user_version = $version');
          },
        ),
      );
      addTearDown(db.close);
      final repo = AccountRepositoryImpl(db, MemorySecretStore());
      final a = (await repo.watchAccounts().first).single;
      expect(a.children, isEmpty);
      expect(a.selectedChildId, isNull);
      expect(a.personalTarget, const TimetableTarget(ElementType.student, 7));
      await repo.update(
        a.copyWith(children: _kids, selectedChildId: 12),
      );
      final b = (await repo.watchAccounts().first).single;
      expect(b.children, _kids);
      expect(b.selectedChildId, 12);
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.single, 3);
    }

    test('v1 -> v3', () => check(v1Schema, 1));
    test('v2 -> v3', () => check([...v1Schema, ...v2Additions], 2));
  });
}

/// Tables added in v2 (as drift created them then).
const v2Additions = [
  '''CREATE TABLE "info_cache" ("account_id" TEXT NOT NULL, "key" TEXT NOT NULL, "json" TEXT NOT NULL, "fetched_at" INTEGER NOT NULL, PRIMARY KEY ("account_id", "key"))''',
  '''CREATE TABLE "absence_lookup_entries" ("account_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "id" INTEGER NOT NULL, "name" TEXT NOT NULL, PRIMARY KEY ("account_id", "kind", "id"))''',
];
