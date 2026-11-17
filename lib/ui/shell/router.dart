import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/build_channel.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../accessibility/accessibility_screen.dart';
import '../accounts/manage_accounts_screen.dart';
import '../calendar/calendar_sync_screen.dart';
import '../calendar/calendar_syncs_screen.dart';
import '../classreg/class_lead_screen.dart';
import '../classreg/class_register_overview_screen.dart';
import '../classreg/excuses_screen.dart';
import '../classreg/free_room_booking_screen.dart';
import '../classreg/substitution_requests_screen.dart';
import '../classreg/teacher_absences_screen.dart';
import '../classreg/teacher_exams_screen.dart';
import '../infocenter/info_center_screen.dart';
import '../infocenter/messages_tab.dart';
import '../login/login_form_screen.dart';
import '../login/login_screen.dart';
import '../login/id_austria_screen.dart';
import '../login/qr_scan_screen.dart';
import '../settings/timetable_settings_screen.dart';
import '../sync/sync_screen.dart';
import '../timetable/timetable_screen.dart';
import 'app_drawer.dart';
import 'debug_screen.dart';
import 'element_picker_screen.dart';
import 'whats_new.dart';

/// Routes:
///   /                      own timetable (active account)
///   /timetable/:type/:id   any element's timetable
///   /browse                pick a class / teacher / room / subject
///   /info                  info center (messages, homework, exams, …)
///   /rooms/book            teachers: book a room without a lesson
///   /info/message/:id      one inbox message
///   /login, /login/add, /login/form (extra: School?), /login/qr,
///   /login/idaustria       how to log in when the school uses ID Austria
///   /accounts              manage accounts
///   /accessibility         high contrast, day view, read aloud (no login needed)
///   /settings              timetable look (colors, text, cancelled)
///   /calendar              calendar syncs; /calendar/setup (extra:
///                          CalendarSetupArgs) adds or edits one
///   /sync                  sync of lesson notes (all platforms)
///   /whats-new             release notes of this and earlier versions
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
      // Accessibility options are reachable before the first login.
      if (!has && !inLogin && loc != '/accessibility') return '/login';
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
          drawer: const AppDrawer(onHome: false),
          target: TimetableTarget(
            ElementType.parse(s.pathParameters['type']),
            int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ),
      GoRoute(
        path: '/accessibility',
        builder: (_, _) => const AccessibilityScreen(),
      ),
      GoRoute(path: '/browse', builder: (_, _) => const ElementPickerScreen()),
      GoRoute(
        path: '/classreg',
        builder: (_, _) => const ClassRegisterOverviewScreen(),
      ),
      // Old name of the class register overview ("Open lessons").
      GoRoute(path: '/classreg/open', redirect: (_, _) => '/classreg'),
      GoRoute(path: '/exams', builder: (_, _) => const TeacherExamsScreen()),
      GoRoute(
        path: '/excuses',
        builder: (_, s) => ExcusesScreen(
          initialClassId: int.tryParse(s.uri.queryParameters['class'] ?? ''),
        ),
      ),
      GoRoute(path: '/classlead', builder: (_, _) => const ClassLeadScreen()),
      GoRoute(
        path: '/substitution-requests',
        builder: (_, _) => const SubstitutionRequestsScreen(),
      ),
      GoRoute(
        path: '/teacher-absences',
        builder: (_, _) => const TeacherAbsencesScreen(),
      ),
      GoRoute(
        path: '/rooms/book',
        builder: (_, _) => const FreeRoomBookingScreen(),
      ),
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
        path: '/login/idaustria',
        builder: (_, _) => const IdAustriaScreen(),
      ),
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const ManageAccountsScreen(),
      ),
      GoRoute(
        path: '/calendar',
        builder: (_, _) => const CalendarSyncsScreen(),
      ),
      GoRoute(
        path: '/calendar/setup',
        builder: (_, s) =>
            CalendarSyncScreen(args: s.extra! as CalendarSetupArgs),
      ),
      GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      GoRoute(path: '/whats-new', builder: (_, _) => const WhatsNewScreen()),
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
