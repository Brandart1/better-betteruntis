<div align="center">

# BetterBetterUntis

**A fast, friendly WebUntis timetable app for Android, iOS, iPadOS and the web.**

[![CI](https://github.com/Brandart1/better-betteruntis/actions/workflows/ci.yml/badge.svg)](https://github.com/Brandart1/better-betteruntis/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Brandart1/better-betteruntis?include_prereleases&label=release)](https://github.com/Brandart1/better-betteruntis/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)

</div>

BetterBetterUntis is a clean-room rewrite inspired by
[BetterUntis](https://github.com/SapuSeven/BetterUntis). It shows your school
timetable faster, works offline, handles several schools at once and fixes
long-standing annoyances, like **teachers missing from student timetables**.

> [!NOTE]
> This is an early alpha. Expect rough edges, and please
> [open an issue](https://github.com/Brandart1/better-betteruntis/issues) when
> something looks wrong at your school.

## ✨ Features

**Timetable**
- Swipeable week view with merged double lessons, overlapping lessons side by side, holidays and a "now" line
- Tap a date to open that day full screen, then tap it again to go back to the week
- Cancelled lessons, substitutions and exams at a glance, with old → new teachers and rooms
- Cache-first and offline-capable: the timetable appears instantly, then refreshes
- Custom colours (presets, hue slider or hex code), text size and centred text

**Teachers and rooms, even when your school hides them**
- Teacher names are filled in from the WebUntis REST API when the classic API leaves them out
- Teacher and room timetables are rebuilt from every class timetable when the school doesn't publish them directly

**Accounts**
- Log in via school search, a QR code or manually
- Multiple accounts across different schools, switchable in one tap
- Credentials stay on your device (Keychain or Android Keystore)

**Info center**
- Messages of the day and inbox
- Homework and exams
- Absences
- Office hours

**Export**
- Export any timetable as **CSV**, **XLSX** or **PDF**
- Pick a specific week, or the *regular* timetable derived from the last few weeks

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

[MIT](LICENSE). BetterBetterUntis is an independent project. It is **not
affiliated with or endorsed by Untis GmbH**. "WebUntis" is a trademark of its
respective owner.
