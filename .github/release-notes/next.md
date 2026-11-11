## New in this release

### New
- **Version number** at the bottom of the menu (e.g. "Version 0.4.5 (21) · beta").
- **Update check:** when the app starts and a newer release is out, a popup shows the link to the latest release on GitHub. Nothing is sent except a request to GitHub; offline, the check is skipped silently.

### Behind the scenes
- Automatic checks after each change now only run the tests; the app is built once per release. This halves the build minutes per release.
- Each release now also checks that the self-hosting Docker image still builds.
- Release notes now list every change since the previous release.
