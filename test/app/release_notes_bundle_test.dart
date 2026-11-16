import 'dart:convert';
import 'dart:io';

import 'package:better_betteruntis/app/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/sync_release_notes.dart' as sync;

void main() {
  test('assets/release_notes is up to date with .github/release-notes', () {
    final expected = sync.expectedBundle(Directory(sync.sourceDir));
    final diffs = sync.bundleDifferences(Directory(sync.bundleDir), expected);
    expect(
      diffs,
      isEmpty,
      reason:
          'Run `dart run tool/sync_release_notes.dart` and commit '
          'assets/release_notes/.',
    );
  });

  test('the bundled index lists only released versions, newest first', () {
    final json = File('${sync.bundleDir}/${sync.indexFile}').readAsStringSync();
    final idx = parseReleaseIndex(json);
    expect(idx, isNotEmpty);
    final raw = (jsonDecode(json) as Map)['releases'] as List;
    expect(raw.length, idx.length, reason: 'every entry parses');
    for (var i = 1; i < idx.length; i++) {
      expect(idx[i - 1].version > idx[i].version, isTrue);
    }
    for (final n in idx) {
      expect(n.file, startsWith('v'));
      expect(File('${sync.bundleDir}/${n.file}').existsSync(), isTrue);
    }
    expect(idx.map((n) => n.file), isNot(contains('next.md')));
  });

  group('generator', () {
    late Directory tmp, src, out;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('bbu_notes');
      src = Directory('${tmp.path}/src')..createSync();
      out = Directory('${tmp.path}/out');
      for (final name in [
        'v0.4.8-alpha.md',
        'v0.4.8-alpha.2.md',
        'v0.4.7-beta.md',
        'v0.5.0.md',
        'next.md',
        'next-server.md',
        'default.md',
        'README.md',
        'v0.4.9-rc.1.md',
      ]) {
        File('${src.path}/$name')
            .writeAsStringSync('## New in this release\n$name\n');
      }
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('copies only tag-named files and writes the index', () {
      final expected = sync.expectedBundle(src);
      expect(expected.keys.toSet(), {
        'v0.5.0.md',
        'v0.4.8-alpha.2.md',
        'v0.4.8-alpha.md',
        'v0.4.7-beta.md',
        'index.json',
      });
      final index = jsonDecode(expected['index.json']!) as Map;
      expect(
        [for (final e in index['releases'] as List) e['version']],
        ['0.5.0', '0.4.8-alpha.2', '0.4.8-alpha.1', '0.4.7-beta'],
      );
      expect((index['releases'] as List)[2], {
        'version': '0.4.8-alpha.1',
        'tag': 'v0.4.8-alpha',
        'channel': 'alpha',
        'file': 'v0.4.8-alpha.md',
      });
    });

    test('detects missing, changed and extra files; write fixes them', () {
      final expected = sync.expectedBundle(src);
      expect(sync.bundleDifferences(out, expected), hasLength(5));
      sync.writeBundle(out, expected);
      expect(sync.bundleDifferences(out, expected), isEmpty);

      File('${out.path}/v0.5.0.md').writeAsStringSync('edited');
      File('${out.path}/v0.1.0.md').writeAsStringSync('removed upstream');
      File('${out.path}/v0.4.7-beta.md').deleteSync();
      expect(sync.bundleDifferences(out, expected), [
        'changed: v0.5.0.md',
        'extra: v0.1.0.md',
        'missing: v0.4.7-beta.md',
      ]);
      sync.writeBundle(out, expected);
      expect(sync.bundleDifferences(out, expected), isEmpty);
    });

    test('two files for the same release are an error', () {
      File('${src.path}/v0.4.8-alpha.1.md').writeAsStringSync('dup');
      expect(() => sync.expectedBundle(src), throwsStateError);
    });
  });
}
