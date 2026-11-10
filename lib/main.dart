import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/untis_api_impl.dart';
import 'app/routing_api.dart';
import 'core/providers.dart';
import 'data/data_providers.dart';
import 'dev/fake_accounts.dart';
import 'ui/shell/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = RoutingUntisApi(
    real: UntisApiImpl(isIos: defaultTargetPlatform == TargetPlatform.iOS),
    demo: FakeUntisApi(latency: const Duration(milliseconds: 250)),
  );
  runApp(
    ProviderScope(
      overrides: [untisApiProvider.overrideWithValue(api), ...dataOverrides()],
      child: const BetterUntisApp(),
    ),
  );
}
