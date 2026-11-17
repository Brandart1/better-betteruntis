import 'package:better_betteruntis/core/models.dart';
import 'package:better_betteruntis/core/notifications.dart';
import 'package:better_betteruntis/core/providers.dart';
import 'package:better_betteruntis/core/settings.dart';
import 'package:better_betteruntis/ui/common/large_text.dart';
import 'package:better_betteruntis/ui/settings/notification_settings_screen.dart';
import 'package:better_betteruntis/ui/shell/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Notifier implements LocalNotifier {
  _Notifier(this.grant);
  final bool grant;
  int asked = 0;

  @override
  Future<bool> requestPermission() async {
    asked++;
    return grant;
  }

  @override
  Future<void> show(AppNotification n) async {}

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> takeLaunchPayload() async => null;
}

class _Service implements NotificationService {
  int checks = 0;

  @override
  Future<List<AppNotification>> check({
    Duration minInterval = Duration.zero,
  }) async {
    checks++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _account = Account(
  id: 'acc',
  school: School(
    schoolId: 1,
    loginName: 's',
    displayName: 'School',
    address: '',
    host: 'x.webuntis.com',
  ),
  username: 'u',
  anonymous: false,
  displayName: 'Max',
  elementId: 7,
);

void main() {
  Future<(ProviderContainer, _Service)> pump(
    WidgetTester tester,
    _Notifier notifier,
  ) async {
    final service = _Service();
    final store = MemorySettingsStore();
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        localNotifierProvider.overrideWithValue(notifier),
        notificationServiceProvider.overrideWithValue(service),
        activeAccountProvider.overrideWith((ref) => Stream.value(_account)),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (c, service);
  }

  bool enabled(ProviderContainer c) =>
      c.read(notificationPrefsProvider).of('acc').enabled;

  testWidgets('turning on asks for permission, then checks quietly', (
    tester,
  ) async {
    final notifier = _Notifier(true);
    final (c, service) = await pump(tester, notifier);
    expect(enabled(c), isFalse);
    // Kinds can't be changed while off.
    expect(
      tester
          .widget<AdaptiveSwitchTile>(
            find.byKey(const ValueKey('notifications-timetable')),
          )
          .onChanged,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
    await tester.pumpAndSettle();
    expect(notifier.asked, 1);
    expect(enabled(c), isTrue);
    expect(service.checks, 1);

    await tester.tap(find.byKey(const ValueKey('notifications-messages')));
    await tester.pumpAndSettle();
    expect(c.read(notificationPrefsProvider).of('acc').messages, isFalse);
    expect(c.read(notificationPrefsProvider).of('acc').timetable, isTrue);

    // Off again: no permission prompt.
    await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
    await tester.pumpAndSettle();
    expect(notifier.asked, 1);
    expect(enabled(c), isFalse);
  });

  testWidgets('denied permission keeps notifications off', (tester) async {
    final notifier = _Notifier(false);
    final (c, service) = await pump(tester, notifier);
    await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
    await tester.pumpAndSettle();
    expect(enabled(c), isFalse);
    expect(service.checks, 0);
    expect(find.textContaining('not allowed'), findsOneWidget);
  });

  testWidgets('days ahead can be changed', (tester) async {
    final (c, _) = await pump(tester, _Notifier(true));
    await tester.tap(find.byKey(const ValueKey('notifications-enabled')));
    await tester.pumpAndSettle();
    expect(find.text('Today and the next 2 school days'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    expect(c.read(notificationPrefsProvider).of('acc').daysAhead, 4);
  });
}
