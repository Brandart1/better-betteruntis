/// Bundled release notes ("What's new"): the index of released versions,
/// which notes to show for a stored and the current version, and the
/// providers that load them. The assets are generated from
/// `.github/release-notes` by `tool/sync_release_notes.dart`.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/build_channel.dart';
import '../core/release_version.dart';
import '../core/settings.dart';
import 'app_update.dart';

const releaseNotesAssetDir = 'assets/release_notes';

/// [SettingsStore] key of the last version (normalized [ReleaseVersion]
/// string) whose "What's new" was seen.
const lastVersionOpenedKey = 'lastVersionOpened';

/// One bundled release note.
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.tag,
    required this.file,
  });

  final ReleaseVersion version;

  /// `v0.4.8-alpha.7`, shown as the title.
  final String tag;

  /// File name inside [releaseNotesAssetDir].
  final String file;

  String get assetPath => '$releaseNotesAssetDir/$file';

  @override
  String toString() => 'ReleaseNote($tag)';
}

/// Parses `index.json`; broken entries are skipped. Newest first.
List<ReleaseNote> parseReleaseIndex(String json) {
  final out = <ReleaseNote>[];
  try {
    final decoded = jsonDecode(json);
    final list = decoded is Map ? decoded['releases'] : null;
    if (list is! List) return out;
    for (final e in list) {
      if (e is! Map) continue;
      final tag = e['tag'], file = e['file'];
      if (tag is! String || file is! String) continue;
      final v = ReleaseVersion.tryParse(tag);
      if (v == null) continue;
      out.add(ReleaseNote(version: v, tag: tag, file: file));
    }
  } on FormatException {
    return out;
  }
  out.sort((a, b) => b.version.compareTo(a.version));
  return out;
}

/// Alpha (and local dev) builds show every note; beta and stable builds
/// skip alpha notes, because each beta's notes already cover everything
/// since the previous beta.
bool noteVisibleIn(ReleaseVersion note, String channel) =>
    note.channel != ReleaseChannel.alpha ||
    channel == 'alpha' ||
    channel == 'dev';

/// Notes with [after] < version <= [upTo] (no lower bound when [after] is
/// null) that [channel] shows, newest first.
List<ReleaseNote> selectReleaseNotes(
  List<ReleaseNote> all, {
  ReleaseVersion? after,
  required ReleaseVersion upTo,
  required String channel,
}) => [
  for (final n in all)
    if ((after == null || n.version > after) &&
        n.version <= upTo &&
        noteVisibleIn(n.version, channel))
      n,
]..sort((a, b) => b.version.compareTo(a.version));

/// What to do at start.
sealed class WhatsNewDecision {
  const WhatsNewDecision();
}

/// Same version, or a downgrade: nothing to show, nothing to store.
class WhatsNewNothing extends WhatsNewDecision {
  const WhatsNewNothing();
}

/// Store the current version without showing anything (fresh install, first
/// run of the feature, or no bundled notes in between).
class WhatsNewStoreSilently extends WhatsNewDecision {
  const WhatsNewStoreSilently();
}

/// Show [notes] (newest first), then store the current version.
class WhatsNewShow extends WhatsNewDecision {
  const WhatsNewShow(this.notes);
  final List<ReleaseNote> notes;
}

WhatsNewDecision decideWhatsNew({
  required Object? stored,
  required ReleaseVersion current,
  required List<ReleaseNote> all,
  required String channel,
}) {
  final last = stored is String ? ReleaseVersion.tryParse(stored) : null;
  if (last == null) return const WhatsNewStoreSilently();
  if (last >= current) return const WhatsNewNothing();
  final notes = selectReleaseNotes(
    all,
    after: last,
    upTo: current,
    channel: channel,
  );
  return notes.isEmpty ? const WhatsNewStoreSilently() : WhatsNewShow(notes);
}

/// The running release. The tag baked in by the release workflow wins;
/// without it the version name (X.Y.Z) is combined with the channel: beta
/// and stable builds are X.Y.Z-beta / X.Y.Z, alpha and dev builds the newest
/// bundled release of X.Y.Z (alpha.1 if there is none). Null when neither
/// tag nor version name can be parsed.
ReleaseVersion? resolveCurrentRelease({
  required String tag,
  required String? appVersion,
  required String channel,
  required List<ReleaseNote> all,
}) {
  final fromTag = ReleaseVersion.tryParse(tag);
  if (fromTag != null) return fromTag;
  final v = ReleaseVersion.tryParse(appVersion);
  if (v == null) return null;
  final core = ReleaseVersion(v.major, v.minor, v.patch);
  switch (ReleaseChannel.tryParse(channel)) {
    case ReleaseChannel.stable:
      return core;
    case ReleaseChannel.beta:
      return ReleaseVersion(
        v.major,
        v.minor,
        v.patch,
        channel: ReleaseChannel.beta,
        number: 1,
      );
    case ReleaseChannel.alpha || null:
      for (final n in all) {
        if (n.version.sameCore(core) && noteVisibleIn(n.version, channel)) {
          return n.version;
        }
      }
      return ReleaseVersion(
        v.major,
        v.minor,
        v.patch,
        channel: ReleaseChannel.alpha,
        number: 1,
      );
  }
}

/// The part of a note shown in the app: without the redundant
/// `## New in this release` heading and without `## Install` sections
/// (download instructions for the GitHub release page).
String releaseNoteBody(String markdown) {
  final out = <String>[];
  var skipping = false;
  for (final line in const LineSplitter().convert(markdown)) {
    final h2 = RegExp(r'^##\s+(.*?)\s*$').firstMatch(line);
    if (h2 != null) {
      final title = h2.group(1)!.toLowerCase();
      skipping = title == 'install' || title.startsWith('install ');
      if (title == 'new in this release') continue;
    }
    if (!skipping) out.add(line);
  }
  return out.join('\n').trim();
}

/// Loads a bundled text asset. Overridable in tests.
final releaseNotesAssetLoaderProvider =
    Provider<Future<String> Function(String path)>(
      (ref) => rootBundle.loadString,
    );

/// All bundled notes, newest first; empty if the index can't be loaded.
final releaseNotesIndexProvider = FutureProvider<List<ReleaseNote>>((
  ref,
) async {
  try {
    final load = ref.watch(releaseNotesAssetLoaderProvider);
    return parseReleaseIndex(await load('$releaseNotesAssetDir/index.json'));
  } catch (_) {
    return const [];
  }
});

/// Displayed text of one note ([ReleaseNote.assetPath]).
final releaseNoteTextProvider = FutureProvider.family<String, String>((
  ref,
  assetPath,
) async {
  final load = ref.watch(releaseNotesAssetLoaderProvider);
  return releaseNoteBody(await load(assetPath));
});

/// Build channel used for the channel rule. Overridable in tests.
final releaseChannelProvider = Provider<String>((ref) => buildChannel);

/// The running release; null where the version can't be read (tests).
final currentReleaseProvider = FutureProvider<ReleaseVersion?>((ref) async {
  final app = await ref.watch(appVersionProvider.future);
  final all = await ref.watch(releaseNotesIndexProvider.future);
  return resolveCurrentRelease(
    tag: buildTag,
    appVersion: app?.version,
    channel: ref.watch(releaseChannelProvider),
    all: all,
  );
});

/// Whether to check for "What's new" at start. Overridable in tests.
final whatsNewCheckEnabledProvider = Provider<bool>((ref) => true);
