# Teacher features (0.6.0, branch `teacher`)

## Wishes from teachers
<!-- Paste what the teacher asked for below, one bullet per wish, as written.
     Nothing here is planned until it is moved to "Planned" further down. -->

- **Homework** (Hausaufgaben) — requested 2026-11-12. See "Homework: what we know" below; the teacher's own details still to come.
- **Previous lesson topics** — told 2026-11-16: when entering the lesson topic, the topics of the last few lessons (of that course) are shown too. → Built (see "Built").
- **Class register entries** (Klassenbucheinträge) — told 2026-11-16: the screen where absences are entered (the class's pupils, with names and photos) also has a section "Klassenbucheinträge": see every entry of that class and create new ones. → Built, but only entries of your own recent lessons of the course (see "Built").
- **Class register in the menu** (Klassenbuch) — told 2026-11-16: besides tapping a lesson in "My timetable", the burger menu has "Klassenbuch": today's upcoming lessons and past lessons, filterable by whether absences and lesson topic are done. → Built as "Class register" in the drawer (see "Built").
- **Pupil photos** — told 2026-11-16: the pupil list shows photos next to the names (we only show names so far; how the server delivers photos is unknown).
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
- [x] **Absences & lesson topic per lesson** ("Abwesenheiten" + "Lehrstoff"): tap a lesson in your own timetable → "Absences & lesson topic". Tap pupils to mark them absent, type the topic, save. Saving also confirms the attendance check. Double lessons are saved for both periods.
- [x] **Class register** (drawer, "Klassenbuch"; was "Open lessons"): **Today** — all of today's own lessons in time order, upcoming ones included (open them to prepare the topic) — and **Last 7 / 14 / 30 days**, newest first. Each lesson shows whether the attendance check and the topic are done. Filter chips: All · Attendance missing · Topic missing · Done. Tap a lesson to fill it in; the list reloads afterwards.
- [x] **Previous topics**: below the topic field, the topics of the latest 5 earlier lessons of the same course (same lesson id, else same subject + class; from your own timetable, up to 6 weeks back), newest first with the date; the newest two show, "Show N more" for the rest. Tap one to copy it into the field. Loads after the screen is up (inline loading / error with Retry).
- [x] **Class register entries** (Klassenbucheinträge): a section under the pupils: "This lesson" and "Recent entries in this course" (from the earlier lessons loaded for the previous topics — there is no known call for all entries of a class, so entries other teachers made in their lessons are missing). "New entry": pupil or whole class, reason (master data `eventReasons`, optional), text. The server's error stays visible in the form.
- [x] Demo: log in with user `teacher` at the demo school to try it without a real account.

## To confirm with a real teacher account
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

## Ideas (not planned yet)
- Late arrival / leaving early (partial absence with times)
- Absence reason and note per pupil
- Notes for pupils / notes for teachers per lesson
- Seating plan / photos
- Excuse management for class teachers

## Planned
<!-- Wishes we agreed to build move here. -->
