# Decisions made while the maintainer was away ("savestate")

Each entry: what I chose, the alternative, and how to switch. Delete entries
once confirmed.

## 1. Version swap: server = 0.5.0, teacher = 0.6.0
- **Chosen:** swapped (agreed in chat before leaving). Teacher branch commit
  `6a2f037` (0.6.0+66) renamed its docs to 0.6.0; this branch uses 0.5.0+N.
- **Alternative:** keep teacher = 0.5.0, server = 0.6.0.
- **Undo:** nothing was released under the new numbers. Change `version:`
  in `pubspec.yaml` on both branches (keep +N increasing), revert the
  "0.6.0 alphas" wording in teacher's docs/API.md, docs/FEATURES.md and
  docs/TEACHER_FEATURES.md, and rename release notes files if any.

## 2. Turning E2E on: no account reset
- **Chosen:** `PUT /api/sync/e2e` creates the header and deletes the plaintext
  notes in the same atomic step; the client re-uploads encrypted with the same
  session. (The plan said "reset the account first", but a reset also deletes
  the session and header.)
- **Alternative:** reset (DELETE /account) + new login + PUT header.
- **Switch:** worker/src/sync/db.ts `createE2eHeader` (drop the DELETE) and
  the engine's enableE2e flow.

## 3. Passphrase change / new recovery code: `PATCH /api/sync/e2e`
- **Superseded by R4** (authKey proof). Was: replace the header only if its `check` value is unchanged
  (proves the same data key; the library keeps `check`). 409
  `e2e_check_mismatch` otherwise.
- **Alternative:** no server-side replace; change = reset + re-upload
  everything encrypted with a new key.
- **Switch:** remove the PATCH route (worker/src/sync/router.ts, e2e.ts,
  db.ts `replaceE2eHeader`) and its tests.

## 4. Smaller server limits chosen by me / the agents
- Encrypted note blob ≤ 16 KiB (a 4 000-character note encrypts to ~12.6 KB).
- At most 30 sessions per identity (oldest dropped on login → that device
  gets "signed out").
- Daily cron at 03:17 UTC deletes expired sessions (`wrangler.jsonc`
  `triggers`).
- Rate limits (wrangler.jsonc `ratelimits`): login 10/min per IP, relay
  300/min per IP, other sync calls 120/min (now per identity, see R3).
- **Switch:** values in worker/src/sync/notes.ts (`LIMITS`), db.ts
  (`MAX_SESSIONS_PER_IDENTITY`), wrangler.jsonc.

## D1. D1 database id: repository variable, substituted in CI
- **Chosen:** `worker/wrangler.jsonc` keeps the placeholder
  `00000000-0000-0000-0000-000000000000`; the deploy job replaces it with the
  repository **variable** `CLOUDFLARE_D1_ID` (fails with an error if it is
  set up for deploys but the variable is missing). Keeps account-specific ids
  out of the repo, local dev/tests never point at the real database, forks
  can deploy to their own account.
- **Alternative:** commit the real `database_id` (it isn't a secret; this is
  Cloudflare's default workflow) and drop the substitution step.
- **Switch:** put the id into `wrangler.jsonc`, delete the "Use the real D1
  database id" step in `.github/workflows/release.yml`.

## D2. Alpha = preview version under alias `alpha`, shared production D1
- **Chosen:** alpha tags run `wrangler versions upload --preview-alias alpha
  --tag <tag>` (stable URL `alpha-better-betteruntis.<sub>.workers.dev`, no
  production traffic); beta/stable run `wrangler deploy --tag <tag>`.
  Added `"preview_urls": true` to `wrangler.jsonc`. Previews share the
  production D1 database and migrations run on every deploy, so migrations
  must be additive. The new `wrangler preview` command (open beta) was not
  used.
- **Alternative:** a separate `alpha` wrangler environment with its own
  Worker and D1 database (`env.alpha` in wrangler.jsonc, second
  `CLOUDFLARE_D1_ID_ALPHA` variable): fully isolated test data, but alpha
  testers' synced notes don't carry over, and twice the setup.
- **Switch:** add `env.alpha` to wrangler.jsonc and use
  `deploy --env alpha` + `d1 migrations apply ... --env alpha` for alphas.

## D3. Deploy only on tag pushes, not on manual rebuilds
- **Chosen:** the `cloudflare` gate job disables the deploy for
  `workflow_dispatch` runs, so rebuilding an old tag can't put old code in
  production. Missing secrets → job shown as *skipped*, run stays green.
  The GitHub release doesn't wait for the deploy (a Cloudflare problem
  doesn't hold back the APK/IPA); a failed deploy still turns the run red.
- **Alternative:** add a `deploy: true/false` input to workflow_dispatch;
  make `release` depend on `deploy-worker`.
- **Switch:** edit the `cloudflare` job's check in release.yml.

## D4. Self-hosting removed completely
- **Chosen:** deleted `server/`, `Dockerfile`, `docker-compose.yml`,
  `.dockerignore`, the release's Docker job and the
  `…-web-linux-x64.tar.gz` asset, the server tests in ci.yml and the
  `server/**` analyzer exclude. docs/WEB.md now describes the Cloudflare
  version and points to 0.4.x tags for the old server. The release's `web`
  job now only builds the app and passes it to `deploy-worker` as an
  artifact (`web-build`, 7 days).
- **Alternative:** keep the server for existing self-hosters for one more
  release (deprecated), or keep only the web tarball (static files without
  a relay are useless because of CORS).
- **Switch:** `git checkout v0.4.8-alpha.7 -- server Dockerfile
  docker-compose.yml .dockerignore` and restore the jobs from that tag's
  release.yml.

## D5. npm pinned to 11.19.1 in CI, `npm ci --strict-allow-scripts`
- **Chosen:** CI installs npm 11.19.1 (same as the dev container) so the
  `allowScripts` policy in `worker/package.json` is honoured, and uses
  `--strict-allow-scripts` so a new dependency with unreviewed install
  scripts fails the build instead of running them. Verified locally: both
  `workerd` and `esbuild` postinstalls run under the strict flag.
- **Alternative:** plain `npm ci` with the runner's bundled npm (unreviewed
  scripts would only warn).
- **Switch:** drop the `npm install -g` step / the flag.

## D6. Privacy notice: backup retention = D1 Time Travel window
- **Chosen:** docs/PRIVACY.md (draft) names Time Travel as the only backup,
  7 days (free) / 30 days (paid) as a placeholder to pick, and says the
  relay writes no logs. Legal basis for sync: consent (Art. 6(1)(a)); for
  the relay left as a placeholder (6(1)(b) or (f)).
- **Alternative:** a separate exported backup (e.g. `wrangler d1 export`
  to R2) with its own retention: longer safety net, but then deletions
  linger longer and the notice must say so.

## 5. Sync server address in the phone apps (placeholder)
- **Chosen:** `BBU_SYNC_URL` compile-time constant, default
  `https://better-betteruntis.workers.dev` (placeholder: real workers.dev
  URLs are `<worker>.<your-subdomain>.workers.dev`). The web version always
  uses its own origin.
- **To do:** once the Worker exists, set the real URL as the default in
  lib/sync/sync_client.dart (or pass `--dart-define=BBU_SYNC_URL=...` in
  release.yml). A custom domain would make this independent of the
  Cloudflare subdomain.
- **Update (engine review):** the placeholder default is gone. Release
  builds pass the repository **variable** `BBU_SYNC_URL`
  (`--dart-define=BBU_SYNC_URL=${{ vars.BBU_SYNC_URL }}`); without it the
  default is `''` and sync is **unavailable** in the phone apps of that
  build (the sync screen says "Sync isn't available in this build" instead
  of the opt-in, `enable()` throws). The web version still uses its own
  origin. To do: set the variable to the Worker / custom-domain URL.

## 6. Web version: only one account can sync
- **Chosen:** the browser has one `bbu_sync` cookie, so on the web `enable()`
  refuses while another account syncs (otherwise notes could land on the
  wrong identity).
- **Alternative:** per-account bearer tokens in localStorage on the web
  (readable by page scripts, weaker than the HttpOnly cookie).
- **Switch:** lib/sync/sync_engine.dart (web guard) + client auth mode.

## 7. Removing an account from the app
- **Chosen:** ends this device's sync session and forgets its keys; the
  server data stays (the dialog says so and points to "turn off sync" to
  delete it).
- **Alternative:** removing the account also turns sync off (deletes the
  server data), which would affect the user's other devices.

## 8. Small engine behaviours
- 429 (rate limit): single calls (pull, E2E header changes, interactive
  actions) are not retried; the error is shown and the next trigger
  (change, app start/resume, "Sync now") retries. **Exception: note
  uploads** (`PUT /notes` batches of a sync, e.g. a full upload of
  thousands of notes after enable/unlock/E2E switch run into the server's
  20 writes/min per identity): the engine waits `retry-after` (at most 65 s
  per wait, at most 10 min per sync) and continues; it stops if the
  account's state changed or the engine was disposed. Acknowledged
  batches are already stored (not dirty), the rest stays dirty.
  Switch: `SyncEngine.maxRateLimitWait` / `maxPushWait`.
- Two devices changing the same note in the same millisecond: the server
  keeps the version it stored first and every device adopts it ("server /
  first writer wins"). Notes from before sync (updatedAt 0) are stamped
  with the current time on their first upload, so they don't all tie.
- 401: one silent re-login with the account's WebUntis login; continues
  only for the same identity and if the server's seq didn't go back
  (otherwise "turned off or reset on another device", signed out, an empty
  re-created account is deleted again).
- Clock ahead: changes are never stamped more than 60 s ahead of the
  device clock; on 400 `clock_skew` the offending notes are stamped with
  the server's `serverTime` and the upload is retried once.
- Notes over 4 000 characters are skipped (counted in the sync error); the
  input field is now capped at 4 000.

## R1. Per-identity byte quota: 5 MiB
- **Chosen:** 5 MiB per identity = UTF-8 bytes of key + text/blob over all
  stored notes incl. tombstones (413 `storage_quota`), next to the 20 000
  notes limit. A write that only shrinks the total always passes (deleting
  works when over quota). Counters `identities.note_count`/`bytes` are kept
  by SQLite triggers on `notes` (same statement as every change, also for
  E2E on/off, tombstone purge, cascades), so no request scans notes.
- **Alternative:** a larger quota (20 000 × 4 000 chars would be ~80 MB per
  user; 500 MB D1 total); or explicit counter statements in each batch
  instead of triggers.
- **Switch:** `LIMITS.maxBytesPerUser` in worker/src/sync/notes.ts.

## R2. Tombstone purge after 400 days (server time)
- **Chosen:** daily cron deletes tombstones whose row wasn't written on the
  server for 400 days (new column `notes.stored_at`, server ms, partial
  index `notes_tombstones`; `updated_at` is the client clock and could be
  set arbitrarily old). At most 20 000 per run. A device offline longer
  than that may keep or re-upload notes deleted elsewhere.
- **Alternative:** longer (or never) — tombstones count against both quotas.
- **Switch:** `TOMBSTONE_MAX_AGE_MS` in worker/src/sync/db.ts.

## R3. Rate limits per identity: RL_WRITE 20/min, RL_AUTH 300/min per IP
- **Chosen:** RL_SYNC (120/min) is now keyed by identity, not session, and
  applies to every authenticated call; new RL_WRITE (20/min per identity)
  on top for PUT notes and PUT/PATCH/DELETE e2e; new RL_AUTH (300/min per
  client IP, /64 for IPv6) before every session lookup (also logout).
  RL_SESSION / RL_PROXY keys are now /64 for IPv6. 20 writes × 500 notes =
  10 000 notes/min, so a first upload of 20 000 notes takes ≥ 2 minutes
  (the client must honour 429 + `retry-after`; see 8. "no automatic retry").
  RL_AUTH 300/min allows a school NAT with many users; lower it if abused.
- **Alternative:** RL_WRITE 60/min; reuse RL_SESSION with a key prefix
  instead of RL_AUTH (10/min per IP would be far too low for normal use).
- **Switch:** `ratelimits` in worker/wrangler.jsonc (namespace ids 1004,
  1005 are new).

## R4. E2E PATCH: authKey proof, `check` rule dropped
- **Chosen:** PATCH `{header, authKey}` requires SHA-256(authKey) == stored
  `authHash` (constant time) and the new header's `authHash` == stored. The
  old rule "`check` must be unchanged" is dropped (and with it 409
  `e2e_check_mismatch`): the auth key already proves the DEK, and the
  client may re-encrypt `check` with a fresh nonce. Same proof for the new
  `DELETE /api/sync/e2e` (turn E2E off, sessions stay). KDF bounds on the
  server: m 19 456–262 144, t 2–16, p 1–16, salt exactly 16 bytes.
- **Alternative:** keep the `check` equality as an extra condition.
- **Switch:** worker/src/sync/e2e.ts `patchE2e` (compare `check` with the
  stored header) and db.ts `replaceE2eHeader`.

## R5. Browser login answer without token; identity ids never reused
- **Chosen:** `POST /api/sync/session` omits `token` when an `Origin`
  header is present (browsers use the HttpOnly cookie). `identities.id` is
  `AUTOINCREMENT`, so a deleted identity's id is never given to a later
  login. More than one `bbu_sync` cookie → 401.
- **Alternative:** always return the token (web client could keep it in
  memory), plain `INTEGER PRIMARY KEY`.
- **Switch:** worker/src/sync/auth.ts `createSessionHandler`,
  migrations/0001_init.sql.
