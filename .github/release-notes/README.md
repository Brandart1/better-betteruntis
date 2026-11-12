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

## Teacher branch (0.5.0)
- Branch `teacher` builds the 0.5.0 teacher alphas, tagged `v0.5.0-alpha.N`
  from that branch. Its changes go to `next-teacher.md` (a separate file, so
  merging `main` into `teacher` doesn't conflict); on an alpha build rename it
  to `v0.5.0-alpha.N.md` and start a fresh `next-teacher.md`.
- The `+build` number is shared with `main`: always one above the highest
  number used on either branch, so Android can update between both builds.
