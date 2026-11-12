# Teacher features (0.5.0, branch `teacher`)

## Wishes from teachers
<!-- Paste what the teacher asked for below, one bullet per wish, as written.
     Nothing here is planned until it is moved to "Planned" further down. -->

- **Homework** (Hausaufgaben) — requested 2026-11-12. See "Homework: what we know" below; the teacher's own details still to come.

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

## Built (0.5.0 alphas)
- [x] **Absences & lesson topic per lesson** ("Abwesenheiten" + "Lehrstoff"): tap a lesson in your own timetable → "Absences & lesson topic". Tap pupils to mark them absent, type the topic, save. Saving also confirms the attendance check. Double lessons are saved for both periods.
- [x] **Open lessons** (drawer): past lessons of the last 7 / 14 / 30 days that still miss the attendance check or the topic; tap one to fill it in.
- [x] Demo: log in with user `teacher` at the demo school to try it without a real account.

## To confirm with a real teacher account
- [ ] Pupils and existing absences load (getPeriodData2017)
- [ ] Marking absent / present again works
- [ ] Lesson topic is saved and shows up in WebUntis
- [ ] Attendance check counts as done in WebUntis
- [ ] Open lessons matches WebUntis' list of open class register entries

## Ideas (not planned yet)
- Late arrival / leaving early (partial absence with times)
- Absence reason and note per pupil
- List of the course's previous lesson topics
- Notes for pupils / notes for teachers per lesson
- Class register events (Klassenbucheinträge / remarks)
- Seating plan / photos
- Excuse management for class teachers

## Planned
<!-- Wishes we agreed to build move here. -->
