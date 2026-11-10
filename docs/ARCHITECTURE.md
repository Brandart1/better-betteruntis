# Architecture

Flutter (Android, iOS, iPadOS). Riverpod for state and DI, go_router for navigation, drift (SQLite) for the cache, flutter_secure_storage for secrets, dio for HTTP.

```
lib/
  core/      models.dart, interfaces.dart, providers.dart   ← the contract between layers (no Flutter UI)
  api/       UntisApi impl: JSON-RPC, TOTP, tolerant JSON → models
  data/      drift DB, AccountRepository, TimetableRepository (cache-first), NameResolver
  ui/
    login/       welcome + school search, login form, QR scan, 2FA prompt
    accounts/    account switcher / management
    timetable/   week pager, grid, lesson detail sheet, day view
    shell/       app scaffold, drawer, router, theme
  dev/       fake implementations for UI development & demo mode
test/        mirrors lib/
docs/        API.md (protocol notes), FEATURES.md (parity checklist)
```

## Rules
- The UI depends only on `core/`. Never import `api/` or `data/` from `ui/`.
- Look names up in **all** master data, and fall back to inline names. Never hide a name because an entry is `active: false`. (This is the fix for BetterUntis' missing teachers; see `docs/API.md`.)
- Parse JSON tolerantly. Unknown enum values, missing fields or wrong types fall back to defaults instead of throwing.
- Accounts are independent: each has its own host, school, secret, master data and cache. One `UntisApi` instance serves all of them.
- Secrets live only in secure storage. Passwords are never stored.
- Clean-room rewrite: don't copy code from BetterUntis (GPL). The project is MIT licensed.

## Versioning
`pubspec.yaml` `version: X.Y.Z+N` is the single source of truth: X.Y.Z becomes
the app's version name and N the Android versionCode / iOS build number.
- Every commit bumps the version: patch (`Z`) plus build number (`N`).
- Releases with new features bump the minor version (`Y`).
- Release tags are `vX.Y.Z[-alpha|-beta|-rc]` and must match pubspec (the release workflow checks this).
