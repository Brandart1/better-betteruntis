import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/dev/fake_accounts.dart';
import 'package:better_betteruntis/ui/accounts/manage_accounts_screen.dart';
import 'package:better_betteruntis/ui/login/id_austria_screen.dart';
import 'package:better_betteruntis/ui/login/login_form_screen.dart';
import 'package:better_betteruntis/ui/login/login_screen.dart';
import 'package:better_betteruntis/ui/login/qr_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Test app wiring the login/accounts routes against the fakes.
class Harness {
  Harness({List<Account> accounts = const [], String? activeId})
    : api = FakeUntisApi(latency: Duration.zero),
      repo = InMemoryAccountRepository(initial: accounts, activeId: activeId);

  final FakeUntisApi api;
  final InMemoryAccountRepository repo;
  late final GoRouter router;

  Future<void> pump(
    WidgetTester tester, {
    String initial = '/login',
    Widget? home,
    Widget Function(ValueChanged<String> onCode)? qrScanner,
    Size size = const Size(600, 1200),
    List overrides = const [],
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              home ?? const Scaffold(body: Center(child: Text('HOME'))),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const LoginScreen(),
          routes: [
            GoRoute(
              path: 'add',
              builder: (_, _) => const LoginScreen(addingAccount: true),
            ),
            GoRoute(
              path: 'form',
              builder: (_, s) => LoginFormScreen(school: s.extra as School?),
            ),
            GoRoute(
              path: 'qr',
              builder: (_, _) => QrScanScreen(scanner: qrScanner),
            ),
            GoRoute(
              path: 'idaustria',
              builder: (_, _) => const IdAustriaScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/accounts',
          builder: (_, _) => const ManageAccountsScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          untisApiProvider.overrideWithValue(api),
          accountRepositoryProvider.overrideWithValue(repo),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Account testAccount(
  String id,
  String name, {
  School? school,
  String? username,
  String? profileName,
}) => Account(
  id: id,
  school: school ?? FakeUntisApi.schools.first,
  username: username ?? name.toLowerCase().replaceAll(' ', '.'),
  anonymous: false,
  displayName: name,
  profileName: profileName,
);
