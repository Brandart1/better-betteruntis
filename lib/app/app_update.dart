/// App version and the "is this the latest release?" check against GitHub.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/build_channel.dart';

const repoUrl = 'https://github.com/Brandart1/better-betteruntis';

/// Always redirects to the newest full release; linked from the update dialog.
final latestReleasePage = Uri.parse('$repoUrl/releases/latest');

/// GitHub's "latest" release skips pre-releases (alphas), drafts excluded.
const latestReleaseApi =
    'https://api.github.com/repos/Brandart1/better-betteruntis/releases/latest';

/// Version name (`0.4.4`) and build number (`19`) of the running app.
class AppVersion {
  const AppVersion(this.version, this.build);
  final String version;
  final String build;

  @override
  String toString() => build.isEmpty ? version : '$version ($build)';
}

/// The newest published release.
class ReleaseInfo {
  const ReleaseInfo({required this.tag, required this.url});
  final String tag;
  final Uri url;

  /// `v0.4.5-beta` → `0.4.5`.
  String get version => tag.replaceFirst(RegExp('^v'), '').split('-').first;
}

/// `v0.4.5-beta`, `0.4.5+20` or `0.4.5` → `[0, 4, 5]`; null if unparsable.
List<int>? parseVersion(String s) {
  final core = s
      .trim()
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[-+]'))
      .first;
  final parts = core.split('.');
  if (parts.length != 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.contains(null)) return null;
  return nums.cast<int>();
}

/// True if [latest] is a higher X.Y.Z than [current]. Suffixes (`-beta`,
/// `+19`) are ignored; unparsable input never counts as newer.
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Asks GitHub for the latest release. Null on any failure (offline, rate
/// limit, unexpected answer): the check is best effort and stays silent.
Future<ReleaseInfo?> fetchLatestRelease(Dio dio) async {
  try {
    final res = await dio.get<Map<String, dynamic>>(
      latestReleaseApi,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'better-betteruntis',
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final data = res.data;
    final tag = data?['tag_name'];
    if (tag is! String) return null;
    return ReleaseInfo(tag: tag, url: latestReleasePage);
  } catch (_) {
    return null;
  }
}

/// Version of the running app; null where it can't be read (tests).
final appVersionProvider = FutureProvider<AppVersion?>((ref) async {
  try {
    final p = await PackageInfo.fromPlatform();
    return AppVersion(p.version, p.buildNumber);
  } catch (_) {
    return null;
  }
});

/// Latest release lookup. Overridable in tests.
final latestReleaseFetcherProvider = Provider<Future<ReleaseInfo?> Function()>(
  (ref) =>
      () => fetchLatestRelease(
        Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
      ),
);

/// Whether to check for updates at start. Not on the web (the host updates
/// it) and not in local dev builds (no release to compare against, and tests
/// must not hit the network).
final updateCheckEnabledProvider = Provider<bool>(
  (ref) => !kIsWeb && buildChannel != 'dev',
);
