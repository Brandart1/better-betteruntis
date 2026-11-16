# Teacher features (0.6.0, branch `teacher`)

## Wishes from teachers
<!-- Paste what the teacher asked for below, one bullet per wish, as written.
     Nothing here is planned until it is moved to "Planned" further down. -->

- **Homework** (Hausaufgaben) — requested 2026-11-12. See "Homework: what we know" below; the teacher's own details still to come.
- **Previous lesson topics** — told 2026-11-16: when entering the lesson topic, the topics of the last few lessons (of that course) are shown too. → Built (see "Built").
- **Class register entries** (Klassenbucheinträge) — told 2026-11-16: the screen where absences are entered (the class's pupils, with names and photos) also has a section "Klassenbucheinträge": see every entry of that class and create new ones. → Built, but only entries of your own recent lessons of the course (see "Built").
- **Class register in the menu** (Klassenbuch) — told 2026-11-16: besides tapping a lesson in "My timetable", the burger menu has "Klassenbuch": today's upcoming lessons and past lessons, filterable by whether absences and lesson topic are done. → Built as "Class register" in the drawer (see "Built").
- **Pupil photos** — told 2026-11-16: the pupil list shows photos next to the names (we only show names so far; how the server delivers photos is unknown). → Built on a guess (see "Built" and docs/API.md "Pupil photos (assumed)").
- **Absence summaries** — told 2026-11-16: absences per pupil or for the whole class, for this lesson, the subject total and the total over all subjects. → Built (see "Built"); the all-subjects source is a guess.
- **Substitutions** — told 2026-11-16: when a substitute held my lesson, I want to see the absences and topic they entered. → Built (see "Built").
- **Room booking** (Räume buchen) — told 2026-11-16: book a room (e.g. the IT room) for one of your lessons. → Built (see "Built").
- **Exam creation** — told 2026-11-16: a real tool to create exams (type, name, room, several periods, classes / pupils) instead of "Mark as exam"; plus a central exam menu (own exams, "New exam" with date, own subjects, their classes and the matching periods). → Built (see "Built").
- **Parent-teacher day** (Elternsprechtag) — told 2026-11-16, **later**: teachers offer time slots for the upcoming Elternsprechtag; rather complicated, details after the next talk with the teacher (Wednesday 2026-11-18). Parents then book slots in their WebUntis — also a task for later (parent side, branch `main`).

## Homework: what we know (2026-11-12)
Sources: a school's teacher guide (EPF Luxembourg, "Hausaufgabe 2023 Lehrer", with screenshots of WebUntis and the Untis Mobile iOS app) and the Untis help center ("Untis Mobile – Funktionen für Lehrkräfte", "Rechte im Modul Klassenbuch → Hausaufgabe"). Not yet confirmed by our teacher.

**Fields** (same in browser and app):
| Field | Notes |
|---|---|
| Text ("Hausaufgaben") | multi-line, what pupils see |
| Remark ("Bemerkung") | only teachers see it ("nicht sichtbar für Schüler*innen und Eltern") |
| Assigned date ("Aufgabedatum" / "Aufgegeben am") | the lesson's date, set automatically |
| Due date ("Fälligkeitsdatum") | date picker; days on which this course has lessons are highlighted (a hint, not a rule) |
| Done ("Erledigt") | toggle, pupils see it |
| Attachment ("Anhang") | browser only in the screenshots (OneDrive) — skip for now |

**Where:**
- Untis Mobile: tap a lesson → lesson details list → "Hausaufgaben (count)" → list → new / edit. The edit screen has a ✓ (save) at the top and a delete button at the bottom.
- WebUntis browser: "Unterricht → Mein Unterricht → Termine" or the "Hausübungen" column of "Tagesunterricht Lehrer*innen" → dialog per course ("Hausaufgaben – His – Hugo") listing existing homework plus "Neue Hausaufgabe".
- Homework belongs to the **course (Unterricht / lessonId)**, given in one lesson and due on a later date.
- Right: part of the "Klassenbuch" right; teachers who have the class register have it.

**Plan for our app:** a "Homework" section in the "Absences & lesson topic" screen: list the course's homework given in this lesson, add / edit (text, remark, due date — default the next lesson of the same course, done toggle) / delete.

**Still unknown:** the server call to create / edit / delete homework (reading already works: `homeWorks` on lessons, `getHomeWork2017`). Needs a capture from a teacher account (Debug screen of an alpha, or a browser F12 capture while adding homework in WebUntis).

**Open questions for the teacher:**
- Is the due date always a later lesson of the same course?
- Are remark, "done" or attachments used at all?

## Reference: Untis Mobile lesson details for teachers
From the guide's app screenshot (iOS), the official app's lesson menu is, top to bottom: online toggle · Notes for pupils · Notes for teachers · Lesson topic (✓ when entered, preview of the text) · Pupils (absent count, ✓ when the check is done) · Class register entries (count) · Homework (count) · Create messenger group. Worth copying as one list instead of our single button once more features exist.

Untis' feature list for teachers with the class register module ("WebUntis Klassenbuch"):
- Absences per lesson or day; late arrivals (automatic by time or entered manually); absence reason; free text; list of present/absent pupils per lesson; lesson details show whether the attendance check is done
- Lesson topic, including a list of the course's previous topics
- Homework
- View class duties (Klassendienste) and exemptions (Befreiungen)
- Offline mode
- Class register entries for the whole class, single pupils or a selection
- Class teachers: overview of their class(es) — all absences, edit excuse status, all class register entries, time filter
Basic package (no class register needed): enter notes for pupils ("Info zur Stunde") and notes for teachers, link a video conference to a lesson.

## Built (0.6.0 alphas)
- [x] **Lesson details on the server** — wish 2026-11-16 ("details added should be global, just like the exam thing"): for teachers, "Add details" in the lesson sheet of an own lesson sets the lesson info everyone sees ("Info zur Stunde", `submitPeriodInfo2017`) instead of a note on the device. Old device notes still show, marked "only on this device".
- [x] **Absences & lesson topic per lesson** ("Abwesenheiten" + "Lehrstoff"): tap a lesson in your own timetable → "Absences & lesson topic". Tap pupils to mark them absent, type the topic, save. Saving also confirms the attendance check. Double lessons are saved for both periods.
- [x] **Class register** (drawer, "Klassenbuch"; was "Open lessons"): **Today** — all of today's own lessons in time order, upcoming ones included (open them to prepare the topic) — and **Last 7 / 14 / 30 days**, newest first. Each lesson shows whether the attendance check and the topic are done. Filter chips: All · Attendance missing · Topic missing · Done. Tap a lesson to fill it in; the list reloads afterwards.
- [x] **Previous topics**: below the topic field, the topics of the latest 5 earlier lessons of the same course (same lesson id, else same subject + class; from your own timetable, up to 6 weeks back), newest first with the date; the newest two show, "Show N more" for the rest. Tap one to copy it into the field. Loads after the screen is up (inline loading / error with Retry).
- [x] **Class register entries** (Klassenbucheinträge): a section under the pupils: "This lesson" and "Recent entries in this course" (from the earlier lessons loaded for the previous topics — there is no known call for all entries of a class, so entries other teachers made in their lessons are missing). "New entry": pupil or whole class, reason (master data `eventReasons`, optional), text. The server's error stays visible in the form.
- [x] **Pupil photos**: in "Absences & lesson topic" each pupil shows their photo with a small present / absent badge, or their initials when there is none; long press a pupil to see the photo larger. "Hide pupil photos" in the app bar (stored on the device, default on). Photos are kept in memory for the session only (not on disk, not synced). Where the server has them is a guess (docs/API.md "Pupil photos (assumed)"); the demo teacher shows generated placeholders.
- [x] **Absence summary**: "Summary" next to "Absences" in "Absences & lesson topic". Scope **Lesson · Subject · All subjects**, grouping **Per pupil · Whole class**. Counts: absent lessons, excused / unexcused / open (no excuse decided), late arrivals (absent from the start but not until the end of a lesson; they don't count as absent lessons), pupils with absences. Per pupil sorted by name (pupils without absences too), tap one for their absences. Period: the school year so far (master data `schoolyears`, else since 1 September), or "Change" for a custom range. *Lesson*: the opened lesson block. *Subject*: every lesson of the course (same lesson id, else same subject + classes) in your own timetable in the range — lessons a substitute held included — read with getPeriodData2017 (at most 45 weeks; progress shown). *All subjects*: the class absence list of the lesson's class(es) (assumed call, see docs/API.md "Absence summaries (teachers)"), only the lesson's pupils, lessons counted from the time grid (approximate). Errors show with Retry.
- [x] **Substitutions**: a lesson of yours that a substitute held (your name struck through in your timetable) opens "Absences & lesson topic" **read-only**, with "Entered by substitute <name>": no saving, no new entries, pupils can't be switched (the repository refuses too). Lessons you substituted in for someone else are fully editable. The Class register shows such lessons as "Substituted by X" with the topic and number absent they entered (or "not visible to you" when the server doesn't share them); they never count as missing and only appear under "All". "Previous topics" include topics a substitute entered in the course (marked "· substitute X"). getPeriodData2017 for substituted lessons is asked separately, so a refusal there doesn't break the rest. Demo: Wednesdays' 2nd lesson (Mathematik) is held by Jonas Schmidt.
- [x] **Book a room**: lesson sheet of an own lesson → "Book a room": the rooms the server lists as free for the whole block (double lessons included; getRoomChangeData2017, else getAvailableRooms2017), searchable by name; tap one, confirm, and the room is changed (submitRoomChange2017). The server's errors stay in the screen; on success a message shows and the own timetable week is refreshed. A changed room offers "Back to <planned room>" (our way to cancel a booking — there is no cancel call). Demo: rooms EDV1 / R110 / TH are free (the gym not on Mondays).
- [x] **Create exam** (teachers with the class register; pupils and parents keep "Mark as exam"): "Create exam" on a lesson opens the exam editor pre-filled from the lesson: exam type (master data `examTypes`, else free text), name, text, date, subject, classes (chips), periods (chips of the day's time-grid units; tap to extend / shrink the consecutive range), room (the free rooms for that time, the lesson's room first), pupils (all, or a selection from the lesson's pupils). Sent to the server (assumed call); the server's error stays visible. Demo: the exam shows in the timetable and the exam list.
- [x] **Exams** (drawer, teachers): the own exams (upcoming and past, like the Info center tab) and "New exam": date, subject (only subjects from your own timetable, 2 weeks back to 3 ahead), the classes you teach it in, periods defaulting to your lessons of that subject and class on that date.
- [x] Demo: log in with user `teacher` at the demo school to try it without a real account.

## To confirm with a real teacher account
- [ ] Lesson details: `submitPeriodInfo2017` saves, the text shows in WebUntis/Untis Mobile as "Info zur Stunde", and an empty text removes it
- [ ] Pupils and existing absences load (getPeriodData2017)
- [ ] Marking absent / present again works
- [ ] Lesson topic is saved and shows up in WebUntis
- [ ] Attendance check counts as done in WebUntis
- [ ] Previous topics: same course is found (does `lessonId` stay the same across weeks?) and the topics match WebUntis
- [ ] getPeriodData2017 contains class register entries — under which key and with which fields (Debug log)
- [ ] `eventReasons` in the master data (names shown in "New entry")
- [ ] Creating an entry: does `createClassRegEvent2017` exist, and with which params? (send the Debug log with `createClassRegEvent2017 request body` and the answer)
- [ ] Is there a call for all entries of a class (to show entries of other teachers' lessons)?
- [ ] Class register overview (missing attendance / topic) matches WebUntis' list of open class register entries

- [ ] Pupil photos: which keys do the pupils in getPeriodData2017 carry (Debug log `getPeriodData2017 referencedStudents keys`)? Is one a photo URL?
- [ ] Pupil photos: does any guessed endpoint answer with an image (Debug log `pupil photo probe #N [HTTP …]`)? If not: a browser F12 capture of the photo request in WebUntis' class register (URL and response type only)
- [ ] Pupil photos on the web alpha: does the bearer token suffice (the relay sends no cookies)?

- [ ] Absence summaries, all subjects: does `GET /WebUntis/api/classreg/absences/students?…&studentId=-1&klasseId=<id>` answer for a teacher (Debug log `REST classreg absences/students klasseId=…`), and do the entries carry `studentId`? Else does the fallback getStudentAbsences2017 with `klasseId` work? Only class teachers may be allowed to see a class's absences.
- [ ] Absence summaries: does getPeriodData2017 send an excuse status per absence (`excused`, `excuseStatusId`, `excuse{…}`)? Without it every absence counts as "open". Is there a separate late-arrival flag?
- [ ] Substitutions: does a lesson a substitute held appear in the original teacher's timetable (teacher element `orgId` = own id, `id` = the substitute) and is it **not** flagged CANCELLED? Does getPeriodData2017 return its data to the original teacher?
- [ ] Room booking: do getRoomChangeData2017 / submitRoomChange2017 answer for the teacher (Debug log `… request body` and the answers)? Is `orgRoomId` the planned room (we send the planned one) or the current one? Does "Back to …" undo a booking in WebUntis?
- [ ] Room booking: does the school allow teachers to change rooms (`errors` with a right missing)? Is "booking" for the teacher really a room change of the lesson, or do they mean WebUntis' separate room reservations (Raumreservierung, not in the Untis Mobile API)?
- [ ] Exams: master data key for exam types (`examTypes`?) — check the getUserData2017 response in the Debug log
- [ ] Exams: which endpoint does WebUntis' browser use to create an exam (F12 capture of "Prüfung anlegen": URL, method, JSON body)? Our guess `POST /WebUntis/api/exams` (then `api/classreg/exams`), body in Debug log `REST exams request body`
- [ ] Exams: does a created exam show in the timetable (period `exam`) and in getExams2017 for teacher / class / pupils?
- [ ] Exams menu: are the subjects from the own timetable the right "authorised" ones, or is there a server list of a teacher's lessons (Unterrichte)?
- [ ] Is "subject total" what the teacher means (only this course), or all lessons of this subject in the class (also other teachers')?

## Ideas (not planned yet)
- Late arrival / leaving early (partial absence with times)
- Absence reason and note per pupil
- Notes for pupils / notes for teachers per lesson
- Seating plan
- Excuse management for class teachers

## Planned
<!-- Wishes we agreed to build move here. -->
