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
   - `userData`: `elemId`, `elemType`, `displayName`, `schoolName`, `klassenIds`, `children`, `rights`.
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
- `getOfficeHours2017 {klasseId, startDate, auth}` returns name strings directly (`displayNameTeacher`, `displayNameRooms`).
- `getAuthToken {auth}` returns `{token}`, a JWT used as `Authorization: Bearer` for REST calls, e.g. `GET /view/v1/messages` (the inbox).
- Room finder: there is no dedicated method. Call `getTimetable2017` with `type:ROOM` for each saved room.

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
