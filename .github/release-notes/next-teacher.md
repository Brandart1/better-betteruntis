## New in this release

Teacher test build (branch `teacher`). Absences, lesson topic, previous topics and class register entries are confirmed with real teacher accounts. Room booking and creating exams are still guesses at the server calls (the official app can't do either); most other teacher calls now follow the official Untis app 6.8.1 — if something fails, please send the entries from the Debug screen.

### New
- With sync on, **favourite classes and teachers** sync too (from v0.5.9-beta), per WebUntis account.
- Absences (from v0.5.8-beta): each absence says **Whole day** or **Partial · n of m lessons**, from the timetable (cancelled lessons don't count), and **By subject** shows the attendance in each subject as a percentage with missed and unexcused lessons.
- **Favourite classes and teachers** in Browse timetables (from v0.5.7-beta): tap the star next to a class or teacher, or in the top bar of its timetable, and it is also shown at the top of its list under "Favourites" (it keeps its place in the list).
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
- Teachers: **My class** for class teachers: open absences of your class (excuse them right there), the pupils absent most often, recent class register entries, and links to Excuses, the class timetable and the absence summary.
- Teachers: **Substitution requests** in the menu: requests asking you to cover a colleague's lesson (subject, class, time, room, whom you'd replace, state); accept or decline the open ones. Your timetable is refreshed after accepting. If your school doesn't use online substitution planning, the screen says so.
- Teachers: **My absences** in the menu: your absences with the affected lessons and who substitutes them; **Report absence** with a reason, from–until and a note for your substitute. Remove a mistaken report in WebUntis for now.
- Web test version: saving excuses and notes for teachers works there too now (the web relay forwards those requests).
- **Messages**: write new messages, reply, see your sent messages with their read confirmations, confirm reading when asked, and revoke a sent message. Who you can write to depends on your school's settings. Attachments aren't supported yet.
- **Notifications** (Settings → Notifications, per account, off by default): substitutions, cancellations and room changes in your timetable for today and the next school days, new messages and (teachers) new substitution requests — tapping one opens Substitution requests. Android also checks in the background about every 45 minutes; iOS checks when you open the app; in the browser they show inside the app. Everything stays on your device.
- Web test version for teachers (no sync): https://bbu-teacher-alpha.brandart1.workers.dev
- Demo school: log in as `teacher` to try the teacher features.

### Fixed
- Web version: **reporting an absence** works (from v0.5.9-beta): the relay now carries the WebUntis website login, keeps nothing and logs nothing.
- Absences: "Partial · n of m lessons" no longer counts a lesson twice when the timetable lists it more than once at the same time (from v0.5.9-beta).
- Teachers: **Create exam** offers the school's own exam types again when the server gives them to the app, and then sends the type's id like the WebUntis website does (the server may refuse an exam with only a type name). Otherwise the types of existing exams are offered as before.
- Custom homework, exams and lesson notes: the hint under the text field (e.g. "Only for you, not sent to the school.") wraps onto a second line on small screens instead of being cut off with "…".
- Teachers: your own timetable shows the class (and room) of each lesson again instead of your own name.
- Teachers: removing the notes for pupils no longer removes the notes for teachers too.
- Teachers: if the school server refuses a request for its rate limit, it is repeated after a short wait, and the lesson screen asks for its data only once.
- The app is fast again: the request limit from the previous builds is gone, so every screen loads at full speed. Pupil photos also need fewer requests: after three photos in a row that don't load, the app stops asking for them.
- Teachers: the class register sends far fewer requests. Lessons read a moment ago (in the overview, the lesson, previous topics, homework) are reused for 2 minutes instead of asked for again, the overview no longer reloads its weeks each time you come back from a lesson, and pupil photos share one login and one pupil list instead of one per pupil. Saving, or pulling down in the Class register overview, always loads fresh.
- Teachers: "All subjects" in the absence summary explains that only the class teacher may see all of a class's absences, instead of "invalid user role".
- Teachers: creating an exam now sends what the WebUntis website sends.
- Teachers: changing a lesson's room back to the planned room now works (the app sent the planned room instead of the current one).

- Teachers: adding or removing a **room** of a lesson now uses the same call as the official Untis app (the whole room list is sent), so the change should no longer snap back after a while.
- Teachers: **class register entries** are now saved with the official app's call (one entry per pupil for the whole class), dated at the lesson.
- Teachers: **Absence summary → All subjects** now loads the class's absences the way the official app does.
- Teachers: **pupil photos** come from the school's pupil list only, without trying other addresses first.
- Teachers: **Create exam**: type the exam type freely or tap one your school already uses (the app guessed a type list the server doesn't have).
- **Messages**: the list of whom you may write to, recipient groups and the search in custom filters now read the server's real field names (groups were sent without their id before).
- Teachers: **Report absence** now sends the school like the official app.

### Changed
- Messages are displayed with a well-tested HTML library instead of the app's own parser: headings, tables and nested lists look right now. Images in messages still aren't loaded (privacy); their description is shown instead.
- "What's new" and release notes use a standard Markdown library; two-factor login codes come from a standard TOTP library (same codes as before).
- Android: in-app updates are much faster (ota_update library instead of own installer code). Only downloads with a matching checksum get installed; Android asks for "Install unknown apps" itself when needed. Alpha builds are also offered newer alphas of their own version line.
- The version info at the bottom of the menu shows the alpha number ("alpha.3" instead of "alpha").
- Teachers: **Substitution requests** and **My absences** show only when your school offers them, as in the official app (WebUntis decides); the Settings switch “Online substitution planning” is gone. Notifications for requests follow that too.
- Timetables show changes of the timetable's own class, teacher or room: e.g. a teacher sees who substitutes them in their own timetable, a room's timetable shows a lesson moved to another room, and lessons shared by several classes list all of them.
- Includes everything from v0.5.2-beta (web version, optional encrypted sync, "What's new", keyboard navigation, Android in-app updater, large-text fixes).
