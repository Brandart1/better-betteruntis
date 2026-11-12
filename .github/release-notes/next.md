## New in this release

### New
- **ID Austria login help:** on the login page, tap "My school requires parents' accounts to log in with ID Austria" for step-by-step instructions: log in to bildung.gv.at with ID Austria, open WebUntis, show the QR code under your profile → "Freigaben" (Sharing) → "Zugriff über Untis Mobile", and scan it. The scanner opens straight from that page.

### Fixed
- ID Austria parent accounts work through the QR code, so they're no longer a known issue.

### Changed
- **Reporting absences:** the app now opens a WebUntis web session for it, like the browser does, with the same security token (CSRF) and headers. Your school's server didn't accept the app's normal sign-in for this. Still being tested.

### Known issues
- **Reporting absences** (parent accounts) doesn't work yet.
