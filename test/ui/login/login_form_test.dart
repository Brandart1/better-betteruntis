import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

final school = FakeUntisApi.schools.first;

Future<Harness> openForm(WidgetTester tester, {Harness? harness}) async {
  final h = harness ?? Harness();
  await h.pump(tester);
  h.router.push('/login/form', extra: school);
  await tester.pumpAndSettle();
  return h;
}

Future<void> fillAndSubmit(
  WidgetTester tester,
  String user,
  String pass, {
  String? profile,
}) async {
  await tester.enterText(find.byKey(const ValueKey('usernameField')), user);
  await tester.enterText(find.byKey(const ValueKey('passwordField')), pass);
  if (profile != null) {
    await tester.enterText(find.byKey(const ValueKey('profileField')), profile);
  }
  await tester.tap(find.byKey(const ValueKey('loginButton')));
  await pumpFrames(tester);
}

/// Like pumpAndSettle, but tolerates the button's spinner that keeps
/// animating while a dialog (2FA, duplicate) waits for the user.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('wrong password shows a friendly message', (tester) async {
    final h = await openForm(tester);
    await fillAndSubmit(tester, 'max', 'wrong');
    expect(
      find.textContaining("username and password don't match"),
      findsOneWidget,
    );
    expect(h.repo.accounts, isEmpty);
  });

  testWidgets('wrong clock maps to a friendly message', (tester) async {
    await openForm(tester);
    await fillAndSubmit(tester, 'clock', 'pw');
    expect(find.textContaining('Your device clock seems off'), findsOneWidget);
  });

  testWidgets('validates empty fields', (tester) async {
    final h = await openForm(tester);
    await tester.tap(find.byKey(const ValueKey('loginButton')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(h.api.loginCalls, isEmpty);
  });

  testWidgets('successful login adds account and goes home', (tester) async {
    final h = await openForm(tester);
    await fillAndSubmit(tester, 'max.mustermann', 'secret', profile: 'Me');
    expect(find.text('HOME'), findsOneWidget);
    final a = h.repo.accounts.single;
    expect(a.username, 'max.mustermann');
    expect(a.displayName, 'Max Mustermann');
    expect(a.profileName, 'Me');
    expect(a.school.loginName, school.loginName);
    expect(a.elementType, ElementType.student);
    expect(a.elementId, 1001);
    expect(a.masterDataTimestamp, FakeUntisApi.demoMasterData.timestamp);
    expect(h.repo.secrets[a.id], 'FAKESECRETMAX.MUSTERMANN');
    expect(h.repo.active?.id, a.id);
  });

  testWidgets('2FA dialog flow retries with the token', (tester) async {
    final h = await openForm(tester);
    await fillAndSubmit(tester, '2fa', 'secret');
    expect(find.text('Two-factor code'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('twoFactorField')),
      '000000',
    );
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await pumpFrames(tester);
    expect(find.textContaining("That code didn't work"), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('twoFactorField')),
      FakeUntisApi.twoFactorCode,
    );
    await tester.pump();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(h.api.loginCalls.map((c) => c.token), [
      null,
      '000000',
      FakeUntisApi.twoFactorCode,
    ]);
    expect(h.repo.accounts.single.username, '2fa');
  });

  testWidgets('cancelling 2FA keeps the form', (tester) async {
    final h = await openForm(tester);
    await fillAndSubmit(tester, '2fa', 'secret');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loginButton')), findsOneWidget);
    expect(h.repo.accounts, isEmpty);
  });

  testWidgets('duplicate account warns instead of adding', (tester) async {
    final h = Harness(
      accounts: [testAccount('a1', 'Max Mustermann', username: 'max')],
    );
    await openForm(tester, harness: h);
    await fillAndSubmit(tester, 'MAX', 'secret');
    expect(find.text('Already added'), findsOneWidget);
    expect(h.api.loginCalls, isEmpty);
    await tester.tap(find.text('Switch to it'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(h.repo.accounts, hasLength(1));
  });

  testWidgets('anonymous login hides credentials', (tester) async {
    final h = await openForm(tester);
    await tester.tap(find.byKey(const ValueKey('anonymousSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loginButton')));
    await tester.pumpAndSettle();
    expect(h.api.loginCalls.single.anonymous, isTrue);
    expect(h.repo.accounts.single.anonymous, isTrue);
  });

  testWidgets('manual entry resolves the school', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('schoolField')),
      'humboldt-koeln',
    );
    await fillAndSubmit(tester, 'lea', 'pw');
    expect(find.text('HOME'), findsOneWidget);
    expect(
      h.repo.accounts.single.school.displayName,
      'Humboldt-Gymnasium Köln',
    );
  });

  testWidgets('manual entry with unknown school shows message', (tester) async {
    final h = Harness();
    await h.pump(tester);
    h.router.push('/login/form');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('schoolField')),
      'nope-xyz',
    );
    await fillAndSubmit(tester, 'lea', 'pw');
    expect(find.textContaining("couldn't find a school"), findsOneWidget);
  });
}
