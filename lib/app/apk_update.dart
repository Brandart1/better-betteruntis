/// Android in-app updater: downloads the release APK from GitHub, verifies
/// its SHA-256 digest and hands it to the system installer, all done by the
/// `ota_update` plugin. Betas and stables, plus newer alphas for alpha builds: see
/// [parseRelease] and [pickAlphaUpdate].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';

/// Where an update is in its life; see [ApkUpdateEvent].
enum ApkUpdateStage {
  /// Downloading; [ApkUpdateEvent.progress] is 0..1 or null when unknown.
  downloading,

  /// Downloaded and verified; the system installer is (being) opened. The
  /// stream ends here: the app is replaced if the user confirms.
  installing,

  /// The system refused because this app may not install unknown apps (the
  /// user must allow it in the settings first).
  needsPermission,

  /// Download, verification or installation failed; [ApkUpdateEvent.message]
  /// is shown to the user.
  failed,

  /// Cancelled by [ApkUpdater.cancel].
  canceled,

  /// Installed (rarely seen: updating ourselves restarts the app).
  done,
}

class ApkUpdateEvent {
  const ApkUpdateEvent(this.stage, {this.progress, this.message});
  final ApkUpdateStage stage;
  final double? progress;
  final String? message;
}

/// Downloads and installs a release APK; faked in tests.
abstract class ApkUpdater {
  /// Starts the update. The stream emits [ApkUpdateEvent]s and ends after
  /// the last one (installing, failed, canceled or done).
  Stream<ApkUpdateEvent> start(ReleaseAsset apk);

  /// Stops a running download.
  Future<void> cancel();

  /// Deletes APKs left over from earlier updates.
  Future<void> cleanup();
}

/// Maps an `ota_update` event onto the app's [ApkUpdateEvent].
ApkUpdateEvent mapOtaEvent(OtaEvent e) {
  final v = e.value;
  switch (e.status) {
    case OtaStatus.DOWNLOADING:
      final percent = int.tryParse(v ?? '');
      return ApkUpdateEvent(
        ApkUpdateStage.downloading,
        progress: percent == null ? null : (percent / 100).clamp(0.0, 1.0),
      );
    case OtaStatus.INSTALLING:
      return const ApkUpdateEvent(ApkUpdateStage.installing);
    case OtaStatus.INSTALLATION_DONE:
      return const ApkUpdateEvent(ApkUpdateStage.done);
    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
      return const ApkUpdateEvent(ApkUpdateStage.needsPermission);
    case OtaStatus.CANCELED:
      return const ApkUpdateEvent(ApkUpdateStage.canceled);
    case OtaStatus.CHECKSUM_ERROR:
      return const ApkUpdateEvent(
        ApkUpdateStage.failed,
        message: 'The download is damaged (checksum mismatch).',
      );
    case OtaStatus.DOWNLOAD_ERROR:
      return const ApkUpdateEvent(
        ApkUpdateStage.failed,
        message: 'Download failed. Check your connection and try again.',
      );
    case OtaStatus.ALREADY_RUNNING_ERROR:
      return const ApkUpdateEvent(
        ApkUpdateStage.failed,
        message: 'An update is already running.',
      );
    case OtaStatus.INSTALLATION_ERROR:
      return ApkUpdateEvent(
        ApkUpdateStage.failed,
        message: 'Installation failed${v == null ? '' : ': $v'}.',
      );
    case OtaStatus.INTERNAL_ERROR:
      return ApkUpdateEvent(
        ApkUpdateStage.failed,
        message: 'Update failed${v == null ? '' : ': $v'}.',
      );
  }
}

/// Starts an `ota_update` run; replaceable in tests.
typedef OtaRunner = Stream<OtaEvent> Function({
  required String url,
  required String filename,
  required String? sha256,
  required Map<String, String> headers,
});

Stream<OtaEvent> _runOta({
  required String url,
  required String filename,
  required String? sha256,
  required Map<String, String> headers,
}) => OtaUpdate().execute(
  url,
  destinationFilename: filename,
  sha256checksum: sha256,
  headers: headers,
);

Future<void> _defaultCancel() => OtaUpdate().cancel();

/// The plugin downloads to `<files>/ota_update/`; older app versions used
/// `<cache>/updates/`.
Future<List<Directory>> _defaultLeftovers() async => [
  Directory('${(await getApplicationSupportDirectory()).path}/ota_update'),
  Directory('${(await getTemporaryDirectory()).path}/updates'),
];

/// [ApkUpdater] over the `ota_update` plugin (Android only).
class OtaApkUpdater implements ApkUpdater {
  const OtaApkUpdater({
    this.run = _runOta,
    this.cancelOta = _defaultCancel,
    this.leftoverDirectories = _defaultLeftovers,
  });

  final OtaRunner run;
  final Future<void> Function() cancelOta;
  final Future<List<Directory>> Function() leftoverDirectories;

  @override
  Stream<ApkUpdateEvent> start(ReleaseAsset apk) {
    // The plugin refuses a '/' in the name.
    final name = apk.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // Without a digest a failed download (the plugin still writes an HTTP
    // error body) could be handed to the installer: never install unchecked.
    if (apk.sha256 == null) {
      return Stream.value(
        const ApkUpdateEvent(
          ApkUpdateStage.failed,
          message:
              'This release has no checksum, so it can\'t be installed '
              'safely from the app. Download it from GitHub instead.',
        ),
      );
    }
    final Stream<OtaEvent> events;
    try {
      events = run(
        url: apk.url.toString(),
        filename: name,
        // The plugin verifies the digest after the download and does not
        // install on a mismatch.
        sha256: apk.sha256,
        headers: const {'User-Agent': 'better-betteruntis'},
      );
    } catch (e) {
      return Stream.value(
        ApkUpdateEvent(ApkUpdateStage.failed, message: 'Update failed: $e.'),
      );
    }
    return events
        .map(mapOtaEvent)
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (e, st, sink) => sink.add(
              ApkUpdateEvent(
                ApkUpdateStage.failed,
                message: 'Update failed: $e.',
              ),
            ),
          ),
        );
  }

  @override
  Future<void> cancel() async {
    try {
      await cancelOta();
    } catch (_) {
      // Nothing running.
    }
  }

  @override
  Future<void> cleanup() async {
    try {
      for (final d in await leftoverDirectories()) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    } catch (_) {
      // Best effort: a leftover file only costs storage.
    }
  }
}

/// Whether the dialog offers "Update now" (Android app only).
final inAppUpdateSupportedProvider = Provider<bool>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
);

final apkUpdaterProvider = Provider<ApkUpdater>((ref) => OtaApkUpdater());
