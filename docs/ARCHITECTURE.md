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
- Clean-room rewrite: don't copy code from BetterUntis. The project is licensed under GPLv3 (it was MIT up to 0.3.x).

## Versioning
`pubspec.yaml` `version: X.Y.Z+N` is the single source of truth: X.Y.Z becomes
the app's version name and N the Android versionCode / iOS build number.
- Every commit bumps only the build number (`N`), so unreleased work doesn't use up version numbers.
- Every release build bumps the patch version (`Z`) by 1 and is tagged. `N` keeps counting up and is never reset.
- CI only analyzes and tests; the app is built once, by the release workflow, when a tag is pushed.
- Minor (`Y`) and major (`X`) only change when explicitly decided.
- Release tags are `vX.Y.Z[-alpha|-beta|-rc]` and must match pubspec (the release workflow checks this).

## Notifications and background checks
Local only, no push and no server. lib/core/notifications.dart (settings per account, de-duplication, `ChangeChecker`), lib/core/change_sources.dart (timetable, messages), lib/app/notifications/ (system notifiers, state store, background task). What was already notified lives in `notification_state.json` (web: localStorage `bbu.notificationState`), separate from settings.json so the app and the background isolate don't overwrite each other.

Android: while any account has notifications on, a periodic WorkManager task (`bbu-change-check`, woken every 15 min, network required; Android may delay it in Doze / battery saver; it really checks every 15 min on school days from an hour before the earliest daily time until 18:00, else about every 45 min — `backgroundMinIntervalAt`) starts a background isolate (`notificationCallbackDispatcher` in lib/app/notifications/background_check_io.dart). It opens the same database, secure storage and settings as the app and runs the same `ChangeChecker`: refresh this and next week of "My timetable", then the inbox, with the stored credentials. Skipped if the app checked less than 10 minutes earlier; capped at 8 minutes. Turning notifications off everywhere cancels the task. iOS checks only on start and resume; the web app only while open (changes as a snackbar).

Daily summary and reminders (lib/core/daily_notifications.dart, `DailyPlanner`): at the user's time (per account, default 07:00) one notification with that day's changes and tests (school and own), and one "Coming up" with tests / homework N days ahead. Each check builds the next one and hands it to the OS as a scheduled notification (flutter_local_notifications `zonedSchedule`, an instant in UTC; Android exact alarm if allowed, else inexact), so it arrives on time even with the app closed, with what the last check knew. Before that time today's changes are recorded silently (they are in the summary); after it they are notified at once. Where nothing can be scheduled (web) or no check ran before the time, the first check up to 10 h later shows it. `notification_state.json` keeps per account the last day handed over (`daily`).
