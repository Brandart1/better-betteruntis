import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_betteruntis/app/apk_update.dart';
import 'package:better_betteruntis/app/app_update.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves [body] for every request; records the requested URLs.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.status = 200});
  final List<int> body;
  final int status;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return ResponseBody.fromBytes(
      body,
      status,
      headers: {
        Headers.contentLengthHeader: ['${body.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;
  final bytes = utf8.encode('pretend this is an APK');
  final hex = sha256.convert(bytes).toString();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('apk_update_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ReleaseAsset asset({int? size, String? digest}) => ReleaseAsset(
    name: 'better-betteruntis-v0.5.1-beta.apk',
    url: Uri.parse('https://github.com/x/y/releases/download/v/a.apk'),
    size: size ?? bytes.length,
    sha256: digest,
  );

  ApkDownloader downloader(_FakeAdapter adapter) => ApkDownloader(
    dio: Dio()..httpClientAdapter = adapter,
    directory: () async => Directory('${tmp.path}/updates'),
  );

  test('downloads, verifies the digest and removes older APKs', () async {
    final old = File('${tmp.path}/updates/better-betteruntis-v0.5.0.apk');
    await old.create(recursive: true);
    final adapter = _FakeAdapter(bytes);
    final progress = <int>[];
    final file = await downloader(adapter)
        .download(asset(digest: hex), onProgress: (r, t) => progress.add(r));
    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith('better-betteruntis-v0.5.1-beta.apk'));
    expect(await old.exists(), isFalse);
    expect(progress.last, bytes.length);
    expect(adapter.requested.single.host, 'github.com');
  });

  test('without a digest only the size is checked', () async {
    final file = await downloader(_FakeAdapter(bytes)).download(asset());
    expect(await file.exists(), isTrue);
  });

  test('digest mismatch: error and the file is deleted', () async {
    final wrong = sha256.convert(utf8.encode('other')).toString();
    await expectLater(
      downloader(_FakeAdapter(bytes)).download(asset(digest: wrong)),
      throwsA(
        isA<ApkUpdateException>().having(
          (e) => e.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test('size mismatch: error', () async {
    await expectLater(
      downloader(_FakeAdapter(bytes)).download(asset(size: 999)),
      throwsA(isA<ApkUpdateException>()),
    );
    expect(Directory('${tmp.path}/updates').listSync(), isEmpty);
  });

  test('HTTP error: ApkUpdateException', () async {
    await expectLater(
      downloader(_FakeAdapter(bytes, status: 404)).download(asset()),
      throwsA(isA<ApkUpdateException>()),
    );
  });

  test('cleanup removes all downloaded files', () async {
    final f = File('${tmp.path}/updates/x.apk');
    await f.create(recursive: true);
    await downloader(_FakeAdapter(bytes)).cleanup();
    expect(await f.exists(), isFalse);
  });
}
