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

> **Schema changes after the first deploy:** `migrations/0001_init.sql` was
> edited in place while nothing was deployed. **Once the first deploy has
> applied it, never edit it again: every schema change must be a NEW
> migration file** (`migrations/0002_<what>.sql`, …), additive (new
> tables/columns with defaults) and compatible with the version that is
> live (alphas share the production database, see "How releases deploy").

## Sync API (`src/sync/`)

All JSON, `cache-control: no-store`, errors `{"error": code, "message"}`.
Unknown paths → 404 `not_found`, wrong method → 405 with `allow`.

| Endpoint | Request → answer |
|---|---|
| `POST /api/sync/session` | `{host, school, untisToken}` → `{token, expiresAt, identity, e2e}` + cookie `__Host-bbu_sync`. **`token` is omitted when the request has an `Origin` header** (browsers use the HttpOnly cookie; native apps send no Origin) |
| `DELETE /api/sync/session` | → 204, clears the cookie (also without a session) |
| `GET /api/sync/notes?since=<seq>` | → `{notes, latestSeq, more, e2e, identity}` (1 000 per page) |
| `PUT /api/sync/notes` | `{notes: [...]}` (≤ 500, ≤ 1 MiB) → `{notes, latestSeq, e2e, identity}`; 413 `too_many_notes` / `storage_quota`; 429 `daily_limit` (`retry-after` = seconds to the next UTC midnight); 400 `clock_skew` with `serverTime`; 503 `busy` (`retry-after: 5`, only if a write lost 3 races in a row) |
| `GET /api/sync/e2e` | → header, or 404 `e2e_not_enabled` (both with response header `x-bbu-identity-epoch`) |
| `PUT /api/sync/e2e` | header (with `authHash`) → 201 (once; deletes plaintext notes), 409 `e2e_exists` |
| `PATCH /api/sync/e2e` | `{header: {... same authHash}, authKey}` → 200; 403 `e2e_auth_failed`, 404 `e2e_not_enabled` |
| `DELETE /api/sync/e2e` | `{authKey}` → 204: deletes the header and all notes, sessions stay (E2E off); 403 `e2e_auth_failed`, 404 `e2e_not_enabled` |
| `DELETE /api/sync/account` | → 204, deletes identity, notes, sessions, header |

`identity` is always `{"host": string, "school": string, "userId": string,
"epoch": string}` (POST /session, GET/PUT /notes; host and school lower
case, userId a string). It comes from the session, so a web client can
notice that the shared cookie now belongs to another account. **`epoch`**
is 16 random bytes (base64url, 22 chars) generated when the identity row is
created and never changed: the same for every session of that identity,
**different after `DELETE /account` + a new login** (also after an
operator deletion), unchanged by `DELETE /e2e` and by a D1 Time Travel
restore. A client that sees another epoch than it stored must treat the
server account as new (e.g. not re-upload into it without asking). The
`/e2e` answers keep their body (the bare header) and carry the epoch in the
response header **`x-bbu-identity-epoch`** (GET 200/404, PUT 201, PATCH
200, DELETE 204). The internal `identities.id` is never exposed.

Any authenticated call whose identity row disappeared between the session
lookup and the statement (concurrent account deletion) answers 401
`unauthorized`, never 200 with empty data.

Notes: plaintext `{key, exam, text, updatedAt, deleted}`, E2E
`{key (43-char base64url HMAC), blob (base64url), updatedAt, deleted}`;
answers add `seq`. Last write wins; an equal `updatedAt` keeps the stored
version (the answer returns it). **Plaintext tombstones (`deleted: true`)
are stored and returned blanked: `text: ""`, `exam: false`**, whatever the
client sent; E2E tombstones are opaque blobs and stored as sent. Seqs of
one PUT are `last_seq + position in the request + 1`, so notes of the
request that weren't written (older/tied) leave gaps. `clock_skew` (updatedAt > server time +
5 min) answers `{"error": "clock_skew", "message", "serverTime": <ms UTC>}`.

E2E header:
`{version: 1, kdf: {alg: "argon2id", m, t, p, salt}, wrappedDek, wrappedDekRecovery?, check, authHash}`.
Server-side bounds: m 19 456–65 536 (KiB), t 2–8, p 1–4, salt exactly
16 bytes; `authHash` = 43-char base64url of SHA-256(authKey), where
authKey (32 bytes) = HKDF-SHA256(DEK, info `"bbu-header-auth-v1"`). PATCH and
DELETE send `authKey` (43-char base64url); the server compares
SHA-256(authKey) with the stored `authHash` in constant time, and PATCH also
requires the new header's `authHash` to equal the stored one. `check` is not
compared (it may change). The server never sees the DEK; `authHash` is part
of the header returned by GET.

Limits: 500 notes / 1 MiB per request; per identity **5 000 live
(non-deleted) notes** (tombstones don't count here) and 5 MiB (UTF-8 bytes
of key + text/blob, tombstones included); a write that doesn't grow the
live count / the byte total passes even when over the limit (deleting
always works). **Daily write budget: 5 000 accepted note writes per
identity and UTC day** (every insert or overwrite counts 1, tombstones
included; notes that aren't written because the stored version is newer or
equal don't count). Over budget the whole PUT is refused (all or nothing)
with 429 `daily_limit` and `retry-after` = seconds until the next UTC
midnight. So the first full upload of a maximal account (5 000 notes = 10
PUTs of 500) fits in one day. The counters live on `identities`
(`note_count`, `bytes`, `budget_day`, `budget_used`) and are changed by ONE
aggregated, guarded UPDATE in the same batch as each write (no triggers),
so no request scans the notes.

D1 cost per PUT of 500 plaintext notes (measured with `meta.rows_read` /
`rows_written`, `test/sync/budget.test.ts` guards it):

| | rows written | rows read |
|---|---|---|
| 500 new notes | 1 001 (was 1 501) | 2 514 (was 7 010) |
| 500 overwrites | 1 001 (was 1 501) | 3 014 (was 8 510) |
| 500 older (nothing written) | 0 (was 1) | 3 010 (was 5 512) |
| 500 tombstones | 1 501 | 3 014 |

Per written note: the note row + its entry in the `(identity_id, seq)`
index (D1 counts index writes); tombstones also enter the partial purge
index. Dropping the seq index would halve the writes but make every
non-empty pull scan the whole account (up to 5 000 rows read per page).
The read-back of stored versions only runs for keys that weren't written;
the summary query that names a refusal only runs when nothing was written.

Rate limits (`wrangler.jsonc` `ratelimits`, 429 `rate_limited` +
`retry-after: 60`; IP keys use the IPv6 /64, see `src/ip.ts`):

| Binding | Limit | Key | Applies to |
|---|---|---|---|
| `RL_SESSION` | 30/min | client IP | `POST /session` (a school NAT where a class turns sync on together) |
| `RL_AUTH` | 300/min | client IP | only **failed** session lookups (unknown/expired token, also on logout); an IP over the limit is marked blocked for 60 s and gets 429 **before** the D1 lookup (mark in isolate memory + `caches.default`; the cache is a no-op on workers.dev, the memory mark and the limiter still apply) |
| `RL_SYNC` | 120/min | identity | every authenticated call |
| `RL_WRITE` | 20/min | identity | `PUT /notes`, `PUT/PATCH/DELETE /e2e` (on top of `RL_SYNC`) |
| `RL_PROXY` | 300/min | client IP | `/proxy/*` |

Daily cron (03:17 UTC): deletes expired sessions and **tombstones not
written on the server for 400 days** (column `stored_at`, server time; a
tombstone written again later is kept), lowering each identity's `bytes`
by the purged sizes in the same batch. A
device that was offline longer than that may keep, or re-upload, notes that
were deleted elsewhere.

Auth: `Authorization: Bearer <token>` (apps) or the cookie (web; state-changing
requests need `X-BBU-Sync: 1` or a same-origin `Origin`). Cookie:
`__Host-bbu_sync=<token>; Path=/; HttpOnly; Secure; SameSite=Strict;
Max-Age=7776000` (no Domain). The `__Host-` prefix means a sibling
(sub)domain can't set or overwrite it (no cookie tossing / fixation);
`Path=/` (required by the prefix) means it also reaches `/proxy/*` and the
assets, but the relay never forwards cookies upstream (tested). Logout,
account deletion and a rejected double cookie clear it with the same
attributes and `Max-Age=0`. A request with more than one `__Host-bbu_sync`
cookie still gets 401; the old name `bbu_sync` is ignored. The identity is
verified with WebUntis `app/data` on an allowlisted host (`ALLOWED_HOSTS`).

Relay: requests with `Sec-Fetch-Dest` other than `empty` or
`Sec-Fetch-Site: cross-site` get 403 (the app only uses fetch/XHR); every
relay response carries `Content-Security-Policy: sandbox; default-src
'none'; frame-ancestors 'none'` and `Content-Disposition: attachment`. All
Worker responses get `X-Frame-Options: DENY`, `frame-ancestors 'none'` (unless
a stricter CSP is set) and HSTS; the app gets the same via `public/_headers`
(frame-ancestors only, no full CSP: Flutter needs inline scripts/wasm).

Modules: `router.ts` (routes), `auth.ts` (sessions, cookie, CSRF, rate limits),
`identity.ts` (WebUntis check), `notes.ts` / `e2e.ts` (validation, handlers),
`db.ts` (all SQL), `http.ts` (JSON helpers); `../ip.ts` (rate-limit IP keys).
Schema: `migrations/0001_init.sql`.


**Retention (daily cron):** expired sessions, tombstones not written for 400
days, and sync accounts without a login for 12 months (no session left;
`identities.last_login`, migration 0002) are deleted, the latter with all
their notes and E2E header (privacy notice §2).

## Operations (maintainer)

### One-time Cloudflare setup

1. **Account:** create a Cloudflare account and turn on **2FA** (also on
   GitHub). Whoever controls either account can deploy a Worker that steals
   WebUntis passwords; this is the biggest single risk (SYNC-PLAN.md,
   security item 8).
2. **workers.dev subdomain:** Workers & Pages → pick a subdomain once. The
   Worker is then at `https://better-betteruntis.<subdomain>.workers.dev`,
   alphas at `https://alpha-better-betteruntis.<subdomain>.workers.dev`.
3. **Database** (from `worker/`, after `npx wrangler login`):

   ```sh
   npx wrangler d1 create bbu-sync --location weur   # or --jurisdiction eu
   ```

   Note the `database_id` it prints. `--jurisdiction eu` keeps the data in
   the EU (stronger than a location hint); it can't be changed later. Update
   the database location in `docs/PRIVACY.md` accordingly.
4. **API token:** My Profile → API Tokens → Create Token → template **Edit
   Cloudflare Workers**, then add **Account → D1 → Edit**. Account
   resources: only your account. Zone resources: only the zone of your
   custom domain (or none without one). Give it an expiry date and rotate
   it.
5. **GitHub** (Settings → Secrets and variables → Actions):
   - secret `CLOUDFLARE_API_TOKEN`: the token,
   - secret `CLOUDFLARE_ACCOUNT_ID`: the account id (dashboard sidebar /
     `npx wrangler whoami`),
   - **variable** `CLOUDFLARE_D1_ID`: the `database_id` from step 3. CI
     writes it into `wrangler.jsonc` in place of the placeholder
     `00000000-…`; the repository keeps the placeholder so local dev and
     tests never touch the real database.
   - **variable** `BBU_SYNC_URL`: the Worker's public URL (e.g.
     `https://better-betteruntis.<subdomain>.workers.dev` or your custom
     domain). The Android/iOS builds sync with it; without it they show
     "Sync isn't available in this build". (The web version always uses its
     own origin.)
   - **variable** `ALPHA_SYNC`: `on` lets alpha releases deploy the web
     preview and build the apps with sync. Keep it `on` only while sync
     itself is being developed (0.5.0 alphas); afterwards remove it (or set
     anything else): alphas then have no sync and no web preview, so alpha
     bugs can't reach the production sync database. Betas and stable
     releases are unaffected.
6. **First deploy** (once, by hand, so the Worker exists before an alpha
   tries to upload a preview version to it):

   ```sh
   flutter build web --release --no-web-resources-cdn   # repo root
   cp -R ../build/web/. public/                          # keeps public/_headers
   sed -i "s/00000000-0000-0000-0000-000000000000/<database_id>/" wrangler.jsonc
   npx wrangler d1 migrations apply bbu-sync --remote
   npx wrangler deploy
   git checkout wrangler.jsonc                            # back to the placeholder
   ```

7. **Custom domain (optional):** Worker → Settings → Domains & Routes → Add
   → Custom domain (the zone must be on Cloudflare). Then set
   `PUBLIC_ORIGIN` in `wrangler.jsonc` to `https://<domain>` and add Zone →
   Workers Routes → Edit for that zone to the API token if the domain is
   configured in `wrangler.jsonc` (`routes`). Fill in the URL in
   `docs/WEB.md` and `docs/PRIVACY.md`.
8. **WAF rate limit (recommended, on the custom domain's zone):** Security
   → WAF → Rate limiting rules: *URI Path equals `/api/sync/session`*,
   10 requests per 10 seconds per IP, action Block for 10 seconds. This
   stops floods before they reach the Worker (and its
   `RL_*` limits, which are per Cloudflare
   location). The free plan allows one such rule.
9. **Bot Fight Mode: leave it off** (Security → Bots). It challenges
   non-browser clients and can't be skipped per path on the free plan, so
   the phone apps' calls to `/api/*` would fail. If you use Super Bot Fight
   Mode (paid), add a skip rule for `/api/*` and `/proxy/*`.
10. **Usage limits:** on the free Workers plan requests beyond the daily
    limit fail instead of being billed. Keep request logging
    (`observability`) off, as configured.
    D1 on the free plan: 100 000 rows written and 5 M rows read per day for
    the whole app; when used up, sync fails for everyone until 00:00 UTC.
    The per-identity daily write budget keeps one account from using it up;
    watch D1 → Metrics and consider Workers Paid if the app grows
    (`docs/DECISIONS-PENDING.md` R6).

### How releases deploy

`.github/workflows/release.yml`, on a pushed `v*` tag:

- `web` builds the Flutter web app and uploads it as the `web-build`
  artifact.
- `cloudflare` checks that both secrets are set; if not (or for a manual
  `workflow_dispatch` rebuild of an old tag), `deploy-worker` is skipped.
- `deploy-worker` puts the web build into `public/` (next to `_headers`),
  substitutes `CLOUDFLARE_D1_ID`, runs `npm ci --strict-allow-scripts`, the
  typecheck and the tests, applies D1 migrations
  (`wrangler d1 migrations apply bbu-sync --remote`) and then:
  - **alpha** tags: `wrangler versions upload --preview-alias alpha` → new
    version at the `alpha-…workers.dev` preview URL, no production traffic;
  - **beta / stable** tags: `wrangler deploy` → production.

  Every version is tagged with the release tag (`--tag`, `--message`).
  Alphas use the **production database**, and migrations run before the
  code switches, so migrations must be additive (new tables/columns with
  defaults) and work with the version that is live.

The CI workflow (`ci.yml`) runs `npm ci`, `tsc --noEmit` and `vitest run`
for every push to `main` and every pull request.

### Rollback

- Dashboard: Worker → Deployments → pick an earlier version → Deploy.
- CLI: `npx wrangler deployments list`, then
  `npx wrangler rollback <version-id> -m "why"`.
- To promote an alpha preview to production without a new tag:
  `npx wrangler versions deploy <version-id>@100%`.

A rollback doesn't undo D1 migrations (another reason to keep them
additive).

### Restoring the database (D1 Time Travel)

D1 keeps a point-in-time history: **7 days on the free plan, 30 days on
Workers Paid**. This is the only backup; it is also the retention window
stated in `docs/PRIVACY.md`.

```sh
npx wrangler d1 time-travel info bbu-sync --timestamp 2026-11-15T12:00:00Z   # bookmark for a time
npx wrangler d1 time-travel restore bbu-sync --timestamp 2026-11-15T12:00:00Z
```

A restore replaces the **whole** database (the restore itself can be undone
with the bookmark it prints). Afterwards, delete again every account that was
deleted after the restore point (deletion requests you handled by hand, see
below; opt-outs from the app since then can't be listed, so announce the
restore or restore only to just before the fault).

### Deleting a user on request

Users can delete everything themselves by turning sync off. For a request by
e-mail, ask for the sync identity shown in the app (WebUntis host, school,
user id), then:

```sh
# find the identity (values are lower case; user_id is a string)
npx wrangler d1 execute bbu-sync --remote --command \
  "SELECT id, host, school, user_id, created_at FROM identities WHERE school = 'example-school' AND user_id = '1234'"

# delete it (replace 42 with the id from above)
npx wrangler d1 execute bbu-sync --remote --command \
  "DELETE FROM notes WHERE identity_id = 42; DELETE FROM e2e_headers WHERE identity_id = 42; DELETE FROM sessions WHERE identity_id = 42; DELETE FROM identities WHERE id = 42"
```

Foreign keys cascade anyway; the explicit deletes match what
`DELETE /api/sync/account` does. Only paste the values the user gave you
(no quotes inside them). The data stays in the Time Travel history until
that window has passed.

For an access request, the same `SELECT` plus
`SELECT key, exam, text, blob, updated_at, deleted FROM notes WHERE identity_id = 42`
shows everything stored (E2E notes are ciphertext).

## Teacher web alpha (no sync)
`wrangler.teacher-alpha.jsonc` is a second, web-only Worker for testing the
teacher branch in the browser: same code, but no D1 binding, no cron and only
the relay's rate limit. Without `DB`, `/api/sync/*` answers `404
{"error":"sync_disabled"}`, and the web build is made with
`--dart-define=BBU_NO_SYNC=true` (no Sync menu entry). Deploy by hand from
branch `teacher`:

    set -a; . /root/better-betteruntis-keys/cloudflare.env; set +a
    tool/deploy_teacher_alpha.sh

→ https://bbu-teacher-alpha.brandart1.workers.dev
