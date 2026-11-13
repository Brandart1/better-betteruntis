<div align="center">

<img src="assets/icon/icon.png" alt="App icon" width="112">

# BetterBetterUntis

**A fast, friendly WebUntis timetable app for Android, iOS, iPadOS and the web.**

[![CI](https://github.com/Brandart1/better-betteruntis/actions/workflows/ci.yml/badge.svg)](https://github.com/Brandart1/better-betteruntis/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Brandart1/better-betteruntis?include_prereleases&label=release)](https://github.com/Brandart1/better-betteruntis/releases)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)

</div>

BetterBetterUntis is a clean-room rewrite inspired by
[BetterUntis](https://github.com/SapuSeven/BetterUntis). It shows your school
timetable faster, works offline, handles several schools and children at once,
and fixes long-standing annoyances like **teachers missing from student
timetables**.

> [!NOTE]
> This is a beta. Most things work, but please
> [open an issue](https://github.com/Brandart1/better-betteruntis/issues) when
> something looks wrong at your school.

## 📸 Screenshots

<table>
  <tr>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/week.png" width="180" alt="Week view"><br><sub>Week view</sub></td>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/lesson.png" width="180" alt="Lesson details"><br><sub>Lesson details</sub></td>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/day.png" width="180" alt="Day view"><br><sub>Day view, read aloud</sub></td>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/info.png" width="180" alt="Info center"><br><sub>Homework</sub></td>
  </tr>
  <tr>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/contrast.png" width="180" alt="High contrast"><br><sub>High contrast*</sub></td>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/week-dark.png" width="180" alt="Dark mode"><br><sub>Dark mode</sub></td>
    <td width="25%" align="center" valign="top"><img src="docs/screenshots/settings.png" width="180" alt="Settings"><br><sub>Colors &amp; text</sub></td>
    <td width="25%" valign="top"></td>
  </tr>
</table>

<sub>Week view shows substitutions, exams and cancelled lessons. *Accessibility features are a work in progress. Demo data — made-up school and names. Regenerate with `tool/screenshots/update.sh`.</sub>

## ✨ Features

**Timetable**
- Swipeable week view with merged double lessons, overlapping lessons side by side, holidays and a "now" line
- Tap a date to open that day full screen, then tap it again to go back to the week
- Cancelled lessons, substitutions and exams at a glance, with old → new teachers and rooms
- Cache-first and offline-capable: the timetable appears instantly, then refreshes
- Tap a lesson for details. Every teacher, class and room in it opens its own timetable

**Teachers and rooms, even when your school hides them**
- Teacher names are filled in from the WebUntis REST API when the classic API leaves them out
- Teacher and room timetables are rebuilt from every class timetable when the school doesn't publish them directly
- Room timetables show teacher and class, and hide the class when the lesson moved away or was cancelled

**Make it yours**
- Colours for regular lessons, substitutions, cancellations and exams: presets, hue slider or hex code
- **Per-subject colours**, e.g. Maths always blue
- For each special state, pick **fill** (whole lesson coloured) or **border** (keeps the subject colour)
- Text size, bold subject and centred text

**Accounts**
- Log in via school search, a QR code or manually (schools that use **ID Austria** for parents: log in on the web and scan the WebUntis QR code; the app shows how)
- Multiple accounts across different schools, switchable in one tap
- **Parent accounts:** "My timetable" shows your child; switch between several children in the drawer
- Credentials stay on your device (Keychain, Android Keystore, or your browser on the web)

**Info center**
- Messages of the day and inbox
- Homework and exams
- Absences, and **report an absence** for your child as a parent
- Office hours of all teachers, A–Z, optionally only your class's

**Export**
- Export any timetable as **CSV**, **XLSX** or **PDF**, using your colours and text settings
- Pick a specific week, or the *regular* timetable derived from the last few weeks

**Web version**
- Self-host it on your homelab with Docker or a single binary. Your data stays in your browser

## 🐞 Known issues

- None known right now.

## 📲 Install

| Platform | How |
| --- | --- |
| **Android** | Download the `.apk` from the [latest release](https://github.com/Brandart1/better-betteruntis/releases) and install it. |
| **iOS / iPadOS** | The release contains an **unsigned** `.ipa`. Sign it yourself with [Sideloadly](https://sideloadly.io), [AltStore](https://altstore.io) or your own developer account. With a free Apple ID, apps have to be re-signed every 7 days. |
| **Web** | Self-host it, see below. |

### 🏠 Self-hosting the web app

Browsers can't talk to WebUntis directly, so the web build ships with a tiny
server. It serves the app and forwards requests to `*.webuntis.com`, and only there.
Your login data is stored in your browser, never on the server.

```sh
docker compose up -d   # then open http://localhost:8080
```

Put it behind HTTPS (Caddy, Traefik or nginx) and don't expose it publicly
without basic auth or a VPN. [docs/WEB.md](docs/WEB.md) covers configuration,
running without Docker, and security notes.

## 🛠️ Building from source

Requires Flutter 3.47+.

```sh
flutter pub get
flutter test
flutter run                                         # device or emulator
flutter build apk --release                         # Android
flutter build web --release --no-web-resources-cdn  # web (serve with server/)
```

iOS builds run on GitHub Actions macOS runners (see `.github/workflows/`), so
no Mac is needed.

## 📚 Docs

- [docs/FEATURES.md](docs/FEATURES.md): feature parity checklist
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is organised
- [docs/API.md](docs/API.md): notes on the WebUntis protocol
- [docs/WEB.md](docs/WEB.md): self-hosting the web version

## ⚖️ License & disclaimer

[GNU GPL v3](LICENSE). BetterBetterUntis is an independent project. It is **not
affiliated with or endorsed by Untis GmbH**. "WebUntis" is a trademark of its
respective owner.
