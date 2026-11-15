# BetterBetterUntis Worker

Cloudflare Worker: serves the web app (static assets), relays WebUntis
requests (`/proxy/<host>/...`) and hosts the optional notes sync
(`/api/sync/*`) on D1. Design and security rules: `../docs/SYNC-PLAN.md`.

```sh
npm ci
npx vitest run        # tests (workerd + local D1, migrations applied in test/setup.ts)
npx tsc --noEmit      # typecheck
npx wrangler dev      # local dev
```

## Sync API (`src/sync/`)

All JSON, `cache-control: no-store`, errors `{"error": code, "message"}`.
Unknown paths → 404 `not_found`, wrong method → 405 with `allow`.

| Endpoint | Request → answer |
|---|---|
| `POST /api/sync/session` | `{host, school, untisToken}` → `{token, expiresAt, identity: {host, school, userId}, e2e}` + cookie `bbu_sync` |
| `DELETE /api/sync/session` | → 204, clears the cookie (also without a session) |
| `GET /api/sync/notes?since=<seq>` | → `{notes, latestSeq, more, e2e}` (1 000 per page) |
| `PUT /api/sync/notes` | `{notes: [...]}` (≤ 500, ≤ 1 MiB) → `{notes, latestSeq, e2e}` |
| `GET /api/sync/e2e` | → header, or 404 `e2e_not_enabled` |
| `PUT /api/sync/e2e` | header → 201 (once; deletes plaintext notes), 409 `e2e_exists` |
| `PATCH /api/sync/e2e` | header for the same key (passphrase change, new recovery code) → 200 if `check` is unchanged, 409 `e2e_check_mismatch`, 404 `e2e_not_enabled` |
| `DELETE /api/sync/account` | → 204, deletes identity, notes, sessions, header |

Notes: plaintext `{key, exam, text, updatedAt, deleted}`, E2E
`{key (43-char base64url HMAC), blob (base64url), updatedAt, deleted}`;
answers add `seq`. E2E header:
`{version: 1, kdf: {alg: "argon2id", m, t, p, salt}, wrappedDek, wrappedDekRecovery?, check}`.

Auth: `Authorization: Bearer <token>` (apps) or the cookie (web; state-changing
requests need `X-BBU-Sync: 1` or a same-origin `Origin`). The identity is
verified with WebUntis `app/data` on an allowlisted host (`ALLOWED_HOSTS`).

Modules: `router.ts` (routes), `auth.ts` (sessions, cookie, CSRF, rate limits),
`identity.ts` (WebUntis check), `notes.ts` / `e2e.ts` (validation, handlers),
`db.ts` (all SQL), `http.ts` (JSON helpers). Schema: `migrations/0001_init.sql`.
