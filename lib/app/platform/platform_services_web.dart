import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

import '../../core/settings.dart';
import '../../data/secret_store.dart';
import '../web_proxy.dart';

const _settingsKey = 'bbu.settings';
const _secretPrefix = 'bbu.secret.';

Future<SettingsStore> openSettingsStore() async => LocalStorageSettingsStore();

SecretStore createSecretStore() => LocalStorageSecretStore();

List<Interceptor> platformInterceptors() => [WebProxyInterceptor(Uri.base)];

const bool supportsDirectDownload = true;

/// Saves [bytes] via a temporary blob link (the browser's download prompt).
Future<void> downloadFile(String name, String mimeType, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  // Revoke later; some browsers start the download asynchronously.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
}

/// Settings as one JSON object in localStorage (per browser profile).
class LocalStorageSettingsStore implements SettingsStore {
  LocalStorageSettingsStore() {
    try {
      final raw = web.window.localStorage.getItem(_settingsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) {
        _values.addAll({for (final e in decoded.entries) '${e.key}': e.value});
      }
    } catch (_) {
      // Storage blocked or corrupt: start empty.
    }
  }

  final _values = <String, Object?>{};

  @override
  Object? peek(String key) => _values[key];

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
    try {
      web.window.localStorage.setItem(_settingsKey, jsonEncode(_values));
    } catch (_) {
      // Quota or private mode: keep in memory only.
    }
  }
}

/// Account secrets in localStorage. Browsers have no keychain; anything a
/// page can encrypt it can also decrypt, so this is as safe as the browser
/// profile (and the HTTPS origin) it lives in.
class LocalStorageSecretStore implements SecretStore {
  @override
  Future<String?> read(String accountId) async =>
      web.window.localStorage.getItem('$_secretPrefix$accountId');

  @override
  Future<void> write(String accountId, String secret) async =>
      web.window.localStorage.setItem('$_secretPrefix$accountId', secret);

  @override
  Future<void> delete(String accountId) async =>
      web.window.localStorage.removeItem('$_secretPrefix$accountId');
}
