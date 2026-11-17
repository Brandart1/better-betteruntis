## New in this release

### Changed
- Messages are displayed with a well-tested HTML library instead of the app's own parser: headings, tables and nested lists look right now. Images in messages still aren't loaded (privacy); their description is shown instead.
- "What's new" and release notes use a standard Markdown library.
- Two-factor login codes come from a standard TOTP library (same codes as before).
- Android: the in-app updater now uses the ota_update library instead of the app's own installer code. It installs only downloads whose checksum matches. Android asks for "Install unknown apps" itself when needed.
- Alpha builds are now also offered newer alphas of the same version line, not only betas.

### Known issues
- Test build for the new updater: after Android's install screen the app can't tell whether the installation worked. If you cancel it, tap Close.
