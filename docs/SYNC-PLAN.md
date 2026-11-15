# Sync and web hosting plan (0.5.x, branch `server`)

Status: **plan, approved 2026-11-15**; being implemented. Ships as 0.5.0,
before the teacher release (now 0.6.0; numbers swapped 2026-11-15).

## Goal

- The **web version** is hosted on Cloudflare (a Worker with static assets),
  deployed automatically from GitHub Actions on release tags. Nothing for the
  maintainer to run, update or back up.
- The same Worker is the **WebUntis relay** for the web version (WebUntis
  sends no CORS headers) and hosts the **optional sync** of the user's own
  lesson notes (custom exams, lesson details) in Cloudflare D1 (SQLite).
- Sync is **opt-in** with a disclaimer that the data is stored on a server.
  Turning it off deletes everything stored about the user on the server; the
  local notes stay on the device.
- **Optional end-to-end encryption** (sync passphrase): the server then only
  stores encrypted notes it can't read.
- No self-hosting (dropped 2026-11-15). The old `server/` folder and Docker
  files were removed in 0.5.0 (recoverable from tag `v0.4.8-alpha.7`; see
  docs/DECISIONS-PENDING.md D4).

## Architecture

```
GitHub Actions (release tag)
  └─ flutter build web ──► wrangler deploy ──► Cloudflare Worker
                                                ├─ static assets (web app, _headers: COOP/COEP)
                                                ├─ /proxy/<host>/...  → https://<host>/... (*.webuntis.com only)
                                                └─ /api/sync/*        → D1 database
Android / iOS app ──────────────────────────────► /api/sync/* (bearer token)
Web app (same origin) ──────────────────────────► /proxy/*, /api/sync/* (cookie)
```

- Worker in TypeScript (`worker/`), tested with Vitest + the Workers pool
  (Miniflare, local D1).
- Deploy: `cloudflare/wrangler-action` in release.yml (secrets
  `CLOUDFLARE_API_TOKEN`, scoped to this Worker, and `CLOUDFLARE_ACCOUNT_ID`,
  added by the maintainer). Alphas deploy to a preview URL, betas/stable to
  production. Rollback in the dashboard.
- D1 migrations in `worker/migrations/`, applied by the deploy job.

## API (adapted from the deleted branch's design)

All JSON, `cache-control: no-store`, errors `{"error": "<code>", "message"}`.

| Endpoint | Purpose |
|---|---|
| `POST /api/sync/session` | `{host, school, untisToken}` → verify with WebUntis `app/data`, create session; returns `{token, expiresAt, identity, e2e}` + cookie (`token` omitted when the request has an `Origin`, i.e. from a browser) |
| `DELETE /api/sync/session` | log out this session |
| `GET /api/sync/notes?since=<seq>` | changes after seq (paged, max 1000) |
| `PUT /api/sync/notes` | upsert up to 500 notes, last write wins (a tie keeps the stored version) |
| `GET/PUT /api/sync/e2e` | the user's E2E header (salt, KDF params, wrapped keys); PUT creates it once and deletes the plaintext notes; see below |
| `PATCH /api/sync/e2e` | `{header, authKey}`: replace the header for the same key (passphrase change, new recovery code); needs proof of the DEK (`authKey`), else 403 `e2e_auth_failed` |
| `DELETE /api/sync/e2e` | `{authKey}`: turn E2E off (deletes header + all notes, sessions stay), 403 `e2e_auth_failed` / 404 `e2e_not_enabled` |
| `DELETE /api/sync/account` | delete everything about the user (opt-out, E2E reset) |

Wire details (implemented in `worker/src/sync/`, summary in `worker/README.md`):

- **Note, plaintext account:** `{key, exam, text, updatedAt, deleted}` (key
  1–256 chars, text ≤ 4 000 chars, no NUL/unpaired surrogates). **E2E
  account:** `{key, blob, updatedAt, deleted}` with `key` = 43-char base64url
  HMAC and `blob` = base64url ciphertext (≤ 16 KiB decoded); `exam`/`text`
  must be absent. One request is either all plaintext or all encrypted.
  Responses add `seq`. `updatedAt` > now + 5 min → 400 `clock_skew`.
- `GET /notes` → `{notes, latestSeq, more, e2e, identity}`; `PUT /notes` →
  `{notes: stored version of each key, latestSeq, e2e, identity}` (`identity`
  from the session, so the web client can detect a cookie of another
  account). A write with an equal `updatedAt` keeps the stored version and
  returns it. `clock_skew` errors carry `serverTime` (ms UTC) so the client
  can clamp and retry. Duplicate keys in one
  request merge like applying them in order. Seqs are strictly increasing per
  identity (gaps possible after deletions).
- Mode: once a header exists, plaintext notes → 409 `e2e_required`; without
  one, encrypted notes → 409 `e2e_not_enabled`.
- `GET /e2e` → the header, or 404 `e2e_not_enabled`. `PUT /e2e` → 201 with
  the stored header (unknown fields dropped), or 409 `e2e_exists`. **Creating
  the header also deletes the account's plaintext notes in the same batch**,
  so the "turn on E2E" flow is: PUT header, then re-upload all notes
  encrypted (no account reset or new login needed; other devices learn it
  from `e2e: true` and the 409s). Turning E2E off/resetting the passphrase
  without a recovery code is still `DELETE /account`.
- Limits: 500 notes and 1 MiB per request (413 `batch_too_large` /
  `body_too_large`), per identity 20 000 notes incl. tombstones (413
  `too_many_notes`) and 5 MiB of key + text/blob bytes (413
  `storage_quota`; shrinking writes always pass), at most 30 sessions per
  identity (oldest dropped on login). Rate limits → 429 `rate_limited` +
  `retry-after` (bindings in worker/README.md).
- Tombstones not written on the server for 400 days are purged by the
  daily cron; a device offline longer than that may keep or re-upload notes
  deleted elsewhere.
- `DELETE /e2e` turns E2E off without signing devices out: header and all
  (encrypted) notes go in one batch; other devices see `e2e: false` and
  re-upload in plaintext.
- A cross-site `Origin` on `POST /session` → 403 `csrf_rejected`.

## Security design (agreed)

1. **Injection:** only prepared statements with `.bind()`; no string-built
   SQL; fixed table/column names. Strict JSON validation (types, lengths,
   counts, body size). Note texts are shown as plain text in the app.
2. **Isolation between users:** the identity (host + school + WebUntis user
   id) comes only from the server's own check with WebUntis; no endpoint takes
   a user or account id. Every query is scoped `WHERE identity_id = ?` from the
   session. Notes are keyed by (identity, key). Account deletion only acts on
   the session's identity. Tests: user B can't read/overwrite/delete A's
   notes, even with A's keys.
3. **Verification target:** the WebUntis host must match the allowlist
   (`webuntis.com`, `*.webuntis.com`), otherwise a fake server could claim any
   identity. The claimed school must match the tenant WebUntis reports.
4. **Sessions:** 256-bit random tokens; only SHA-256 hashes stored. Web:
   cookie `bbu_sync` (HttpOnly, Secure, SameSite=Strict, Path=/api/sync, so
   never sent to /proxy). State-changing cookie requests need the
   `X-BBU-Sync: 1` header (CSRF). Tokens never in URLs. 90-day expiry; logout
   deletes.
5. **Accidental data loss:** reject `updatedAt` more than 5 minutes in the
   future (clock skew). D1 Time Travel as a safety net (point-in-time restore).
   Opt-out asks for confirmation; other devices getting 401 stop syncing and
   **keep their local notes**. Last-write-wins in one atomic statement
   (`INSERT … ON CONFLICT DO UPDATE … WHERE excluded.updated_at >
   notes.updated_at`); multi-statement changes via `db.batch()` (atomic).
6. **Abuse and limits:** Workers rate-limiting bindings: session creation
   and the relay per client IP, session lookups per client IP *before* D1
   is asked (random tokens can't cost unlimited reads), all sync calls and,
   stricter, writes **per identity** (more sessions don't buy more
   requests); IPv6 clients are keyed by their /64. Plus a WAF rule.
   Per identity 20 000 notes and a **5 MiB byte quota**, both checked from
   counters on `identities` (maintained by triggers, no scans: D1 bills
   rows read/written); 4 000 chars/note, 500 notes and 1 MiB per request;
   old tombstones purged daily. Free plan stops instead of billing.
   Multiple `bbu_sync` cookies (cookie tossing) → 401; the browser login
   answer carries no token (cookie only).
7. **Privacy:** no logging of bodies, tokens, note keys or texts; identities
   only as a short hash. Privacy notice (draft from the deleted branch can be
   reused), Cloudflare as processor.
8. **Accounts:** 2FA on Cloudflare and GitHub, API token scoped to this
   Worker, pinned action versions. A takeover could deploy a password-stealing
   Worker; this is the biggest single risk.
9. **Relay sandboxing:** `/proxy` only serves fetch/XHR from this origin
   (`Sec-Fetch-Dest` other than `empty` or `Sec-Fetch-Site: cross-site` →
   403), and every relay response has `Content-Security-Policy: sandbox;
   default-src 'none'; frame-ancestors 'none'` and `Content-Disposition:
   attachment`, so relayed WebUntis content can never run as a page of
   this origin (which would reach the sync cookie's API via same-origin
   fetches). All responses: `X-Frame-Options: DENY`, `frame-ancestors
   'none'`, HSTS.

## End-to-end encryption (optional)

**Goal:** with E2E on, a database leak, Cloudflare, or the maintainer can't
read note texts, exam marks or which lessons they belong to.

### Keys

- **Data key (DEK):** random 256-bit key, created on the first device that
  turns E2E on. Encrypts all notes. Never leaves devices unencrypted.
- **Passphrase key (KEK):** derived from the user's sync passphrase with
  **Argon2id** (m = 19 MiB, t = 2, p = 1, 16-byte random salt; OWASP minimum,
  fast enough in the browser). Wraps the DEK.
- **Recovery key (optional):** random 128-bit key shown once as a 26-character
  code; also wraps the DEK, so a forgotten passphrase isn't fatal.
- **Changing the passphrase** only re-wraps the DEK; notes are not
  re-encrypted.
- On each device the unwrapped DEK is cached in secure storage (Android
  Keystore / iOS Keychain via flutter_secure_storage; on the web
  localStorage, which is weaker, so the web asks again after 30 days).

### E2E header (server, readable by the server)

`{version: 1, kdf: {alg: "argon2id", m, t, p, salt}, wrappedDek, wrappedDekRecovery?, check, authHash}`.
`check` = the DEK encrypting a fixed string, to tell a wrong passphrase from
corrupt data. `authHash` = base64url(SHA-256(authKey)) (43 chars), with
`authKey` = HKDF-SHA256(DEK, info `"bbu-header-auth-v1"`, 32 bytes): replacing
(PATCH) or deleting (DELETE) the header requires sending `authKey`, so a
stolen session alone can't swap in a header for an attacker's key or turn
E2E off. The server checks SHA-256(authKey) against the stored hash in
constant time and never sees the DEK. Server-side KDF bounds: m 19 456–262 144
KiB, t 2–16, p 1–16, salt exactly 16 bytes. Stored per identity, written with `PUT /api/sync/e2e` only if
none exists yet (or after an account reset), so two devices can't create
different keys at the same time.

### Notes

- **Key hiding:** the server key becomes `HMAC-SHA256(K_key, noteKey)`
  (base64url), where `K_key` is derived from the DEK with HKDF
  (`info = "bbu-note-key-v1"`). The server can't see dates, times or lessons;
  the same note always maps to the same server key, so last-write-wins still
  works.
- **Content:** `exam`, `text` and the real note key are encrypted together
  with **XChaCha20-Poly1305** (random 192-bit nonce; package `cryptography`,
  same algorithm on all platforms), with `K_enc` from HKDF
  (`info = "bbu-note-enc-v1"`). Blob format v2:
  `0x02 | nonce(24) | ciphertext | tag(16)`. Associated data =
  `0x02 | u64 updatedAt | u8 deleted | server key`, so a ciphertext can't be
  moved to another note, and the server can't change a note's timestamp or
  mark it deleted (both checked when decrypting; tampered notes are skipped
  and counted).
- **Padding:** plaintext padded to multiples of 256 bytes to hide the text
  length.
- **Server still sees:** the identity, number of notes, `updatedAt`, `seq`,
  the deleted flag and the padded size. Tombstones are also encrypted
  records.

### Flows

- **Turn on E2E** (sync already on or new): set passphrase (min. 8 chars,
  strength hint), optionally note the recovery code → app creates the DEK,
  uploads the header (the server deletes its plaintext copies in the same
  step) and re-uploads all local notes encrypted.
- **Second device:** after the sync login the server reports `e2e: true` →
  app asks for the passphrase (or recovery code), unwraps the DEK, syncs.
- **Forgot passphrase, no recovery code:** "Reset sync" deletes the server
  data (`DELETE /api/sync/account`) and starts over; local notes on every
  device stay and are uploaded again.
- **Turn off E2E:** `DELETE /api/sync/e2e` with `authKey` (deletes header
  and encrypted notes, sessions stay), then re-upload in plaintext (with the
  normal disclaimer); other devices see `e2e: false` and do the same.
- **Change passphrase / new recovery code:** `PATCH /api/sync/e2e` with the
  re-wrapped header (same `authHash`) and `authKey`.

### Limits (stated in the app)

- In the **web version** the encryption code itself comes from the Worker, so
  someone controlling the Cloudflare account could serve modified code. The
  phone apps don't have this weakness. E2E still protects against database
  leaks and against reading the stored data.
- A lost passphrase without the recovery code can't be recovered by anyone;
  only the synced copy is lost, not local notes.

## App side (after teacher)

- Settings → Sync: opt-in dialog with disclaimer, the sync identity shown
  (for deletion requests), "Sync now", last sync, E2E section (turn on/off,
  change passphrase, show/regenerate recovery code), "Turn off sync" (deletes
  server data, keeps local).
- Sync client: note keys without the local account id; pull (`since`) then
  push; tombstones; reset `since` to 0 after a new session; stop on 401
  without touching local data.
- Web: relay origin = the Worker (same origin), cookie auth + `X-BBU-Sync`.

## Order of work

1. Worker skeleton: static assets + `_headers`, relay with allowlist, tests.
2. D1 schema + migrations, sessions with WebUntis check, notes API, account
   deletion, rate limits, tests (incl. cross-user and injection tests).
3. E2E header endpoint + server-side rules; client crypto library in the app
   with test vectors shared between Dart and the Worker tests.
4. release.yml deploy job (after the maintainer adds the secrets).
5. App: sync settings, client, E2E UI.
6. Privacy notice, README, docs.
