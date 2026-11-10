import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/settings.dart';
import '../../data/secret_store.dart';
import '../settings_store.dart';

Future<SettingsStore> openSettingsStore() => FileSettingsStore.open();

SecretStore createSecretStore() => SecureSecretStore();

/// No request rewriting on native platforms.
List<Interceptor> platformInterceptors() => const [];

/// Only web builds download files directly; native builds use the share sheet.
const bool supportsDirectDownload = false;

Future<void> downloadFile(String name, String mimeType, Uint8List bytes) =>
    throw UnsupportedError('downloadFile is web-only');
