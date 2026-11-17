import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/untis_api_impl.dart';
import 'app/notifications/background_check.dart';
import 'app/notifications/local_notifiers.dart';
import 'app/platform/platform_services.dart';
import 'app/routing_api.dart';
import 'core/notifications.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'data/data_providers.dart';
import 'dev/fake_accounts.dart';
import 'sync/sync_auto_trigger.dart';
import 'sync/sync_client.dart' show kSyncDisabled;
import 'sync/sync_controller.dart';
import 'sync/sync_engine.dart';
import 'ui/export/export_service.dart';
import 'ui/shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load settings before the first frame so custom colors don't flash.
  final settings = await openSettingsStore();
  final api = RoutingUntisApi(
    real: UntisApiImpl(
      isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
      interceptors: platformInterceptors(),
    ),
    demo: FakeUntisApi(latency: const Duration(milliseconds: 250)),
  );
  runApp(
    ProviderScope(
      overrides: [
        untisApiProvider.overrideWithValue(api),
        settingsStoreProvider.overrideWithValue(settings),
        ...dataOverrides(secrets: createSecretStore()),
        localNotifierProvider.overrideWithValue(createPlatformNotifier()),
        notificationStateStoreProvider.overrideWithValue(
          createNotificationStateStore(),
        ),
        backgroundSchedulerProvider.overrideWithValue(scheduleBackgroundChecks),
        backgroundChecksSupportedProvider.overrideWithValue(
          backgroundChecksSupported,
        ),
        // `--dart-define=BBU_NO_SYNC=true` (teacher web alpha): no sync at
        // all, the Sync screen says it isn't available in this build.
        if (!kSyncDisabled) syncControllerProvider.overrideWith(SyncEngine.new),
        if (supportsDirectDownload) ...[
          exportDirectoryProvider.overrideWithValue(() async => null),
          exportShareProvider.overrideWithValue(
            (file, {origin, subject}) =>
                downloadFile(file.name, file.mimeType, file.bytes),
          ),
        ],
      ],
      child: const SyncAutoTrigger(child: BetterUntisApp()),
    ),
  );
}
