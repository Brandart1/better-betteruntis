import 'dart:async';
import 'dart:io';

import 'package:better_betteruntis/app/apk_update.dart';
import 'package:better_betteruntis/app/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ota_update/ota_update.dart';

void main() {
  final hex = 'a' * 64;
  final asset = ReleaseAsset(
    name: 'better-betteruntis-v0.5.1-beta.apk',
    url: Uri.parse('https://example.com/releases/download/v/a.apk'),
    size: 100,
    sha256: hex,
  );

  group('mapOtaEvent', () {
    ApkUpdateEvent map(OtaStatus s, [String? v]) => mapOtaEvent(OtaEvent(s, v));

    test('progress is a fraction', () {
      final e = map(OtaStatus.DOWNLOADING, '40');
      expect(e.stage, ApkUpdateStage.downloading);
      expect(e.progress, 0.4);
      expect(map(OtaStatus.DOWNLOADING, '250').progress, 1.0);
      expect(map(OtaStatus.DOWNLOADING, 'x').progress, isNull);
      expect(map(OtaStatus.DOWNLOADING).progress, isNull);
    });

    test('installing and done', () {
      expect(map(OtaStatus.INSTALLING).stage, ApkUpdateStage.installing);
      expect(map(OtaStatus.INSTALLATION_DONE).stage, ApkUpdateStage.done);
    });

    test('missing permission: needsPermission', () {
      expect(
        map(OtaStatus.PERMISSION_NOT_GRANTED_ERROR).stage,
        ApkUpdateStage.needsPermission,
      );
    });

    test('checksum mismatch: damaged-download error', () {
      final e = map(OtaStatus.CHECKSUM_ERROR, 'Checksum verification failed');
      expect(e.stage, ApkUpdateStage.failed);
      expect(e.message, contains('checksum'));
    });

    test('other errors carry a message', () {
      expect(
        map(OtaStatus.DOWNLOAD_ERROR, 'boom').message,
        contains('connection'),
      );
      expect(
        map(OtaStatus.INSTALLATION_ERROR, 'conflict').message,
        'Installation failed: conflict.',
      );
      expect(map(OtaStatus.INTERNAL_ERROR, 'x').message, 'Update failed: x.');
      expect(map(OtaStatus.ALREADY_RUNNING_ERROR).stage, ApkUpdateStage.failed);
    });

    test('cancel', () {
      expect(map(OtaStatus.CANCELED).stage, ApkUpdateStage.canceled);
    });
  });

  group('OtaApkUpdater', () {
    late Map<String, Object?> args;
    late StreamController<OtaEvent> ota;
    late int cancels;
    late OtaApkUpdater updater;

    setUp(() {
      cancels = 0;
      ota = StreamController<OtaEvent>();
      updater = OtaApkUpdater(
        run:
            ({
              required url,
              required filename,
              required sha256,
              required headers,
            }) {
              args = {
                'url': url,
                'filename': filename,
                'sha256': sha256,
                'headers': headers,
              };
              return ota.stream;
            },
        cancelOta: () async => cancels++,
      );
    });

    test('passes URL, safe filename and digest; maps the whole run', () async {
      final events = <ApkUpdateEvent>[];
      final done = updater.start(asset).forEach(events.add);
      ota
        ..add(OtaEvent(OtaStatus.DOWNLOADING, '10'))
        ..add(OtaEvent(OtaStatus.DOWNLOADING, '100'))
        ..add(OtaEvent(OtaStatus.INSTALLING, 'Installation started'));
      await ota.close();
      await done;
      expect(args['url'], asset.url.toString());
      expect(args['filename'], 'better-betteruntis-v0.5.1-beta.apk');
      expect(args['sha256'], hex);
      expect((args['headers'] as Map)['User-Agent'], isNotNull);
      expect(events.map((e) => e.stage), [
        ApkUpdateStage.downloading,
        ApkUpdateStage.downloading,
        ApkUpdateStage.installing,
      ]);
      expect(events.first.progress, 0.1);
    });

    test('without a digest none is passed; odd names are sanitised', () async {
      final odd = ReleaseAsset(name: 'a/b c.apk', url: asset.url, size: 1);
      final sub = updater.start(odd).listen((_) {});
      expect(args['sha256'], isNull);
      expect(args['filename'], 'a_b_c.apk');
      await sub.cancel();
    });

    test('checksum error from the plugin ends in a failed event', () async {
      final events = <ApkUpdateEvent>[];
      final done = updater.start(asset).forEach(events.add);
      ota.add(
        OtaEvent(OtaStatus.CHECKSUM_ERROR, 'Checksum verification failed'),
      );
      await ota.close();
      await done;
      expect(events.single.stage, ApkUpdateStage.failed);
      expect(events.single.message, contains('checksum'));
    });

    test('stream errors and thrown starts become failed events', () async {
      final events = <ApkUpdateEvent>[];
      final done = updater.start(asset).forEach(events.add);
      ota.addError(StateError('x'));
      await ota.close();
      await done;
      expect(events.single.stage, ApkUpdateStage.failed);

      final throwing = OtaApkUpdater(
        run: ({
          required url,
          required filename,
          required sha256,
          required headers,
        }) => throw OtaUpdateException('bad'),
      );
      expect((await throwing.start(asset).single).stage, ApkUpdateStage.failed);
    });

    test('cancel calls the plugin, and swallows its errors', () async {
      await updater.cancel();
      expect(cancels, 1);
      final bad = OtaApkUpdater(cancelOta: () async => throw StateError('x'));
      await bad.cancel();
    });

    test('cleanup deletes leftover directories', () async {
      final tmp = await Directory.systemTemp.createTemp('apk_update_test');
      addTearDown(() => tmp.delete(recursive: true));
      final dir = Directory('${tmp.path}/ota_update');
      await File('${dir.path}/old.apk').create(recursive: true);
      await OtaApkUpdater(
        leftoverDirectories: () async => [dir, Directory('${tmp.path}/none')],
      ).cleanup();
      expect(await dir.exists(), isFalse);
    });
  });
}
