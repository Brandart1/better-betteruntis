## New in this release

### New
- **Android: update inside the app.** When a new beta or stable version is out, tap **Update now**: the app downloads it from GitHub, checks it and installs it. Android asks once to allow installing apps from BetterBetterUntis; on Android 12 and newer later updates can install without another tap. Alpha versions are never installed this way.

### Improved
- Timetables opened from **Browse timetables** (or a teacher, class or room) now have the menu button too; **My timetable** in the menu takes you back to your own timetable.
- Day view: the date in the top bar gets shorter on narrow screens ("17 Nov" instead of a cut-off "Tue, 1…").
- The README links to the web version at the top; screenshots are refreshed and show the menu button.

### Fixed
- Day view: with the menu open, the back button now closes the menu first instead of leaving the day view behind it.

### Changed
- **Public timetable logins (no username) can't use Sync.** Sync needs a personal WebUntis login; the Sync screen explains this, and any leftover sync state for such an account is removed from the device. The server refuses them too.
