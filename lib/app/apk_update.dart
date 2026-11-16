/// Android in-app updater: downloads the release APK from GitHub, verifies it
/// and hands it to the system installer (PackageInstaller session in
/// MainActivity.kt). Only betas and stables reach this: see [parseRelease].
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';

/// Download or verification failed; [message] is shown to the user.
class ApkUpdateException implements Exception {
  const ApkUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Downloads release APKs into `<cache>/updates/`, keeping only the newest.
class ApkDownloader {
  ApkDownloader({required this.dio, required this.directory});

  final Dio dio;

  /// Where APKs go (the app's cache dir, which the installer can read).
  final Future<Directory> Function() directory;

  Future<Directory> _dir() async {
    final d = await directory();
    await d.create(recursive: true);
    return d;
  }

  /// Deletes every downloaded APK (and partial download).
  Future<void> cleanup() async {
    try {
      final d = await directory();
      if (!await d.exists()) return;
      await for (final f in d.list()) {
        if (f is File) await f.delete();
      }
    } catch (_) {
      // Best effort: a leftover file only costs cache space.
    }
  }

  /// Downloads [apk], reporting `(received, total)`. Throws
  /// [ApkUpdateException] on failure and [DioException] (type cancel) when
  /// [cancel] fires.
  Future<File> download(
    ReleaseAsset apk, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    await cleanup();
    final dir = await _dir();
    final name = apk.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$name');
    try {
      await dio.downloadUri(
        apk.url,
        file.path,
        cancelToken: cancel,
        deleteOnError: true,
        onReceiveProgress: (r, t) => onProgress?.call(r, t > 0 ? t : apk.size),
        options: Options(
          headers: {'User-Agent': 'better-betteruntis'},
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const ApkUpdateException(
        'Download failed. Check your connection and try again.',
      );
    }
    try {
      await verifyApk(file, apk);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return file;
  }
}

/// Checks [file] against the size and (when GitHub provides one) the SHA-256
/// digest of [apk]. Throws [ApkUpdateException] on a mismatch.
Future<void> verifyApk(File file, ReleaseAsset apk) async {
  final length = await file.length();
  if (length != apk.size) {
    throw ApkUpdateException(
      'The download is incomplete ($length of ${apk.size} bytes).',
    );
  }
  final expected = apk.sha256;
  if (expected == null) return;
  final actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual != expected) {
    throw const ApkUpdateException(
      'The download is damaged (checksum mismatch).',
    );
  }
}

/// Final outcome of an installation attempt.
enum InstallStatus {
  /// Installed (rarely seen: updating ourselves restarts the app).
  success,

  /// The user cancelled the system dialog.
  aborted,

  /// Installation is not allowed yet: the user must allow this app to
  /// install unknown apps first.
  notAllowed,

  /// Any other failure (conflict, incompatible, storage, ...).
  failure,
}

class InstallResult {
  const InstallResult(this.status, [this.message]);
  final InstallStatus status;
  final String? message;
}

/// The system installer; faked in tests.
abstract class ApkInstaller {
  /// Whether this app may install packages (Android 8+: "Install unknown
  /// apps" for this app).
  Future<bool> canRequestInstalls();

  /// Opens the "Install unknown apps" settings page for this app.
  Future<void> openInstallSettings();

  /// Installs [apk]. Completes once Android reports a final status; the
  /// confirmation dialog (if any) is shown by the native side.
  Future<InstallResult> install(File apk);
}

/// [ApkInstaller] over the `better_betteruntis/updater` MethodChannel.
class MethodChannelApkInstaller implements ApkInstaller {
  const MethodChannelApkInstaller();

  static const _channel = MethodChannel('better_betteruntis/updater');

  @override
  Future<bool> canRequestInstalls() async =>
      await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<InstallResult> install(File apk) async {
    try {
      final res = await _channel.invokeMapMethod<String, Object?>('install', {
        'path': apk.path,
      });
      final message = res?['message'] as String?;
      return switch (res?['status']) {
        'success' => InstallResult(InstallStatus.success, message),
        'aborted' => InstallResult(InstallStatus.aborted, message),
        'notAllowed' => InstallResult(InstallStatus.notAllowed, message),
        _ => InstallResult(InstallStatus.failure, message),
      };
    } on PlatformException catch (e) {
      return InstallResult(InstallStatus.failure, e.message ?? e.code);
    }
  }
}

/// Whether the dialog offers "Update now" (Android app only).
final inAppUpdateSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const MethodChannelApkInstaller(),
);

final apkDownloaderProvider = Provider<ApkDownloader>(
  (ref) => ApkDownloader(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
    directory: () async =>
        Directory('${(await getTemporaryDirectory()).path}/updates'),
  ),
);
