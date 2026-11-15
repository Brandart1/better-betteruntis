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
- **Chosen:** replace the header only if its `check` value is unchanged
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
  300/min per IP, other sync calls 120/min per session.
- **Switch:** values in worker/src/sync/notes.ts (`LIMITS`), db.ts
  (`MAX_SESSIONS_PER_IDENTITY`), wrangler.jsonc.
