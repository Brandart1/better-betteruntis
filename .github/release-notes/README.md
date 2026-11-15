# Release notes

- `next.md` collects every user-visible change, fix and addition since the
  last release. Add to it with every change that gets pushed.
- When building release `vX.Y.Z-beta`, rename `next.md` to `vX.Y.Z-beta.md`,
  check it against `git log <previous tag>..HEAD`, and start a fresh `next.md`.
  The release workflow refuses to build a tag without a notes file that has a
  `## New in this release` section.
- Sections under it as needed: `### New`, `### Improved`, `### Fixed`,
  `### Changed`, `### Known issues`, `### Behind the scenes`.
- The install instructions (`default.md`) are appended automatically.

## In the app ("What's new")

The app bundles the notes of every released version (tag-named files only:
`vX.Y.Z.md`, `vX.Y.Z-beta.md`, `vX.Y.Z-alpha[.N].md`; not `next*.md`,
`default.md` or this README). Beta and stable builds show the ones a user
missed after an update in a dialog (never alpha notes); alpha and dev builds
never show that dialog and don't record the version, so a later beta still
shows everything since the last beta/stable version opened. Every build has
a "What's new" entry in the menu. Asset bundles can't read this
dot-directory reliably, so the notes are copied to `assets/release_notes/`
(with an `index.json`):

    dart run tool/sync_release_notes.dart

Run it whenever a release notes file is added or changed (e.g. right after
renaming `next.md`) and commit `assets/release_notes/` together with the notes.
`test/app/release_notes_bundle_test.dart` fails while the copy is stale, and
the release workflow regenerates it before building. Never edit the copies.

In the app, `## New in this release` and `## Install` sections are left out;
headings, lists, **bold**, *italic*, `code` and links are rendered. In alpha
builds the menu entry lists alpha, beta and stable notes (alpha notes are
only visible there); beta and stable builds skip alpha notes everywhere, so a
beta's notes must cover everything since the previous beta.
