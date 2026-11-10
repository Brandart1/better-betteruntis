# Feature parity checklist

Behavioral spec for the clean-room rewrite. Written from observing what BetterUntis does — no code is taken from it.
Legend: `[ ]` todo · `[~]` partial · `[x]` done · **P** = polish / beyond parity.

## Login & accounts
- [ ] Welcome screen with school search (name or address) → results list → prefilled login form
- [ ] QR code login / `untis://setschool?...` deep link (school, user, key, anonymous, apiUrl, skipAppSecret)
- [ ] Manual input: profile name, school name/ID, username, password/key, anonymous toggle
- [ ] Advanced: custom server URL, proxy
- [ ] Demo / "try it out" profile
- [ ] Validation + friendly error messages
- [ ] Anonymous profiles: prompt to choose a personal timetable element
- [ ] Multi-account: switch, add, edit, delete (with confirm); per-profile settings; multiple schools at once
- [ ] Credentials in secure storage (Keychain / Android Keystore)

## Timetable
- [ ] Horizontally paged week view; optional fling and snap-to-day
- [ ] Days to display (default = school week), custom week range
- [ ] Time grid from school; hide timestamps; hour range; reset lesson numbering
- [ ] Pinch zoom with persisted zoom level
- [ ] Pull to refresh + "last refreshed" label; cached-first, offline capable
- [ ] Jump to date / week picker
- [ ] Now indicator; past-day tint
- [ ] Lesson states: regular / irregular / cancelled / exam (+ past variants); substitutions count as irregular; optional "different background = irregular"; hide cancelled; online flag
- [ ] School subject colors (optional)
- [ ] Holidays, breaks, merged multi-hour lessons, side-by-side overlapping lessons
- [ ] Item styling: padding, radius, centered, bold, font sizes, light text
- [ ] **Teachers always shown** (fix BetterUntis bug)
- [ ] **P** Tap a day header → full-screen single-day view

## Element browsing
- [ ] Drawer: personal timetable, browse classes/teachers/rooms/subjects (search + tabs), bookmarks (add/remove), info center, free rooms, settings
- [ ] Home-screen shortcut to an element (Android) / Quick Action (iOS) — **P**

## Lesson detail
- [ ] Pager across overlapping lessons; time, title + state suffix
- [ ] Chips for teachers/classes/rooms → open their timetable
- [ ] Lesson info text, online note, links, homework with due date, topic
- [ ] Teacher-only: edit topic, absence check — **P** (lower priority, student-first)

## Info center
- [ ] Messages of the day + inbox, attachments, clickable links
- [ ] Events: exams, homework
- [ ] Absences with filter (only unexcused, reverse, time range: school year / 7 / 14 / 30 / 90 days)
- [ ] Parents: report an absence for a child (reason, from/until, note); endpoint assumed, see API.md
- [ ] Office hours

## Free rooms
- [ ] Saved room list per profile; free for rest of day/week vs occupied, relative to a selectable hour

## Notifications & background
- [ ] Break notification: next lesson info (subject/room/teacher/class each None/Short/Long)
- [ ] Before-first-lesson notification (lead time, default 30 min); optional in multi-hour lessons
- [ ] Background refresh
- [ ] Auto-mute during lessons — Android only (iOS has no API; use Focus filter / skip)
- [ ] Widgets (BetterUntis never shipped them) — **P**

## Settings
- [ ] General: language, double-back-to-exit (Android), week display options
- [ ] Styling: all item colors, reset colors, theme color / dynamic color, dark mode auto/light/dark, OLED black
- [ ] Timetable options (see above)
- [ ] Notifications options
- [ ] About: version, repo, license (GPLv3), libraries
- [ ] Opt-in crash reporting (default **off**, unlike BetterUntis)
- [ ] **P** Backup/export & import of profiles + settings

## Localization
- [ ] English + German first; ARB-based so community translations are easy
