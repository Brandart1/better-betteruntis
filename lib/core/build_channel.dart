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
