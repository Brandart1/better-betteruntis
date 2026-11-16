## New in this release

Teacher test build (branch `teacher`). The class register calls haven't been confirmed against a real teacher account yet — if something fails, please send the entries from the Debug screen.

### New
- Teachers: tap a lesson in your own timetable → **Absences & lesson topic**. Tap pupils to mark them absent, enter the lesson topic ("Lehrstoff") and save; this also confirms the attendance check. Double lessons are saved for both periods.
- Teachers: **Class register** in the menu: today's lessons (upcoming ones too) and your past lessons of the last 7, 14 or 30 days, with whether the attendance check and the topic are done; filter by "Attendance missing", "Topic missing" or "Done".
- Teachers: **Previous topics** under the topic field: the topics of the course's last lessons; tap one to copy it.
- Teachers: **Class register entries** (Klassenbucheinträge) in the lesson screen: the lesson's entries and recent ones of the course, and **New entry** (a pupil or the whole class, reason, text). Creating entries is a guess at the server call and may fail until we've seen a real one — the Debug screen then has what was sent.
- Web test version for teachers (no sync): https://bbu-teacher-alpha.brandart1.workers.dev
- Demo school: log in as `teacher` to try the teacher features.

### Changed
- Includes everything from v0.5.1-beta (web version, optional encrypted sync, "What's new", keyboard navigation, Android in-app updater, large-text fixes).
