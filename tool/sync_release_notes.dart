/// Copies the release notes of released versions from `.github/release-notes`
/// into `assets/release_notes/` (bundled with the app for "What's new") and
/// writes `assets/release_notes/index.json`.
///
///   dart run tool/sync_release_notes.dart          # regenerate
///   dart run tool/sync_release_notes.dart --check  # exit 1 if out of date
///
/// Only tag-named files count as releases (`vX.Y.Z.md`, `vX.Y.Z-beta.md`,
/// `vX.Y.Z-alpha[.N].md`); drafts (`next*.md`), `default.md` and `README.md`
/// are skipped. test/app/release_notes_bundle_test.dart fails when the
/// bundled copy is stale, so CI catches a forgotten regeneration.
library;

import 'dart:convert';
import 'dart:io';

import 'package:better_betteruntis/core/release_version.dart';

const sourceDir = '.github/release-notes';
const bundleDir = 'assets/release_notes';
const indexFile = 'index.json';

final _tagFile = RegExp(r'^v\d+\.\d+\.\d+(?:-(?:alpha|beta)(?:\.\d+)?)?\.md$');

/// The bundle as it should be: file name → content (notes files and
/// [indexFile]), built from the notes in [source].
Map<String, String> expectedBundle(Directory source) {
  final releases = <(ReleaseVersion, String)>[];
  for (final f in source.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!_tagFile.hasMatch(name)) continue;
    final v = ReleaseVersion.tryParse(name);
    if (v == null) continue;
    final clash = releases.where((r) => r.$1 == v).firstOrNull;
    if (clash != null) {
      throw StateError('$name and ${clash.$2} are the same release ($v)');
    }
    releases.add((v, name));
  }
  releases.sort((a, b) => b.$1.compareTo(a.$1));
  final out = <String, String>{};
  for (final (_, name) in releases) {
    out[name] = File('${source.path}/$name').readAsStringSync();
  }
  final index = {
    'releases': [
      for (final (v, name) in releases)
        {
          'version': v.toString(),
          'tag': name.substring(0, name.length - 3),
          'channel': v.channel.name,
          'file': name,
        },
    ],
  };
  out[indexFile] = '${const JsonEncoder.withIndent('  ').convert(index)}\n';
  return out;
}

/// Differences between the bundle in [bundle] and [expected]: missing,
/// changed and extra files (relative names). Empty when up to date.
List<String> bundleDifferences(Directory bundle, Map<String, String> expected) {
  final diffs = <String>[];
  final present = <String>{
    if (bundle.existsSync())
      for (final f in bundle.listSync().whereType<File>())
        f.uri.pathSegments.last,
  };
  for (final MapEntry(:key, :value) in expected.entries) {
    if (!present.contains(key)) {
      diffs.add('missing: $key');
    } else if (File('${bundle.path}/$key').readAsStringSync() != value) {
      diffs.add('changed: $key');
    }
  }
  for (final name in present.difference(expected.keys.toSet())) {
    diffs.add('extra: $name');
  }
  return diffs..sort();
}

/// Writes [expected] into [bundle] and removes files that don't belong.
void writeBundle(Directory bundle, Map<String, String> expected) {
  bundle.createSync(recursive: true);
  for (final f in bundle.listSync().whereType<File>()) {
    if (!expected.containsKey(f.uri.pathSegments.last)) f.deleteSync();
  }
  for (final MapEntry(:key, :value) in expected.entries) {
    final f = File('${bundle.path}/$key');
    if (!f.existsSync() || f.readAsStringSync() != value) {
      f.writeAsStringSync(value);
    }
  }
}

void main(List<String> args) {
  final expected = expectedBundle(Directory(sourceDir));
  final bundle = Directory(bundleDir);
  final diffs = bundleDifferences(bundle, expected);
  if (args.contains('--check')) {
    if (diffs.isEmpty) {
      stdout.writeln('Bundled release notes are up to date.');
      return;
    }
    stderr.writeln(
      'Bundled release notes are out of date '
      '(run `dart run tool/sync_release_notes.dart`):\n  ${diffs.join('\n  ')}',
    );
    exitCode = 1;
    return;
  }
  writeBundle(bundle, expected);
  stdout.writeln(
    diffs.isEmpty
        ? 'Bundled release notes were already up to date.'
        : 'Updated $bundleDir:\n  ${diffs.join('\n  ')}',
  );
}
