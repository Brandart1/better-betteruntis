import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/untis_api_impl.dart';
import 'app/settings_store.dart';
import 'app/routing_api.dart';
import 'core/providers.dart';
import 'core/settings.dart';
import 'data/data_providers.dart';
import 'dev/fake_accounts.dart';
import 'ui/shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load settings before the first frame so custom colors don't flash.
  final settings = await FileSettingsStore.open();
  final api = RoutingUntisApi(
    real: UntisApiImpl(isIos: defaultTargetPlatform == TargetPlatform.iOS),
    demo: FakeUntisApi(latency: const Duration(milliseconds: 250)),
  );
  runApp(
    ProviderScope(
      overrides: [
        untisApiProvider.overrideWithValue(api),
        settingsStoreProvider.overrideWithValue(settings),
        ...dataOverrides(),
      ],
      child: const BetterUntisApp(),
    ),
  );
}
