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
