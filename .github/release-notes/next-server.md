## New in this release

### New
- **Web version on Cloudflare:** the web version is now hosted for you at `https://better-betteruntis.brandart1.workers.dev`, so there is nothing to install or run. Alpha releases are available as a preview at `https://alpha-better-betteruntis.brandart1.workers.dev`.
- **Sync (optional):** sync your custom exams and lesson details between your phone, tablet and the web version (*Menu → Sync*). Sync is off until you turn it on; turning it off deletes everything stored on the server, while your devices keep their notes.
- **End-to-end encryption for sync (optional):** protect synced notes with a sync passphrase (and an optional recovery code). The server then only stores encrypted data it can't read.
- **What's new:** after an update, the app shows what changed since the version you used last (also when you skipped several releases). You can reread the notes anytime under *Menu → What's new*. They are built into the app, so this also works offline.

- **Get the app:** the web version's menu links to the Android and iOS apps.

### Fixed
- **Web version: logging in failed** with "Something went wrong" right after the password was accepted (the one-time code and the account id used number operations browsers don't support).

### Changed
- The self-hosting server (Docker image and `…-web-linux-x64.tar.gz`) has been removed. If you still want to host the web version yourself, use a 0.4.x release.
