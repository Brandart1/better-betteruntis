import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/ui/accounts/account_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../login/harness.dart';

Harness twoSchools() => Harness(
  accounts: [
    testAccount('a1', 'Max Mustermann'),
    testAccount('a2', 'Mia Mustermann', profileName: 'Little sister'),
    testAccount('a3', 'Tom Teacher', school: FakeUntisApi.schools[1]),
  ],
  activeId: 'a1',
);

const home = Scaffold(body: SafeArea(child: AccountSwitcher()));

void main() {
  testWidgets('switcher shows active account and opens grouped sheet', (
    tester,
  ) async {
    final h = twoSchools();
    await h.pump(tester, initial: '/', home: home);
    expect(find.text('Max Mustermann'), findsOneWidget);
    expect(find.text('Goethe-Gymnasium'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('accountSwitcher')));
    await tester.pumpAndSettle();
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Little sister'), findsOneWidget);
    expect(find.text('Humboldt-Gymnasium Köln'), findsOneWidget); // header
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);

    await tester.tap(find.text('Tom Teacher'));
    await tester.pumpAndSettle();
    expect(h.repo.active?.id, 'a3');
    expect(find.text('Accounts'), findsNothing); // sheet closed
    expect(find.text('Tom Teacher'), findsOneWidget); // switcher updated
  });

  testWidgets('delete asks for confirmation', (tester) async {
    final h = twoSchools();
    await h.pump(tester, initial: '/', home: home);
    await tester.tap(find.byKey(const ValueKey('accountSwitcher')));
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('account-a2'));
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Account options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.repo.accounts, hasLength(3));

    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Account options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(h.repo.accounts.map((a) => a.id), ['a1', 'a3']);
    expect(find.text('Little sister'), findsNothing);
  });

  testWidgets('rename sets and clears the profile name', (tester) async {
    final h = twoSchools();
    await h.pump(tester, initial: '/accounts');
    final tile = find.byKey(const ValueKey('account-a1'));
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Account options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('renameField')), 'Me');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.repo.accounts.first.profileName, 'Me');
    expect(find.text('Me'), findsOneWidget);

    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Account options')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('renameField')), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.repo.accounts.first.profileName, isNull);
  });

  testWidgets('deleting the last account returns to login', (tester) async {
    final h = Harness(accounts: [testAccount('a1', 'Max Mustermann')]);
    await h.pump(tester, initial: '/accounts');
    await tester.tap(find.byTooltip('Account options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(h.repo.accounts, isEmpty);
    expect(find.text('BetterBetterUntis'), findsOneWidget);
  });
}
