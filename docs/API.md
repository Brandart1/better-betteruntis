# WebUntis internal API — working notes

This API isn't documented anywhere; these notes come from observing it. Treat everything here as best-effort and parse responses tolerantly.

## Hosts
- School search: `POST https://schoolsearch.webuntis.com/schoolquery2` (JSON-RPC).
- Server host:
  - Use the custom API URL if the user set one.
  - Otherwise use `mobileServiceUrl` when `useMobileServiceUrl{Android,Ios}` is true and the URL isn't blank.
  - Otherwise use `serverUrl`.
  - In every case keep only the host.
- JSON-RPC endpoint: `https://<host>/WebUntis/jsonrpc_intern.do?school=<loginName>`
- REST endpoint (needs a bearer token): `https://<host>/WebUntis/api/rest`
- Every request is a POST with JSON. Responses come back as `application/json` or `application/json-rpc`; accept both.

## JSON-RPC envelope
Request:

`{"id":"<client-id>","jsonrpc":"2.0","method":"<m>","params":[{...}]}`

The response contains either `result` or `error`. The error shape is `{code, message, data:{exceptionTypeName, message, serverTime}}`.

## Formats
| Kind | Example | Notes |
|---|---|---|
| Date | `2025-09-15` | |
| DateTime | `2025-09-15T08:00` | Optionally followed by `:ss` and/or `Z`. Local time, no zone. |
| Time | `T08:00` | Note the leading `T`. |
| Timestamp | `1731230000000` | Epoch milliseconds. |

## Auth
Every authenticated call puts this inside its params object:

`"auth":{"user":"<u>","otp":<int>,"clientTime":<ms>}`

- Anonymous login: `user:"#anonymous#"` and `otp:0`.
- `otp` is a TOTP (RFC 6238):
  - Key: Base32-decode the shared secret after uppercasing it, skipping any invalid characters.
  - Counter: `clientTime / 30000`, as 8 bytes big-endian.
  - HMAC-SHA1 over the counter, then dynamic truncation, `% 1e6`.
  - Send it as an integer, without zero-padding.
- `clientTime` must be the same timestamp used to compute the OTP. If the device clock is off, the server returns `-8524`.

## Login
1. `searchSchool`: send one of `{search}`, `{schoolid}` or `{schoolname}`. The result is `{schools:[{server, loginName, schoolId, displayName, address, serverUrl, mobileServiceUrl, useMobileServiceUrlAndroid, useMobileServiceUrlIos, tenantId}]}`. If several schools come back, pick the exact match on `schoolId` or `loginName`. `-6003` means too many results.
2. `getAppSharedSecret {userName, password, token?}` (no `auth`) returns the secret as a plain string.
   - On `-8519`, ask the user for a 2FA code and retry with `token`.
   - On any other error, treat the password as the secret. This is how QR codes with `key` work.
   - Store only the secret, never the password.
3. `getUserData2017 {elementId:0, deviceOs, deviceOsVersion, auth}` returns:
   - `masterData`: the full set.
   - `userData`: `elemId`, `elemType`, `displayName`, `schoolName`, `klassenIds`, `children`, `rights`. (`klassenIds` can be empty, also for students. `children`: see "Parent accounts".)
   - `settings`
   - `messengerSettings`

QR code format: `untis://setschool?school=&user=&key=`. Our extras are `anonymous`, `apiUrl` and `skipAppSecret`.

## Data methods
- `getTimetable2017 {id, type, startDate, endDate, masterDataTimestamp, timetableTimestamp:0, timetableTimestamps:[], auth}`
  - `type` is one of `CLASS`, `TEACHER`, `SUBJECT`, `ROOM`, `STUDENT`.
  - Returns `{timetable:{periods:[...]}, masterData:<delta since timestamp>}`.
  - Each period has:
    - `id`, `lessonId`, `startDateTime`, `endDateTime`
    - colors: `foreColor`, `backColor`, `innerForeColor`, `innerBackColor`
    - `text {lesson, substitution, info}`
    - `elements [{type, id, orgId}]`
    - `can []`, `is []` (REGULAR / IRREGULAR / CANCELLED / EXAM / …)
    - `homeWorks`, `exam`
    - `isOnlinePeriod`, `onlinePeriodLink`
    - `blockHash`
  - Elements:
    - `orgId` is the planned element. It defaults to `id` when missing.
    - `id != orgId` means a substitution.
    - `id == 0` means the element was removed.
- `getPeriodData2017 {ttIds, auth}` returns `{dataByTTId:{<id>:{topic, text, homeWorks, absences, …}}, referencedStudents}`.
- `getMessagesOfDay2017 {date, auth}` returns `{messages:[{id, subject, body(html), attachments}]}`.
- `getHomeWork2017` / `getExams2017 {id, type, startDate, endDate, auth}`
  - Homework returns `homeWorks` plus `lessonsById`.
  - Exams return `exams[{…subjectId, klasseIds, roomIds, teacherIds…}]`.
- `getStudentAbsences2017 {startDate, endDate, includeExcused, includeUnExcused, auth}`
  - Parent accounts additionally send `studentId: <child id>` (**assumed**, see below); if the server rejects that, the call is repeated once without it.
- `getOfficeHours2017 {klasseId, startDate, auth}` returns name strings directly (`displayNameTeacher`, `displayNameRooms`). See "Office hours" below for what is assumed.
- `getAuthToken {auth}` returns `{token}`, a JWT used as `Authorization: Bearer` for REST calls, e.g. `GET /view/v1/messages` (the inbox).
- Room finder: there is no dedicated method. Call `getTimetable2017` with `type:ROOM` for each saved room.

## Parent (legal guardian) accounts
Confirmed (user report): using a parent's own `userData.elemType`/`elemId` as a timetable makes `getTimetable2017` fail with "request.type is null", i.e. the parent element is not a timetable element. Our client never sends `getTimetable2017` (or homework/exams) with a type outside CLASS/TEACHER/SUBJECT/ROOM/STUDENT or with id ≤ 0; it fails early with a clear message.

Assumed (no real response seen yet):
- `userData.children` is a list like `[{id, displayName, klasseId?}]`. The parser also accepts `studentId`/`elemId`/`elementId`/`personId` for the id, `longName`/`name`/`firstName`+`lastName` for the name, `klasseId`/`klassenId`/`classId`/`klassenIds[0]`/`klasseIds[0]`/`klasse.id` for the class and an optional `type`.
- A child's timetable, homework and exams are requested with `type: STUDENT` and the child's id.
- `getStudentAbsences2017` takes `studentId` to pick the child. Unknown; if it is rejected we retry without it, which may return the parent's (empty) or all children's absences.
- `userData.elemType` for parents is something like `LEGAL_GUARDIAN` / `PARENT` (anything we don't know maps to `unknown`).

Client behaviour: "My timetable" is the own element when it is a timetable element (students, teachers — unchanged), else the selected child (first by default, switchable in the drawer, persisted per account), else a "no personal timetable" message pointing to Browse.

## Reporting absences (parents)
Parents report an absence for a child ("Abwesenheit melden") in the WebUntis web client; the school decides via rights whether that is allowed. No JSON-RPC method for this is known (`createImmediateAbsence2017` is the teacher's class-register call for one lesson, not this). We use the classic web endpoints instead.

Seen in public community notes on the WebUntis web client (not yet against a real response from our app):
- `GET /WebUntis/api/classreg/absences/meta` → `{data:{absenceReasons:[{id,name}], defaultAbsenceReason:{id}, defaultDate, defaultStartTime, defaultEndTime}}` (times as hhmm numbers, e.g. `750`).
- `GET /WebUntis/api/classreg/absences/students?startDate=yyyymmdd&endDate=yyyymmdd&studentId=<id>&excuseStatusId=-1` → `{data:{absences:[…], absenceReasons, excuseStatuses, showCreateAbsence, …}}`. `showCreateAbsence` is the school's "may report" flag for this user.
- `POST /WebUntis/api/classreg/absences/students/self` with JSON `{studentId, startDate, startTime, endDate, endTime, reasonId, text}`. Dates are yyyymmdd numbers, times hhmm numbers, `reasonId` -1 = none. Answer `{data:{result, conflicts:[…]}}`; saved only when `conflicts` is empty. Errors come as `{errors:[{code,title}]}`.
- The browser sends these with its session cookie plus `X-CSRF-TOKEN` and `Tenant-Id`.

Seen with real parent accounts (2026-11-12, two schools, password and QR login alike):
- The bearer token alone is **not** accepted: both GETs answer `302` to `/WebUntis/index.do` and the POST answers `403` with an HTML "WebUntis Access Denied" page.

Session (0.4.6+23, to be confirmed):
- We open a browser session the way the WebUntis JS library's secret login does: `POST jsonrpc_intern.do?school=<s>&m=getUserData2017&v=i2.2` with `{auth:{user, otp, clientTime}}`. Its `Set-Cookie` should carry `JSESSIONID`. All classic calls then send `Cookie: schoolname="_<base64 school>"; JSESSIONID=…` (plus any other cookies) and still the bearer token.
- Confirmed 2026-11-12: `getUserData2017` sets the cookies `JSESSIONID`, `schoolname` and `Tenant-Id`; with them `absences/meta` answers. `absences/students` and the POST still got the HTML "Access denied" while we also sent our bearer token and a wrong CSRF value.
- Then `GET /WebUntis/api/app/config` with that cookie. Its `data` has `csrfHeader` (the header **name**), `csrfToken` (the value) and `tenantId`. We send `<csrfHeader>: <csrfToken>` and `Tenant-Id`. An `XSRF-TOKEN` cookie is echoed as `X-XSRF-TOKEN`.
- What the browser sends on the POST (captured 2026-11-12): `Accept: application/json`, `Content-Type: application/json`, `X-CSRF-TOKEN`, `Tenant-Id`, `Origin: https://<host>`, `Referer: https://<host>/WebUntis/embedded.do?showSidebar=false`, `Cookie`, and **no** `Authorization`. With a session we send exactly these (0.4.6+24); the bearer token only when no session could be opened.
- The Debug log shows `web session: …` entries: cookie names received, the config's top-level keys and the key paths where CSRF / tenant were found (never values). A cached session that is redirected or refused is reopened once.
- Native apps only: on the web the browser hides `Set-Cookie` and our proxy drops cookies.
- If it still fails, the server answers with a redirect or a login page; our client then reports "The school's server didn't accept the app's sign-in for this function" (code `-8530`, internal).

Assumed (to be confirmed with a real parent account):
- **Delete** (captured from the browser 2026-11-12): `DELETE /WebUntis/api/classreg/absences/students` with JSON `{absenceIds:[<id>]}` and the same session headers as the POST. Answer `{data:{success:true}}`.
- The `absences/students` list entries (real answer 2026-11-12): `{id, startDate, endDate, startTime, endTime, createDate, lastUpdate (ms), createdUser, updatedUser, reasonId, reason, text, interruptions, canEdit, studentName, excuseStatus, isExcused, excuse:{id, text, excuseDate, excuseStatus, isExcused, userId, username}}`. `createdUser` is a teacher's short name (e.g. `Fch`) or the parent's login (an email). `canEdit` is true only while the parent may still change/delete it (seen: only their latest report). The ids match getStudentAbsences2017's; we also match by start/end as a fallback.
- For parents, `studentId` is the child's id from `userData.children`, and `.../students/self` is the right path (the web client uses the same absence module for students and parents).
- The meta field names above; every field is optional in our parser. If the meta call fails, reasons come from the `absences/students` answer, else from master data `absenceReasons` (shown with a notice).

Client behaviour: the Absences tab of parent accounts with children shows "Report absence". The form asks for the child (the selected one is the default), from/until (default: today, the whole school day from the time grid, else the server's default times, else 08:00 to 16:00), the reason and an optional note. If `showCreateAbsence` is false, the form says so and sending is disabled. HTTP 403 means no right. After a successful report every cached absence list of the account is dropped and reloaded.

## Class register (teachers)
Teacher accounts (`userData.elemType` TEACHER) get "Absences & lesson topic" for lessons of their own timetable, and "Class register" in the drawer (today's and past lessons with their attendance check / topic state). Built on branch `teacher` (0.6.0 alphas).

**All assumed** — no real teacher response seen yet. Method names and params follow how other Untis Mobile clients call the teacher API. The timetable period `id` is the `ttId`.
- `getPeriodData2017 {ttIds:[…], auth}` → `{dataByTTId:{"<ttId>":{ttId, absenceChecked, studentIds:[…], absences:[{id, studentId, startDateTime, endDateTime, absenceReasonId?, text?, excused?}], topic:{text}|"<text>", text, homeWorks, …}}, referencedStudents:[{id, firstName, lastName, klasseId?}]}`. The parser also accepts `lessonTopic`, `absencesChecked`, `students`, `displayName`/`name` for students.
- `submitLessonTopic {lessonTopic, ttId, auth}`
- `createImmediateAbsence2017 {periodId:<ttId>, studentId, startTime:"T08:00", endTime:"T08:45", auth}` — the whole lesson.
- `deleteAbsence2017 {absenceId, auth}`
- `submitAbsencesChecked2017 {ttIds:[…], auth}` — "attendance check done".
- Class register entries ("Klassenbucheinträge") are read from getPeriodData2017 per period: a list under `classRegEvents` (also accepted: `classregEvents`, `classRegEntries`, `events`), or one top-level list with a `ttId`/`periodId` per item. Per item (all keys guessed): id `id`/`eventId`; pupil `studentId`/`student{id, firstName, lastName}`/`studentIds:[one]`/`studentName` (none = the whole class); reason `eventReasonId`/`reasonId`/`classRegEventReasonId`/`eventReason{id, name|longName}`, or an inline name in `eventReasonName`/`reasonName`/`reason` (string); text `text`/`remark`/`description`/`comment`; date `dateTime`/`startDateTime`/`date`/`eventDate`/`createDate`/`createdAt` (ISO, yyyyMMdd or epoch ms; none = the lesson's start); author `teacherName`/`createdBy`/`creator`/`author`. Items with neither text nor reason are skipped.
- Reason names: master data `eventReasons` (`{id, name, longName, …}`, long name preferred) from the login's master data, else one `getUserData2017` call; kept for the session only (not persisted).
- `createClassRegEvent2017 {periodId:<ttId>, studentId?, eventReasonId?, text, auth}` — **method name and params are a guess** (modelled on `createImmediateAbsence2017`); `studentId` is left out for the whole class, `eventReasonId` when no reason is chosen. A double lesson gets one entry, in its first period. If the server answers e.g. -32601 "Method not found", the message and code are shown in the form, and the request body is in the Debug log as `createClassRegEvent2017 request body`.
- No class-wide "all entries of a class" call is known. The app shows the entries of the lesson itself plus those found in the earlier lessons of the same course that it loads for "Previous topics" (labelled "Recent entries in this course"): entries other teachers made in their own lessons are not visible.

Client behaviour: saving a lesson block (a double lesson = several ttIds) creates/deletes absences per period, then confirms the check for all, then sends the topic (only if changed) for each period. Request bodies of these writes (no credentials) are in the Debug log as `<method> request body`. The "Class register" overview loads the teacher's own weeks (fresh, else cached), keeps the not cancelled lessons (no break supervisions / office hours) from 7 / 14 / 30 days ago up to the end of today (today's upcoming ones included) and asks getPeriodData2017 for all of them in chunks of 40; lessons the server returns no data for are left out. Filtering (attendance / topic missing, done) happens in the app.

"Previous topics" (class register screen, loaded after the screen is up): the teacher's own timetable weeks, newest first, going back at most 6 weeks (cached weeks, else fetched; a week that fails is skipped, all failing is an error shown inline), stopping once 15 earlier lessons of the same course are found. Same course = same `lessonId`; if no earlier lesson has it, same subject(s) and class(es). Not cancelled, no break supervisions / office hours. getPeriodData2017 for those lessons (chunks of 40) gives the topics (the latest 5 with a topic; a topic repeated on the same day, e.g. a double lesson, once) and the entries.

### Pupil photos (assumed)
How WebUntis delivers pupil photos is **not known** (no capture yet; BetterUntis models `referencedStudents` as `{id, firstName, lastName}` only). The WebUntis REST API uses `imageUrl` for persons (`api/rest/view/v1/app/data`, messenger), so the app tries, per pupil of the class register screen:
1. A photo URL in the pupil object of getPeriodData2017 `referencedStudents`: keys `imageUrl`, `imageURL`, `image`, `photoUrl`, `photo`, `pictureUrl`, `picture`, `avatarUrl`, `portraitUrl` (a string, or `{url|href|src}`); only absolute http(s) URLs or server paths starting with `/` count. Fetched as is; the bearer token is sent only to the account's own host.
2. Otherwise guessed endpoints, in this order (`{id}` = student id): `GET /WebUntis/api/rest/view/v1/students/{id}/image`, `GET /WebUntis/api/portrait/students/{id}`, `GET /WebUntis/api/classreg/students/{id}/image`. The first one that answers with an image is kept for the session (per host and school); after 2 pupils for whom none did, the guesses are given up for the session (at most 6 extra requests).

Each GET sends `Accept: image/*` and the bearer token (`getAuthToken`); on 401 / 403 / 3xx it is repeated once with the web session headers (cookies; native only — on the web the browser can't send them). An answer counts as an image when it is HTTP 200 with `image/*`, or JPEG / PNG / GIF / WebP bytes with another non-text type. Redirects are not followed.

Debug log: `getPeriodData2017 referencedStudents keys` (`{count, keys, withImageUrl}`: the keys the pupil objects carry, no values) after every getPeriodData2017 call; `pupil photo probe #N [HTTP s]`, `pupil photo #N [HTTP s]` and `pupil photo (imageUrl) [HTTP s]` with `{url (ids replaced by <id>, no query), contentType, bytes, image, _redirectTo?}` — never the image bytes; `pupil photo: no source` when the guesses are given up.

Client: photos are kept in memory per account and pupil for the session (also "has no photo"; failed loads are retried next time), never on disk, never synced; at most 4 load at once. Pupils without a photo (or one that can't be decoded) show their initials. "Hide pupil photos" in the screen's app bar is stored on the device only (settings key `pupilPhotos`, default on). Web: the relay (`worker/src/proxy.ts`) already forwards any path of an allowlisted host and binary bodies with their content type, plus the bearer `authorization` header (cookies never) — no relay change was needed.

### Absence summaries (teachers)
"Summary" in the class register screen counts the absences of the lesson's pupils (docs/TEACHER_FEATURES.md). Three scopes:
- **Lesson**: getPeriodData2017 of the lesson block.
- **Subject**: the teacher's own timetable weeks of the range (cached, else fetched; at most 45 weeks, the latest ones), the lessons of the course (same `lessonId`, else same subject(s) + class(es); not cancelled, already started), getPeriodData2017 for them in chunks of 40. Lessons a substitute held are asked for in their own chunks; if the server refuses those, they are skipped and counted as "no data". Per absence and lesson: one absent lesson, or a late arrival when the absence starts with the lesson but ends before it ends.
- **All subjects** — **assumed**, no teacher answer seen: `GET /WebUntis/api/classreg/absences/students?startDate=yyyymmdd&endDate=yyyymmdd&studentId=-1&klasseId=<id>&excuseStatusId=-1` with the web session headers (as for parents, see "Reporting absences"; `studentId=-1` is a guess for "all pupils"), per class of the lesson. If that fails (anything but network / timeout), `getStudentAbsences2017 {startDate, endDate, includeExcused, includeUnExcused, klasseId, auth}` (`klasseId` is a guess). Both answers go through one tolerant parser: list under `data.absences`, `absences`, `data` or top level; per entry `id`, start/end as `startDate`+`startTime` (yyyymmdd / hhmm) or `startDateTime`/`endDateTime`; pupil `studentId`/`student{id, firstName, lastName}`/`studentName`; excused `isExcused`/`excused`/`excuse.isExcused`; status `excuseStatus` (string) / `excuseStatusId` / `excuse.excuseStatus` ("offen"/"open" = open, any other status without excuse = unexcused, none = open); reason `reason` (string or `{name}`)/`absenceReason`; `text`; late `isLate`/`late`/`lateness` or a `type` containing LATE. Only entries of the lesson's pupils are kept (by id, else by name). Lessons per absence = time-grid units it overlaps (fallback grid: minutes / 45), so the count is approximate.
- Excuse state of getPeriodData2017 absences: `excused`/`isExcused`/`excuse.isExcused`; `excuseStatusId`/`excuse.excuseStatusId` and `excuseStatus` (string)/`excuse.excuseStatus` are now parsed too (assumed keys).
- Debug log: `REST classreg class absences request` (the GET path), `REST classreg absences/students klasseId=… from..to` (answer), `getStudentAbsences2017 (class) request body` and its answer.
- Default period: the school year containing today (master data `schoolyears`), else 1 September up to today.

### Substitutions (teachers)
A lesson of the teacher held by a substitute: in their own timetable the teacher element has `orgId` = own id and `id` = the substitute (or `id` 0 with an added teacher). The app treats such a lesson as the substitute's: the class register screen is read-only, saves / new entries are refused in the repository, getPeriodData2017 for such lessons is sent separately from the own ones (a refusal must not break the overview or previous topics). A lesson where the teacher is `id` (also with another `orgId`, i.e. they substitute) is their own and editable. **Assumed**: that the server shows the substituted lesson (not CANCELLED) and shares its data with the original teacher.

## Lesson info (teachers)
"Add details" on a teacher's own lesson writes the lesson info everyone sees ("Info zur Stunde", read back as the period's `text.info` → `Period.infoText`) instead of a device-only note. Built on branch `teacher` (0.6.0+109).

From the decompiled official app (see "Room booking and exams" below): `submitPeriodInfo2017 {periodId, periodInfo, auth}` (`SubmitPeriodInfoRequest extends AuthenticatedRequest`, `periodId: long`, `periodInfo: String`) → `{success: bool}`. Sent once per period of the block; `''` is sent to remove the text (assumed to clear it). The request body is in the Debug log as `submitPeriodInfo2017 request body`. **Not yet seen against a real server.**

Other write methods in that build, for later: `submitLessonTopic`, `submitHomeWork {ttId, homeWork}`, `submitClassRegEvents {ttId, event}`, `submitAbsences`, `createAbsences2017`, `editAbsence2017`, `createImmediateLateness2017`, `submitExcuse2017`, `getLessonTopic2017`, `getClassregData2017`.

## Room booking and exams (teachers)
Teacher accounts with the class register get "Book a room" on lessons of their own timetable, "Create exam" on lessons (instead of the device-only "Mark as exam") and "Exams" in the drawer (their exam list and "New exam"). Built on branch `teacher` (0.6.0 alphas).

**Room calls: names and params come from the official app, but no real answer has been seen yet.** Source: the official Untis Mobile Android app, decompiled (build Sept 2025, https://github.com/JeffScripter/UntisDecompiledSept2025, `smali_classes3/com/untis/mobile/api/UntisMobileApi.smali` and `api/dto/*`). The request classes extend `AuthenticatedRequest` (so they take the usual `auth`). The app has no other room or booking method, and no method to create or cancel a booking:
- `getRoomChangeData2017 {periodIds:[ttId…], auth}` → `{availableRoomIds:[id…], errors:[UMError]}`. These are the rooms free for those periods. We use it for "Book a room" and send the whole block (double lessons included).
- `getAvailableRooms2017 {startDateTime:"2026-11-10T09:40", endDateTime, auth}` → `{roomIds:[id…]}`. The date-time format is **assumed** (the same as the other 2017 methods). We use it for the exam room (any time range), and as a fallback for "Book a room" when `getRoomChangeData2017` answers "method not found".
- `submitRoomChange2017 {periodIds:[…], orgRoomId, roomId, auth}` → `{errors:[UMError], periods:[UMPeriod]}`.
  - **Assumed:** `orgRoomId` is the room being replaced. We send the period's planned room (`orgId` of the room element), or 0 when the lesson has no room.
  - **Assumed:** cancelling a booking means a second change back to the planned room ("Back to …", only offered while the room element shows a change). Booking rooms outside lessons doesn't exist in this API.
- `UMError {code, title, details, meta, source}`. Errors in a 2xx answer are shown in the screen: a non-empty `errors` list means the change failed.
- Parsers also accept `roomIds`/`rooms`/`availableRooms`/a bare list, with ids as numbers, strings or `{id}`.
- After a successful change, the teacher's own timetable week is refreshed.

**Exam creation: guessed.** The official app has no call for it (it only has `getExams2017`), and we found no open-source client that creates exams:
- `POST /WebUntis/api/exams` (the classic web endpoint that `GET` exams come from), with the same web session or bearer handling as the absence report. On HTTP 404/405 we try `POST /WebUntis/api/classreg/exams` once.
- JSON body (keys without a value are left out): `{examTypeId?, examType, name, text, examDate:yyyymmdd, startDate, endDate, startTime:hhmm, endTime, startDateTime, endDateTime, subjectId, lessonId, klasseIds, studentIds ([] = the whole classes), roomIds, teacherIds, periodIds}`. The field names copy what `GET /WebUntis/api/exams` returns (`examType, name, examDate, startTime, endTime, text`), plus the ids.
- Answer: the id from `{data:{id}}`/`{id}`/`{exam:{id}}`. `{errors:[…]}` or `{data:{success:false, message}}` counts as a failure and is shown.
- Exam types: master data `examTypes` (`{id, name, longName, active}`, **assumed key**), from one `getUserData2017` call per session. If there are none, the type is free text.
- After creating an exam, the own timetable week is refreshed. The exam then shows via the period's `exam` (getTimetable2017) and in getExams2017 (type TEACHER).

Exam editor ("New exam" from the menu):
- Subjects are only the teacher's own: the subjects and the classes per subject are taken from their own timetable, 2 weeks back to 3 weeks ahead. No server list of a teacher's lessons is known.
- Periods default to the teacher's lessons of that subject and class on the chosen date (a double lesson counts as one block). They can be changed to any consecutive units of the day's time grid.

Request bodies are in the Debug log as `getRoomChangeData2017 request body`, `getAvailableRooms2017 request body`, `submitRoomChange2017 request body` and `REST exams request body`.

Also seen in the decompiled app (not used yet; for other features): `submitClassRegEvents {ttId, event:JsonClassRegEvent}` (our class register entries call `createClassRegEvent2017` does not exist there), `submitHomeWork {ttId, homeWork:JsonHomeWork}`, `submitLessonTopic`, `createImmediateLateness2017`, `editAbsence2017`, `getClassregData2017`, `getLessonTopic2017`, `submitPeriodInfo2017`.

## Office hours
Assumed (no real response seen yet): `getOfficeHours2017 {klasseId, startDate, auth}`.
- `klasseId`: the account's first `klassenIds` entry, else the parent's selected child's class, else the class that occurs most in the cached "My timetable" weeks, else `-1` (**assumed** to mean "all classes"). Some student accounts have empty `klassenIds` — before this the request was never sent at all.
- A class-specific request that returns nothing is repeated once with `-1`.
- Response: a list under `officeHours` (also accepted: top-level list, `officeHourList`, `items`). Per item: `startDateTime`/`endDateTime` (ISO or epoch ms) or `date`/`startDate` (yyyyMMdd int/string or ISO) plus `startTime`/`endTime` (hhmm int, `"1345"`, `"13:45"`, `"T13:45"`); teacher `displayNameTeacher`/`teacherName`/`teacher` (string or `{displayName|longName|name}`); teacher id `teacherId`/`teacherID`/`teacherElementId`/`teacherIds[0]`/`teacher.id`/`teachers[0].id` (optional); rooms `displayNameRooms`/`rooms`/`roomName` (string or list); `email`, `phone`, `registrationPossible`, `registered`.
- Client: the list is grouped per teacher by the teacher id when present, else by name + email + phone; a one-word name (last name only) with neither also takes the rooms into account, so two "Müller"s don't merge. Same-named groups show their email or rooms in the header.

## Debug log
Only responses are recorded, never requests (so no passwords, OTPs or secrets). The one exception is the body of the absence report (`REST classreg absences/students/self request body`), which has no credentials in it, and the teacher writes (`<method> request body`, e.g. `submitRoomChange2017 request body`, `REST exams request body`; also without credentials). Redirect answers are logged with their target URL, without its query or `;jsessionid`. Bearer tokens are never logged. `getAppSharedSecret` and `getAuthToken` results are replaced by their shape (`<redacted string, N chars>`). In `getUserData2017` responses, values of keys that look like credentials (`token`, `secret`, `password`, `otp`, `jwt`) are redacted. The latest `getUserData2017` response, a "userData only (master data left out)" copy of it, and the latest `getOfficeHours2017` response per `klasseId` stay in the log regardless of its 30-entry limit. The Debug screen menu can fetch both on demand.

## Master data
- `timeStamp`
- `klassen`, `teachers`, `rooms`, `subjects`, `departments`, `holidays`, `schoolyears`, `absenceReasons`, `excuseStatuses`, `eventReasons`, `duties`
- `timeGrid {days:[{day:"MON", units:[{label, startTime, endTime}]}]}`

Teacher fields: `{id, name, firstName, lastName, foreColor, backColor, active, displayAllowed}`.

## Error codes
| Code | Meaning |
|---|---|
| -6003 | Too many search results |
| -8500 | Invalid school |
| -8502 | No user specified |
| -8504 | Invalid password |
| -8509 | No right |
| -8511 | Locked |
| -8519 | 2FA required |
| -8520 / -8521 | Authentication |
| -8523 | No public access |
| -8524 | Client time |
| -7001…-7004 | Bad timetable params |
| -42000…-42003 | Access denied / maintenance |
| -32601 | Method not found |

## Rules for our client (the teacher-bug fixes)
1. Resolve names against **all** master-data entries. Use `active` only to filter pickers, never for lookup. BetterUntis dropped inactive teachers, and `active` defaults to false when the field is missing.
2. Teacher long name: `"first last".trim()`, then `name`, then `#id`. Short name: `name`, then `lastName`, then a placeholder.
3. Keep any `name`, `longName` or `displayName` fields on period elements and use them as a fallback. Also use names from office hours.
4. Apply the master-data delta **before** mapping periods, then persist `timeStamp`. Re-resolve names whenever master data changes. Offer "full refresh" with timestamp 0.
5. Parse enums tolerantly. An unknown `type`, `is` or `can` value must never drop the timetable.
6. Add a debug view of raw responses, so the next missing-data bug is easy to diagnose.
