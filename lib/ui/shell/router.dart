import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/build_channel.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../accounts/manage_accounts_screen.dart';
import '../infocenter/info_center_screen.dart';
import '../infocenter/messages_tab.dart';
import '../login/login_form_screen.dart';
import '../login/login_screen.dart';
import '../login/qr_scan_screen.dart';
import '../settings/timetable_settings_screen.dart';
import '../timetable/timetable_screen.dart';
import 'app_drawer.dart';
import 'debug_screen.dart';
import 'element_picker_screen.dart';

/// Routes:
///   /                      own timetable (active account)
///   /timetable/:type/:id   any element's timetable
///   /browse                pick a class / teacher / room / subject
///   /info                  info center (messages, homework, exams, …)
///   /info/message/:id      one inbox message
///   /login, /login/add, /login/form (extra: School?), /login/qr
///   /accounts              manage accounts
///   /settings              timetable look (colors, text, cancelled)
///   /debug                 raw API responses
final routerProvider = Provider<GoRouter>((ref) {
  // null = still loading, otherwise whether any account exists.
  final hasAccounts = ValueNotifier<bool?>(null);
  ref.listen(
    accountsProvider,
    (_, next) => hasAccounts.value = next.value?.isNotEmpty,
    fireImmediately: true,
  );
  ref.onDispose(hasAccounts.dispose);

  final router = GoRouter(
    refreshListenable: hasAccounts,
    redirect: (context, state) {
      final has = hasAccounts.value;
      if (has == null) return null;
      final loc = state.matchedLocation;
      final inLogin = loc.startsWith('/login');
      if (!has && !inLogin) return '/login';
      if (has && loc == '/login') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const TimetableScreen(drawer: AppDrawer()),
      ),
      GoRoute(
        path: '/timetable/:type/:id',
        builder: (_, s) => TimetableScreen(
          target: TimetableTarget(
            ElementType.parse(s.pathParameters['type']),
            int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ),
      GoRoute(path: '/browse', builder: (_, _) => const ElementPickerScreen()),
      GoRoute(
        path: '/info',
        builder: (_, _) => const InfoCenterScreen(),
        routes: [
          GoRoute(
            path: 'message/:id',
            builder: (_, s) => MessageDetailScreen(
              messageId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
        ],
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/login/add',
        builder: (_, _) => const LoginScreen(addingAccount: true),
      ),
      GoRoute(
        path: '/login/form',
        builder: (_, s) => LoginFormScreen(school: s.extra as School?),
      ),
      GoRoute(path: '/login/qr', builder: (_, _) => const QrScanScreen()),
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const ManageAccountsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const TimetableSettingsScreen(),
      ),
      // Debug screen (raw API data) only in dev/alpha builds.
      if (debugToolsEnabled)
        GoRoute(path: '/debug', builder: (_, _) => const DebugScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
