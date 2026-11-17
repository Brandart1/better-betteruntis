## New in this release

### Changed
- Messages are displayed with a well-tested HTML library instead of the app's own parser: headings, tables and nested lists look right now. Images in messages still aren't loaded (privacy); their description is shown instead.
- "What's new" and release notes use a standard Markdown library.
- Two-factor login codes come from a standard TOTP library (same codes as before).
