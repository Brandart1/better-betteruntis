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

/// The Android APK attached to a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
  final String name;

  /// `browser_download_url` (https on github.com, redirects to the CDN).
  final Uri url;

  /// Size in bytes as reported by GitHub.
  final int size;

  /// Lower-case hex SHA-256 from GitHub's `digest` field, when provided.
  final String? sha256;
}

/// The newest published release.
class ReleaseInfo {
  const ReleaseInfo({required this.tag, required this.url, this.apk});
  final String tag;
  final Uri url;

  /// The APK for the in-app updater on Android; null if none is attached.
  final ReleaseAsset? apk;

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
    return data == null ? null : parseRelease(data);
  } catch (_) {
    return null;
  }
}

/// Turns a GitHub release JSON object into a [ReleaseInfo]. Null for drafts,
/// pre-releases and alpha tags: `/releases/latest` already skips those, this
/// is defence in depth so the updater only ever offers betas and stables.
///
/// [allowAlpha] (alpha builds only, see [pickAlphaUpdate]) also accepts
/// pre-releases and alpha tags; their page is the release's own.
ReleaseInfo? parseRelease(
  Map<String, dynamic> data, {
  bool allowAlpha = false,
}) {
  final tag = data['tag_name'];
  if (tag is! String || tag.isEmpty) return null;
  if (data['draft'] == true) return null;
  final alpha =
      data['prerelease'] == true || tag.toLowerCase().contains('-alpha');
  if (alpha && !allowAlpha) return null;
  final page = data['html_url'];
  return ReleaseInfo(
    tag: tag,
    url: alpha && page is String && page.startsWith('$repoUrl/')
        ? Uri.parse(page)
        : latestReleasePage,
    apk: _parseApk(data['assets'], tag),
  );
}

/// All releases, newest first (alpha builds look at alphas too).
const releasesApi =
    'https://api.github.com/repos/Brandart1/better-betteruntis/releases?per_page=30';

/// Sort key of a tag: X, Y, Z, then alpha (0) < beta (1) < stable (2), then
/// the alpha number (`-alpha` = 1). `v0.5.6-alpha.2` → [0, 5, 6, 0, 2].
List<int>? releaseKey(String tag) {
  final v = parseVersion(tag);
  if (v == null) return null;
  final t = tag.toLowerCase();
  final alpha = RegExp(r'-alpha(?:\.(\d+))?').firstMatch(t);
  if (alpha != null) return [...v, 0, int.parse(alpha.group(1) ?? '1')];
  return [...v, t.contains('-beta') ? 1 : 2, 0];
}

int _compareKeys(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// Whether [latestTag] is an update for the running app. With the build's
/// own tag ([currentTag], alpha builds) alphas count: `v0.5.6-alpha.2` is an
/// update for `v0.5.6-alpha.1`. Otherwise only X.Y.Z of [currentVersion].
bool isUpdate(
  String latestTag,
  String currentVersion, {
  String currentTag = '',
}) {
  final cur = currentTag.isEmpty ? null : releaseKey(currentTag);
  final lat = releaseKey(latestTag);
  if (cur == null || lat == null) {
    return isNewerVersion(latestTag, currentVersion);
  }
  return _compareKeys(lat, cur) > 0;
}

/// The newest release in [releases] (GitHub's list) for an alpha build
/// tagged [currentTag]: betas and stables, plus alphas of the same X.Y line
/// (a 0.5 alpha is never offered a 0.6 teacher alpha). Null if none is
/// newer.
ReleaseInfo? pickAlphaUpdate(List<Object?> releases, String currentTag) {
  final cur = releaseKey(currentTag);
  if (cur == null) return null;
  ReleaseInfo? best;
  List<int>? bestKey;
  for (final r in releases) {
    if (r is! Map<String, dynamic>) continue;
    final info = parseRelease(r, allowAlpha: true);
    if (info == null) continue;
    final key = releaseKey(info.tag);
    if (key == null) continue;
    final sameLine = key[0] == cur[0] && key[1] == cur[1];
    if (key[3] == 0 && !sameLine) continue;
    if (_compareKeys(key, cur) <= 0) continue;
    if (bestKey == null || _compareKeys(key, bestKey) > 0) {
      best = info;
      bestKey = key;
    }
  }
  return best;
}

/// [pickAlphaUpdate] over GitHub's release list. Null on any failure.
Future<ReleaseInfo?> fetchAlphaUpdate(Dio dio, String currentTag) async {
  try {
    final res = await dio.get<List<dynamic>>(
      releasesApi,
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
    return data == null ? null : pickAlphaUpdate(data, currentTag);
  } catch (_) {
    return null;
  }
}

/// The release's APK: `better-betteruntis-<tag>.apk` (see release.yml), else
/// the only `.apk`. Must be an https download from github.com.
ReleaseAsset? _parseApk(Object? assets, String tag) {
  if (assets is! List) return null;
  final apks = <ReleaseAsset>[];
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'], url = a['browser_download_url'], size = a['size'];
    if (name is! String || !name.toLowerCase().endsWith('.apk')) continue;
    if (url is! String || size is! int || size <= 0) continue;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      continue;
    }
    apks.add(
      ReleaseAsset(
        name: name,
        url: uri,
        size: size,
        sha256: parseSha256Digest(a['digest']),
      ),
    );
  }
  final exact = apks.where((a) => a.name == 'better-betteruntis-$tag.apk');
  if (exact.isNotEmpty) return exact.first;
  return apks.length == 1 ? apks.single : null;
}

/// `sha256:<64 hex>` → lower-case hex; null for other or missing digests.
String? parseSha256Digest(Object? digest) {
  if (digest is! String) return null;
  final m = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digest.trim());
  return m?.group(1)!.toLowerCase();
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
/// Alpha builds (with their tag baked in) also get newer alphas of their
/// line; everything else only betas and stables.
final latestReleaseFetcherProvider = Provider<Future<ReleaseInfo?> Function()>(
  (ref) => () {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
    return buildChannel == 'alpha' && buildTag.isNotEmpty
        ? fetchAlphaUpdate(dio, buildTag)
        : fetchLatestRelease(dio);
  },
);

/// Whether to check for updates at start. Not on the web (the host updates
/// it) and not in local dev builds (no release to compare against, and tests
/// must not hit the network).
final updateCheckEnabledProvider = Provider<bool>(
  (ref) => !kIsWeb && buildChannel != 'dev',
);
