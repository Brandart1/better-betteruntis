/// Favourite classes and teachers in "Browse timetables": starred ones are
/// shown again at the top, under "Favourites". Kept per account (element
/// ids belong to one school); with sync on they go to that account's sync
/// (lib/sync/synced_settings.dart, `favourite.<TYPE>#<id>`).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'settings.dart';

/// Element types that can be favourites.
bool canBeFavourite(ElementType type) =>
    type == ElementType.klasse || type == ElementType.teacher;

String favouriteKey(ElementType type, int id) => '${type.apiName}#$id';

/// Favourites per account id, as [favouriteKey]s.
final favouritesProvider =
    NotifierProvider<FavouritesNotifier, Map<String, Set<String>>>(
      FavouritesNotifier.new,
    );

class FavouritesNotifier extends Notifier<Map<String, Set<String>>> {
  static const storeKey = 'favourites';
  bool _changed = false;
  Future<void> _loading = Future.value();

  @override
  Map<String, Set<String>> build() {
    final store = ref.watch(settingsStoreProvider);
    final cached = store.peek(storeKey);
    if (cached != null) {
      _loading = Future.value();
      return _decode(cached);
    }
    _loading = _load(store);
    return const {};
  }

  /// Completes once the stored favourites are loaded.
  Future<void> get ready => _loading;

  static Map<String, Set<String>> _decode(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is List)
          '${e.key}': {for (final k in e.value as List) '$k'},
    };
  }

  Future<void> _load(SettingsStore store) async {
    try {
      final raw = await store.read(storeKey);
      if (!ref.mounted || _changed || raw == null) return;
      state = _decode(raw);
    } catch (_) {}
  }

  /// Applies favourites synced from another device: [changes] maps
  /// [favouriteKey]s to true (starred) or false (unstarred).
  void applyRemote(String accountId, Map<String, bool> changes) {
    if (changes.isEmpty) return;
    final mine = {...?state[accountId]};
    for (final e in changes.entries) {
      e.value ? mine.add(e.key) : mine.remove(e.key);
    }
    _commit(accountId, mine);
  }

  bool isFavourite(String accountId, ElementType type, int id) =>
      state[accountId]?.contains(favouriteKey(type, id)) ?? false;

  /// Stars or unstars [type] #[id] for [accountId].
  void toggle(String accountId, ElementType type, int id) {
    final key = favouriteKey(type, id);
    final mine = {...?state[accountId]};
    if (!mine.remove(key)) mine.add(key);
    _commit(accountId, mine);
  }

  void _commit(String accountId, Set<String> mine) {
    final next = {...state};
    if (mine.isEmpty) {
      next.remove(accountId);
    } else {
      next[accountId] = mine;
    }
    _changed = true;
    state = next;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(storeKey, {
            for (final e in next.entries) e.key: (e.value.toList()..sort()),
          })
          .catchError((_) {}),
    );
  }
}
