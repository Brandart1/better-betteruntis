# Sync and web hosting plan (0.6.x, branch `server`)

Status: **plan, approved 2026-11-15**. Not implemented yet. Ships after the
teacher release (0.5.0), probably the last big step before 1.0.0.

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
  files are removed or kept for existing users; decide before release.

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
| `POST /api/sync/session` | `{host, school, untisToken}` → verify with WebUntis `app/data`, create session; returns `{token, expiresAt, identity, e2e}` + cookie |
| `DELETE /api/sync/session` | log out this session |
| `GET /api/sync/notes?since=<seq>` | changes after seq (paged, max 1000) |
| `PUT /api/sync/notes` | upsert up to 500 notes, last write wins |
| `GET/PUT /api/sync/e2e` | the user's E2E header (salt, KDF params, wrapped keys); see below |
| `DELETE /api/sync/account` | delete everything about the user (opt-out, E2E reset) |

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
6. **Abuse and limits:** Workers rate-limiting binding on session creation
   and the relay, plus a WAF rule; 20 000 notes/user, 4 000 chars/note, 500
   notes and 1 MiB per request. Free plan stops instead of billing.
7. **Privacy:** no logging of bodies, tokens, note keys or texts; identities
   only as a short hash. Privacy notice (draft from the deleted branch can be
   reused), Cloudflare as processor.
8. **Accounts:** 2FA on Cloudflare and GitHub, API token scoped to this
   Worker, pinned action versions. A takeover could deploy a password-stealing
   Worker; this is the biggest single risk.

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

`{version: 1, kdf: {alg: "argon2id", m, t, p, salt}, wrappedDek, wrappedDekRecovery?, check}`.
`check` = the DEK encrypting a fixed string, to tell a wrong passphrase from
corrupt data. Stored per identity, written with `PUT /api/sync/e2e` only if
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
  (`info = "bbu-note-enc-v1"`). Associated data = the server key + version, so
  a ciphertext can't be moved to another note.
- **Padding:** plaintext padded to multiples of 256 bytes to hide the text
  length.
- **Server still sees:** the identity, number of notes, `updatedAt`, `seq`,
  the deleted flag and the padded size. Tombstones are also encrypted
  records.

### Flows

- **Turn on E2E** (sync already on or new): set passphrase (min. 8 chars,
  strength hint), optionally note the recovery code → app creates the DEK,
  uploads the header, deletes the plaintext copies on the server (account
  reset) and re-uploads all local notes encrypted.
- **Second device:** after the sync login the server reports `e2e: true` →
  app asks for the passphrase (or recovery code), unwraps the DEK, syncs.
- **Forgot passphrase, no recovery code:** "Reset sync" deletes the server
  data (`DELETE /api/sync/account`) and starts over; local notes on every
  device stay and are uploaded again.
- **Turn off E2E:** reset the server data and re-upload in plaintext (with
  the normal disclaimer).

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
