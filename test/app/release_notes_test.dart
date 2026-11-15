import 'dart:convert';

import 'package:better_betteruntis/app/release_notes.dart';
import 'package:better_betteruntis/core/release_version.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseVersion v(String s) => ReleaseVersion.tryParse(s)!;

ReleaseNote note(String tag) =>
    ReleaseNote(version: v(tag), tag: tag, file: '$tag.md');

/// Like the real history: alphas, a beta that covers them, and a stable.
final all = [
  'v0.4.6-alpha',
  'v0.4.6-alpha.2',
  'v0.4.6-beta',
  'v0.4.7-alpha',
  'v0.4.7-alpha.2',
  'v0.4.7-beta',
  'v0.4.8-alpha',
  'v0.4.8-alpha.2',
  'v0.4.8-alpha.3',
  'v0.5.0',
].map(note).toList().reversed.toList();

List<String> tags(List<ReleaseNote> n) => [for (final x in n) x.tag];

List<String>? shown(Object? stored, String current, String channel) {
  final d = decideWhatsNew(
    stored: stored,
    current: v(current),
    all: all,
    channel: channel,
  );
  return switch (d) {
    WhatsNewShow(:final notes) => tags(notes),
    WhatsNewStoreSilently() => const ['<store>'],
    WhatsNewNothing() => null,
  };
}

void main() {
  group('decideWhatsNew', () {
    test('fresh install / first run of the feature: store silently', () {
      expect(shown(null, '0.4.8-alpha.3', 'alpha'), ['<store>']);
      expect(shown('garbage', '0.4.8-alpha.3', 'alpha'), ['<store>']);
      expect(shown(42, '0.4.8-alpha.3', 'alpha'), ['<store>']);
    });

    test('same version: nothing', () {
      expect(shown('0.4.8-alpha.3', '0.4.8-alpha.3', 'alpha'), isNull);
      // A plain -alpha equals alpha.1.
      expect(shown('0.4.8-alpha', '0.4.8-alpha.1', 'alpha'), isNull);
    });

    test('downgrade: nothing', () {
      expect(shown('0.5.0', '0.4.8-alpha.3', 'alpha'), isNull);
      expect(shown('0.4.8-alpha.3', '0.4.8-alpha.2', 'alpha'), isNull);
      expect(shown('0.4.7', '0.4.7-beta', 'beta'), isNull);
    });

    test('one missed alpha', () {
      expect(shown('0.4.8-alpha.2', '0.4.8-alpha.3', 'alpha'), [
        'v0.4.8-alpha.3',
      ]);
    });

    test(
      'many missed: every release > stored and <= current, newest first',
      () {
        expect(shown('0.4.6-beta', '0.4.8-alpha.3', 'alpha'), [
          'v0.4.8-alpha.3',
          'v0.4.8-alpha.2',
          'v0.4.8-alpha',
          'v0.4.7-beta',
          'v0.4.7-alpha.2',
          'v0.4.7-alpha',
        ]);
      },
    );

    test('beta and stable builds skip alpha notes', () {
      expect(shown('0.4.6-beta', '0.4.7-beta', 'beta'), ['v0.4.7-beta']);
      expect(shown('0.4.6-beta', '0.5.0', 'stable'), ['v0.5.0', 'v0.4.7-beta']);
      // Coming from an alpha onto the beta channel.
      expect(shown('0.4.7-alpha', '0.4.7-beta', 'beta'), ['v0.4.7-beta']);
    });

    test('dev builds show everything like alpha', () {
      expect(shown('0.4.8-alpha', '0.4.8-alpha.3', 'dev'), [
        'v0.4.8-alpha.3',
        'v0.4.8-alpha.2',
      ]);
    });

    test(
      'newer than stored but no bundled notes in between: store silently',
      () {
        expect(shown('0.4.7-alpha.2', '0.4.7-alpha.3', 'alpha'), ['<store>']);
        // Only alpha notes in between, on the beta channel.
        expect(shown('0.4.7-beta', '0.4.8-beta', 'beta'), ['<store>']);
      },
    );
  });

  test('selectReleaseNotes without a lower bound', () {
    expect(
      tags(selectReleaseNotes(all, upTo: v('0.4.7-beta'), channel: 'beta')),
      ['v0.4.7-beta', 'v0.4.6-beta'],
    );
    expect(
      selectReleaseNotes(all, upTo: v('0.4.6-alpha'), channel: 'alpha').length,
      1,
    );
  });

  group('resolveCurrentRelease', () {
    String? cur(String tag, String? app, String channel) =>
        resolveCurrentRelease(
          tag: tag,
          appVersion: app,
          channel: channel,
          all: all,
        )?.toString();

    test('the baked-in tag wins', () {
      expect(cur('v0.4.8-alpha.2', '0.4.8', 'alpha'), '0.4.8-alpha.2');
      expect(cur('v0.4.8-alpha', '0.4.8', 'alpha'), '0.4.8-alpha.1');
      expect(cur('v0.4.7-beta', null, 'beta'), '0.4.7-beta');
    });

    test('without a tag: version name + channel', () {
      expect(cur('', '0.5.0', 'stable'), '0.5.0');
      expect(cur('', '0.4.9', 'beta'), '0.4.9-beta');
      // Alpha/dev: newest bundled release of that X.Y.Z.
      expect(cur('', '0.4.8', 'alpha'), '0.4.8-alpha.3');
      expect(cur('', '0.4.8', 'dev'), '0.4.8-alpha.3');
      expect(cur('', '0.4.6', 'dev'), '0.4.6-beta');
      expect(cur('', '0.6.0', 'alpha'), '0.6.0-alpha.1');
    });

    test('nothing parsable: null', () {
      expect(cur('', null, 'alpha'), isNull);
      expect(cur('', 'abc', 'stable'), isNull);
    });
  });

  test('parseReleaseIndex sorts newest first and skips broken entries', () {
    final json = jsonEncode({
      'releases': [
        {'tag': 'v0.4.7-beta', 'file': 'v0.4.7-beta.md'},
        {'tag': 'v0.4.8-alpha', 'file': 'v0.4.8-alpha.md'},
        {'tag': 'nope', 'file': 'x.md'},
        {'tag': 'v1.0.0'},
        'junk',
      ],
    });
    final idx = parseReleaseIndex(json);
    expect(tags(idx), ['v0.4.8-alpha', 'v0.4.7-beta']);
    expect(idx.first.assetPath, 'assets/release_notes/v0.4.8-alpha.md');
    expect(parseReleaseIndex('not json'), isEmpty);
    expect(parseReleaseIndex('[]'), isEmpty);
  });

  test('releaseNoteBody drops the intro heading and Install sections', () {
    const md = '''
## New in this release

### New
- A thing

## Install

**Android:** download the `.apk`.

## Known issues
- Bugs
''';
    expect(
      releaseNoteBody(md),
      '### New\n- A thing\n\n## Known issues\n- Bugs',
    );
  });
}
