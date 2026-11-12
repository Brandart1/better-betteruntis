# Teacher features (0.5.0, branch `teacher`)

## Wishes from teachers
<!-- Paste what the teacher asked for below, one bullet per wish, as written.
     Nothing here is planned until it is moved to "Planned" further down. -->

- **Homework** (Hausaufgaben) — requested 2026-11-12. Details on how the teacher gives homework are still to come (see "Homework: what we know" below).

## Homework: what we know (2026-11-12)
From school guides found online (not yet confirmed by our teacher):
- In WebUntis (browser) the teacher adds homework to a lesson/course, picks a **due date** (days on which that course has lessons are highlighted), writes the **text**, can add a **remark only teachers see**, and can **attach a file** (e.g. a OneDrive link).
- Homework can be set to **"done" (erledigt)**, in the browser and in the app; pupils see that.
- Pupils see a colour per homework: soon due, due later, overdue and not done, overdue and done.
- The screens differ by school and country, so some schools may not show all of this.

From the API side:
- Reading works already: lessons carry `homeWorks`, and `getHomeWork2017` lists homework with `startDate`, `endDate` (due), `text`, `remark`, `completed`.
- The method for **creating / editing / deleting** homework from the mobile app is **unknown**. No public source names it. Needs a capture from a teacher account (Debug screen, or a browser F12 capture while adding homework in WebUntis).

Open questions for the teacher:
- Is homework given per lesson (today's lesson) or per course for a later date?
- Is the due date always a later lesson of the same course?
- Are remarks, attachments or "done" used at all?
- Should homework sit next to the topic in the "Absences & lesson topic" screen?

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
- Class register events (Klassenbucheinträge / remarks)
- Seating plan / photos
- Excuse management for class teachers

## Planned
<!-- Wishes we agreed to build move here. -->
