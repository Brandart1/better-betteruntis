## New in this release

Teacher test build (branch `teacher`). Absences, lesson topic, previous topics and class register entries are confirmed with real teacher accounts. Room booking, exams, absence summaries and pupil photos are new and their server calls are still guesses — if something fails, please send the entries from the Debug screen.

### New
- Teachers: tap a lesson in your own timetable → **Absences & lesson topic**. Tap pupils to mark them absent, enter the lesson topic ("Lehrstoff", at the top with its own heading and whether it's entered) and save; this also confirms the attendance check. Double lessons are saved for both periods.
- Teachers: **Class register** in the menu: today's lessons (upcoming ones too) and your past lessons of the last 7, 14 or 30 days, with whether the attendance check and the topic are done; filter by "Attendance missing", "Topic missing" or "Done".
- Teachers: **Previous topics** under the topic field: the topics of the course's last lessons; tap one to copy it.
- Teachers: **Class register entries** (Klassenbucheinträge) in the lesson screen: the lesson's entries and recent ones of the course, and **New entry** (a pupil or the whole class, reason, text).
- Teachers: **pupil photos** next to the names in "Absences & lesson topic" (initials when there is none); long press a pupil for a larger photo, "Hide pupil photos" in the top bar. The photos come with the pupil list from WebUntis. Photos stay in memory only, nothing is saved or synced.
- Teachers: **Absence summary** ("Summary" in "Absences & lesson topic"): how often the pupils were absent in this lesson, in this subject or in all subjects — per pupil (tap one for their absences) or for the whole class, with excused / unexcused / open lessons and late arrivals. School year so far, or a range you choose.
- Teachers: lessons a **substitute** held for you open read-only, with "Entered by substitute …" and what they entered; the Class register lists them as "Substituted by …" instead of missing, and their topics show up under "Previous topics". Lessons you substituted in yourself can be filled in as usual.
- Teachers: **Book a room** on your own lessons: the rooms that are free during the whole lesson (double lessons too), searchable; tap one to book it, "Back to …" undoes a change. The timetable updates afterwards.
- Teachers: **Create exam** on a lesson (replaces "Mark as exam" for teachers): type (a list of the school's exam types), name, text, one or more periods of that day, room (free rooms only), classes and pupils. **Exams** in the menu lists your exams and has **New exam** (date, your subjects and classes, the matching periods).
- Teachers: **Add details** on your own lessons now saves the lesson info in WebUntis ("Info zur Stunde"), so pupils and colleagues see it too, instead of only on your device. Details you added before stay, marked "only on this device".
- Booking rooms, creating exams and saving lesson details are best guesses at the server calls and may fail at first — the error is shown, and the Debug screen then has what was sent and what the server answered; please send it.
- Web test version for teachers (no sync): https://bbu-teacher-alpha.brandart1.workers.dev
- Demo school: log in as `teacher` to try the teacher features.

### Changed
- Timetables show changes of the timetable's own class, teacher or room: e.g. a teacher sees who substitutes them in their own timetable, a room's timetable shows a lesson moved to another room, and lessons shared by several classes list all of them.
- Includes everything from v0.5.2-beta (web version, optional encrypted sync, "What's new", keyboard navigation, Android in-app updater, large-text fixes).
