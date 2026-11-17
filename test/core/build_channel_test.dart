import 'package:better_betteruntis/core/build_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alphas show their number, other channels stay as they are', () {
    expect(channelLabel('alpha', 'v0.5.6-alpha.2'), 'alpha.2');
    expect(channelLabel('alpha', 'v0.5.6-alpha'), 'alpha.1');
    expect(channelLabel('alpha', ''), 'alpha');
    expect(channelLabel('beta', 'v0.5.6-beta'), 'beta');
    expect(channelLabel('stable', 'v1.0.0'), 'stable');
    expect(channelLabel('dev', ''), 'dev');
  });
}
