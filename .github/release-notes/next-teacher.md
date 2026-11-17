## New in this release

Teacher test build (branch `teacher`). Absences, lesson topic, previous topics and class register entries are confirmed with real teacher accounts. Room booking, exams, absence summaries and pupil photos are new and their server calls are still guesses — if something fails, please send the entries from the Debug screen.

### New
- Your own homework on a lesson, like your own exams; both also appear in the Info center marked “Custom”.
- Pupils and parents: the first time they open **Teachers** in the timetables menu, a notice asks them not to use teacher timetables to contact teachers in free periods and points to the office hours (once per device). Teacher accounts don't see it.
- Turning on sync checks for an existing sync first: you only confirm, or enter its passphrase.
- The login screen now says that BetterBetterUntis is independent and not affiliated with Untis GmbH.
- Teachers: tap a lesson in your own timetable → **Absences & lesson topic**. Tap pupils to mark them absent, enter the lesson topic ("Lehrstoff", at the top with its own heading and whether it's entered) and save; this also confirms the attendance check. Double lessons are saved for both periods.
- Teachers: **Class register** in the menu: today's lessons (upcoming ones too) and your past lessons of the last 7, 14 or 30 days, with whether the attendance check and the topic are done; filter by "Attendance missing", "Topic missing" or "Done".
- Teachers: **Previous topics** under the topic field: the topics of the course's last lessons; tap one to copy it.
- Teachers: **Class register entries** (Klassenbucheinträge) in the lesson screen: the lesson's entries and recent ones of the course, and **New entry** (a pupil or the whole class, reason, text).
- Teachers: **pupil photos** next to the names in "Absences & lesson topic" (initials when there is none); long press a pupil for a larger photo, "Hide pupil photos" in the top bar. The photos come with the pupil list from WebUntis. Photos stay in memory only, nothing is saved or synced.
- Teachers: **Absence summary** ("Summary" in "Absences & lesson topic"): how often the pupils were absent in this lesson, in this subject or in all subjects — per pupil (tap one for their absences) or for the whole class, with excused / unexcused / open lessons and late arrivals. School year so far, or a range you choose.
- Teachers: lessons a **substitute** held for you open read-only, with "Entered by substitute …" and what they entered; the Class register lists them as "Substituted by …" instead of missing, and their topics show up under "Previous topics". Lessons you substituted in yourself can be filled in as usual.
- Teachers: **rooms of your own lessons** in the lesson details: ⟳ replaces a room, × removes it, + adds another room — until the lesson starts. ⟳ and + list the rooms free during the whole lesson (double lessons too), the planned room first when it is free again. The timetable updates afterwards.
- Teachers: **Book a room** in the menu, without a lesson: date, from–to as times or lesson numbers, once, daily, weekly, every 2 weeks or every n days; only rooms free on every date are offered, and the booking is refused when you have a lesson then.
- **Free rooms** in Browse → Rooms: show only the rooms that are free during this lesson, the next lesson or a time you choose.
- Teachers: **Create exam** on a lesson (replaces "Mark as exam" for teachers): type (a list of the school's exam types), name, text, one or more periods of that day, room (free rooms only), classes and pupils. **Exams** in the menu lists your exams and has **New exam** (date, your subjects and classes, the matching periods).
- Teachers: **Add details** on your own lessons now saves the lesson info in WebUntis ("Info zur Stunde"), so pupils and colleagues see it too, instead of only on your device. Details you added before stay, marked "only on this device".
- Booking rooms, creating exams and saving lesson details are best guesses at the server calls and may fail at first — the error is shown, and the Debug screen then has what was sent and what the server answered; please send it.
- Teachers: lessons that **colleagues give in your classes and subjects** (their regular lessons and substitutions) now show faded in your timetable, with their name; tap one to see it (read-only). Lessons a substitute holds for you are faded too. Turn it off in Settings → "Colleagues' lessons of my classes".
- Teachers: a **supervision before the first lesson** (e.g. Gangaufsicht 7:40) now shows, also when another teacher's timetable couldn't be opened before; very short lessons show their name instead of a cut-off line.
- New **colours for supervisions and room bookings** (a booked room without a class) in Settings, with preview, fill or border.
- Teachers: **Create exam** and "Absences & lesson topic" are no longer offered for supervisions, an Aufsichtsstunde or anything else without a class; the exam editor doesn't pick them as periods either.
- Teachers: once a lesson has started (or is over), the room buttons (⟳ × +) and **Create exam** show greyed out instead of disappearing — the server seems to refuse both then. Try creating an exam on a future lesson.
- Teachers: **late arrival, leaving early, reason and note** per pupil in "Absences & lesson topic": the clock button next to a pupil sets the part of the lesson they were missing ("Arrived now" / "Left now" while the lesson runs, or any times), an absence reason and a note. Double lessons get the matching part in each period. Uses the official app's call for changing absences; if it fails, please send the Debug log.
- Teachers: lesson details now have **Notes for pupils** (the lesson info, as before) and **Notes for teachers**, which only teachers see and which you can edit right in the lesson sheet.
- Teachers: **Homework** in "Absences & lesson topic": add and edit the homework you give in a lesson (text, a remark only teachers see, due date — the next lesson of the course by default — and done). Homework can't be deleted in the app; remove it in WebUntis.
- Teachers: **Excuses** in the menu: the absences of your class for the last 14 days, a week, a month or the school year, filtered by open / not excused / excused; tap one to mark it excused or not excused with an excuse text.
- Web test version for teachers (no sync): https://bbu-teacher-alpha.brandart1.workers.dev
- Demo school: log in as `teacher` to try the teacher features.

### Fixed
- Teachers: changing a lesson's room back to the planned room now works (the app sent the planned room instead of the current one).

### Changed
- Timetables show changes of the timetable's own class, teacher or room: e.g. a teacher sees who substitutes them in their own timetable, a room's timetable shows a lesson moved to another room, and lessons shared by several classes list all of them.
- Includes everything from v0.5.2-beta (web version, optional encrypted sync, "What's new", keyboard navigation, Android in-app updater, large-text fixes).
