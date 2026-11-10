/// Riverpod wiring. Concrete implementations are injected in main.dart via
/// ProviderScope overrides; tests and the demo mode override with fakes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interfaces.dart';
import 'models.dart';

final untisApiProvider = Provider<UntisApi>(
  (ref) => throw UnimplementedError('override untisApiProvider'),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => throw UnimplementedError('override accountRepositoryProvider'),
);

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => throw UnimplementedError('override timetableRepositoryProvider'),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAccounts(),
);

final activeAccountProvider = StreamProvider<Account?>(
  (ref) => ref.watch(accountRepositoryProvider).watchActive(),
);

/// Name resolver for the active account.
final nameResolverProvider = StreamProvider<NameResolver>((ref) {
  final account = ref.watch(activeAccountProvider).value;
  if (account == null) return const Stream.empty();
  return ref.watch(timetableRepositoryProvider).watchNames(account);
});
