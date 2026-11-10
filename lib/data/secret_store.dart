/// Storage for per-account shared secrets. Secrets never touch the database.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretStore {
  Future<String?> read(String accountId);
  Future<void> write(String accountId, String secret);
  Future<void> delete(String accountId);
}

/// Keychain / Keystore backed implementation.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String accountId) => 'account_secret_$accountId';

  @override
  Future<String?> read(String accountId) => _storage.read(key: _key(accountId));

  @override
  Future<void> write(String accountId, String secret) =>
      _storage.write(key: _key(accountId), value: secret);

  @override
  Future<void> delete(String accountId) =>
      _storage.delete(key: _key(accountId));
}

/// In-memory implementation for tests and demo mode.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async =>
      values[accountId] = secret;

  @override
  Future<void> delete(String accountId) async => values.remove(accountId);
}
