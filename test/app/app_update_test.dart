import 'package:better_betteruntis/app/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseVersion accepts tags, pubspec versions and plain versions', () {
    expect(parseVersion('v0.4.5-beta'), [0, 4, 5]);
    expect(parseVersion('0.4.5+20'), [0, 4, 5]);
    expect(parseVersion('1.10.0'), [1, 10, 0]);
    expect(parseVersion('v0.1.0-alpha.1'), [0, 1, 0]);
    expect(parseVersion('latest'), isNull);
    expect(parseVersion('0.4'), isNull);
  });

  test('isNewerVersion compares X.Y.Z numerically and ignores suffixes', () {
    expect(isNewerVersion('v0.4.5-beta', '0.4.4'), isTrue);
    expect(isNewerVersion('v0.10.0-beta', '0.9.9'), isTrue);
    expect(isNewerVersion('v1.0.0', '0.99.99'), isTrue);
    expect(isNewerVersion('v0.4.4-beta', '0.4.4'), isFalse, reason: 'same');
    expect(isNewerVersion('v0.4.3-beta', '0.4.4'), isFalse, reason: 'older');
    expect(isNewerVersion('garbage', '0.4.4'), isFalse);
    expect(isNewerVersion('v0.4.5', 'garbage'), isFalse);
  });

  test('ReleaseInfo.version strips the v prefix and channel suffix', () {
    final r = ReleaseInfo(tag: 'v0.4.5-beta', url: Uri.parse('https://x'));
    expect(r.version, '0.4.5');
  });

  test('the update link always points to the latest release page', () {
    expect(
      latestReleasePage.toString(),
      'https://github.com/Brandart1/better-betteruntis/releases/latest',
    );
  });

  test('AppVersion shows the build number when known', () {
    expect('${const AppVersion('0.4.4', '19')}', '0.4.4 (19)');
    expect('${const AppVersion('0.4.4', '')}', '0.4.4');
  });

  group('parseRelease', () {
    const hex =
        'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';
    Map<String, dynamic> release({
      String tag = 'v0.5.1-beta',
      bool prerelease = false,
      bool draft = false,
      List<Object?>? assets,
    }) => {
      'tag_name': tag,
      'prerelease': prerelease,
      'draft': draft,
      'assets':
          assets ??
          [
            {
              'name': 'better-betteruntis-$tag.aab',
              'browser_download_url': 'https://github.com/x/y/z.aab',
              'size': 5,
            },
            {
              'name': 'better-betteruntis-$tag.apk',
              'browser_download_url':
                  'https://github.com/Brandart1/better-betteruntis/releases/download/$tag/better-betteruntis-$tag.apk',
              'size': 1234,
              'digest': 'sha256:${hex.toUpperCase()}',
            },
          ],
    };

    test('reads the APK asset with size and SHA-256 digest', () {
      final r = parseRelease(release())!;
      expect(r.tag, 'v0.5.1-beta');
      expect(r.url, latestReleasePage);
      expect(r.apk!.name, 'better-betteruntis-v0.5.1-beta.apk');
      expect(r.apk!.size, 1234);
      expect(r.apk!.sha256, hex);
      expect(r.apk!.url.host, 'github.com');
    });

    test('stable tags work too; no digest means no sha256', () {
      final r = parseRelease(
        release(
          tag: 'v1.0.0',
          assets: [
            {
              'name': 'better-betteruntis-v1.0.0.apk',
              'browser_download_url': 'https://github.com/a/b/c.apk',
              'size': 10,
              'digest': null,
            },
          ],
        ),
      )!;
      expect(r.apk!.sha256, isNull);
    });

    test('alphas, pre-releases and drafts are ignored', () {
      expect(parseRelease(release(tag: 'v0.6.0-alpha.3')), isNull);
      expect(parseRelease(release(tag: 'v0.6.0-ALPHA')), isNull);
      expect(parseRelease(release(prerelease: true)), isNull);
      expect(parseRelease(release(draft: true)), isNull);
      expect(parseRelease({'name': 'no tag'}), isNull);
    });

    test('no usable APK: release without apk', () {
      expect(parseRelease(release(assets: []))!.apk, isNull);
      // Not from github.com, not https, or no size: not offered.
      for (final a in [
        {
          'name': 'better-betteruntis-v0.5.1-beta.apk',
          'browser_download_url': 'https://evil.example/x.apk',
          'size': 10,
        },
        {
          'name': 'better-betteruntis-v0.5.1-beta.apk',
          'browser_download_url': 'http://github.com/x.apk',
          'size': 10,
        },
        {
          'name': 'better-betteruntis-v0.5.1-beta.apk',
          'browser_download_url': 'https://github.com/x.apk',
        },
      ]) {
        expect(parseRelease(release(assets: [a]))!.apk, isNull);
      }
    });

    test('parseSha256Digest accepts only sha256 with 64 hex digits', () {
      expect(parseSha256Digest('sha256:$hex'), hex);
      expect(parseSha256Digest('sha512:$hex'), isNull);
      expect(parseSha256Digest('sha256:abc'), isNull);
      expect(parseSha256Digest(null), isNull);
    });
  });

  group('alpha updates', () {
    Map<String, dynamic> rel(String tag, {bool prerelease = false}) => {
      'tag_name': tag,
      'prerelease': prerelease,
      'draft': false,
      'html_url':
          'https://github.com/Brandart1/better-betteruntis/releases/tag/$tag',
      'assets': [
        {
          'name': 'better-betteruntis-$tag.apk',
          'browser_download_url':
              'https://github.com/Brandart1/better-betteruntis/releases/download/$tag/better-betteruntis-$tag.apk',
          'size': 10,
          'digest': 'sha256:${'a' * 64}',
        },
      ],
    };

    test('releaseKey orders alpha < beta < stable, then the alpha number', () {
      expect(releaseKey('v0.5.6-alpha'), [0, 5, 6, 0, 1]);
      expect(releaseKey('v0.5.6-alpha.2'), [0, 5, 6, 0, 2]);
      expect(releaseKey('v0.5.6-beta'), [0, 5, 6, 1, 0]);
      expect(releaseKey('v0.5.6'), [0, 5, 6, 2, 0]);
      expect(releaseKey('nonsense'), isNull);
    });

    test('isUpdate: tags for alpha builds, X.Y.Z otherwise', () {
      expect(
        isUpdate('v0.5.6-alpha.2', '0.5.6', currentTag: 'v0.5.6-alpha.1'),
        isTrue,
      );
      expect(
        isUpdate('v0.5.6-alpha.1', '0.5.6', currentTag: 'v0.5.6-alpha.1'),
        isFalse,
      );
      expect(
        isUpdate('v0.5.6-beta', '0.5.6', currentTag: 'v0.5.6-alpha.3'),
        isTrue,
      );
      expect(
        isUpdate('v0.5.5-beta', '0.5.6', currentTag: 'v0.5.6-alpha.1'),
        isFalse,
      );
      // Without a tag (betas, stables) nothing changes.
      expect(isUpdate('v0.5.6-alpha.2', '0.5.6'), isFalse);
      expect(isUpdate('v0.5.7-beta', '0.5.6'), isTrue);
    });

    test('pickAlphaUpdate: newest of the same line, betas of any line', () {
      final list = [
        rel('v0.6.0-alpha.9', prerelease: true), // teacher line: skipped
        rel('v0.5.6-alpha.3', prerelease: true),
        rel('v0.5.6-alpha.2', prerelease: true),
        rel('v0.5.5-beta'),
        {'tag_name': 'v0.5.6-alpha.4', 'draft': true},
      ];
      final r = pickAlphaUpdate(list, 'v0.5.6-alpha.2')!;
      expect(r.tag, 'v0.5.6-alpha.3');
      expect(r.url.toString(), endsWith('/releases/tag/v0.5.6-alpha.3'));
      expect(r.apk!.sha256, 'a' * 64);
      expect(pickAlphaUpdate(list, 'v0.5.6-alpha.3'), isNull);
      expect(
        pickAlphaUpdate([...list, rel('v0.6.0-beta')], 'v0.5.6-alpha.3')!.tag,
        'v0.6.0-beta',
      );
    });

    test('beta builds still never see alphas', () {
      expect(parseRelease(rel('v0.5.6-alpha.3', prerelease: true)), isNull);
    });
  });
}
