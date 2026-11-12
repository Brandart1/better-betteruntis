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
- For parents, `studentId` is the child's id from `userData.children`, and `.../students/self` is the right path (the web client uses the same absence module for students and parents).
- The meta field names above; every field is optional in our parser. If the meta call fails, reasons come from the `absences/students` answer, else from master data `absenceReasons` (shown with a notice).

Client behaviour: the Absences tab of parent accounts with children shows "Report absence". The form asks for the child (the selected one is the default), from/until (default: today, the whole school day from the time grid, else the server's default times, else 08:00 to 16:00), the reason and an optional note. If `showCreateAbsence` is false, the form says so and sending is disabled. HTTP 403 means no right. After a successful report every cached absence list of the account is dropped and reloaded.

## Office hours
Assumed (no real response seen yet): `getOfficeHours2017 {klasseId, startDate, auth}`.
- `klasseId`: the account's first `klassenIds` entry, else the parent's selected child's class, else the class that occurs most in the cached "My timetable" weeks, else `-1` (**assumed** to mean "all classes"). Some student accounts have empty `klassenIds` — before this the request was never sent at all.
- A class-specific request that returns nothing is repeated once with `-1`.
- Response: a list under `officeHours` (also accepted: top-level list, `officeHourList`, `items`). Per item: `startDateTime`/`endDateTime` (ISO or epoch ms) or `date`/`startDate` (yyyyMMdd int/string or ISO) plus `startTime`/`endTime` (hhmm int, `"1345"`, `"13:45"`, `"T13:45"`); teacher `displayNameTeacher`/`teacherName`/`teacher` (string or `{displayName|longName|name}`); rooms `displayNameRooms`/`rooms`/`roomName` (string or list); `email`, `phone`, `registrationPossible`, `registered`.

## Debug log
Only responses are recorded, never requests (so no passwords, OTPs or secrets). The one exception is the body of the absence report (`REST classreg absences/students/self request body`), which has no credentials in it. Redirect answers are logged with their target URL, without its query or `;jsessionid`. Bearer tokens are never logged. `getAppSharedSecret` and `getAuthToken` results are replaced by their shape (`<redacted string, N chars>`). In `getUserData2017` responses, values of keys that look like credentials (`token`, `secret`, `password`, `otp`, `jwt`) are redacted. The latest `getUserData2017` response, a "userData only (master data left out)" copy of it, and the latest `getOfficeHours2017` response per `klasseId` stay in the log regardless of its 30-entry limit. The Debug screen menu can fetch both on demand.

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
