import 'package:better_betteruntis/core/release_version.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseVersion v(String s) => ReleaseVersion.tryParse(s)!;

void main() {
  group('parsing', () {
    test('tags, file names, plain versions and build numbers', () {
      expect(v('v0.4.8-alpha.7').toString(), '0.4.8-alpha.7');
      expect(v('0.4.8-alpha.7').channel, ReleaseChannel.alpha);
      expect(v('v0.4.8-alpha.7').number, 7);
      expect(v('v0.4.7-beta.md').toString(), '0.4.7-beta');
      expect(v('v0.4.7-beta').channel, ReleaseChannel.beta);
      expect(v('v0.5.0').toString(), '0.5.0');
      expect(v('0.5.0+81').toString(), '0.5.0');
      expect(v(' V1.2.3-ALPHA.2 ').toString(), '1.2.3-alpha.2');
      expect(v('10.20.30').major, 10);
    });

    test('a plain -alpha is the first alpha', () {
      expect(v('v0.4.8-alpha'), v('v0.4.8-alpha.1'));
      expect(v('v0.4.8-alpha').toString(), '0.4.8-alpha.1');
      expect(v('v0.4.8-alpha') < v('v0.4.8-alpha.2'), isTrue);
    });

    test('garbage is null', () {
      for (final s in [
        null,
        '',
        'next.md',
        'default.md',
        'README.md',
        'next-server.md',
        '0.4',
        '0.4.8.1',
        'v0.4.8-rc.1',
        'v0.4.8-alpha.x',
        'v0.4.8-alpha.',
        'a0.4.8',
        '0.4.8 beta',
      ]) {
        expect(ReleaseVersion.tryParse(s), isNull, reason: '$s');
      }
    });
  });

  group('ordering', () {
    test('X.Y.Z first, then alpha.N < beta < stable', () {
      final sorted = [
        'v0.3.2-alpha',
        'v0.4.0-beta',
        'v0.4.6-alpha',
        'v0.4.6-alpha.2',
        'v0.4.6-alpha.10',
        'v0.4.6-beta',
        'v0.4.6-beta.2',
        'v0.4.6',
        'v0.4.10-alpha',
        'v0.10.0',
        'v1.0.0-alpha',
      ].map(v).toList();
      final shuffled = [...sorted.reversed]..sort();
      expect(shuffled, sorted);
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i - 1] < sorted[i], isTrue, reason: '${sorted[i]}');
        expect(sorted[i] > sorted[i - 1], isTrue);
        expect(sorted[i] >= sorted[i], isTrue);
        expect(sorted[i] <= sorted[i], isTrue);
      }
    });

    test('equality ignores v, build numbers and alpha vs alpha.1', () {
      expect(v('0.5.0+81'), v('v0.5.0'));
      expect(v('v0.4.8-alpha').hashCode, v('0.4.8-alpha.1').hashCode);
      expect(v('0.4.8-beta') == v('0.4.8'), isFalse);
      expect(v('0.4.8').sameCore(v('0.4.8-alpha.3')), isTrue);
      expect(v('0.4.8').sameCore(v('0.4.9')), isFalse);
    });
  });

  test('channel names', () {
    expect(ReleaseChannel.tryParse('alpha'), ReleaseChannel.alpha);
    expect(ReleaseChannel.tryParse('Beta'), ReleaseChannel.beta);
    expect(ReleaseChannel.tryParse('stable'), ReleaseChannel.stable);
    expect(ReleaseChannel.tryParse('dev'), isNull);
  });
}
