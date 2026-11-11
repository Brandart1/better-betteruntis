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
}
