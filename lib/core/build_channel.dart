/// Release channel baked in at build time with
/// `--dart-define=BBU_CHANNEL=alpha|beta|stable` (the release workflow derives
/// it from the tag). Local and CI builds without it are `dev`.
library;

const String buildChannel = String.fromEnvironment(
  'BBU_CHANNEL',
  defaultValue: 'dev',
);

/// The Debug screen (raw API data) is only offered in dev and alpha builds.
const bool debugToolsEnabled = buildChannel == 'dev' || buildChannel == 'alpha';

/// Release tag baked in at build time with `--dart-define=BBU_TAG=v0.5.0-alpha.2`
/// (release workflow). The app's version name only carries X.Y.Z, so this is
/// how "What's new" knows which alpha it is. Empty in local and CI builds.
const String buildTag = String.fromEnvironment('BBU_TAG');

/// The channel as shown next to the version: alphas carry their number
/// ("alpha.2"; a bare "-alpha" tag is alpha.1), the other channels stay as
/// they are.
String channelLabel([String channel = buildChannel, String tag = buildTag]) {
  if (channel != 'alpha') return channel;
  final m = RegExp(
    r'-alpha(?:\.(\d+))?$',
    caseSensitive: false,
  ).firstMatch(tag);
  if (m == null) return channel;
  return 'alpha.${m.group(1) ?? '1'}';
}
