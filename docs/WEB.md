# Web version

The web version of BetterBetterUntis is hosted on **Cloudflare**: a Worker
with static assets (`worker/`) that is deployed automatically by the release
workflow. It does three things:

1. Serves the Flutter web build (with SPA fallback, so URLs like
   `/timetable` work on reload).
2. Relays WebUntis requests. Browsers can't call WebUntis directly (CORS), so
   the web app sends every request for `https://<host>/<path>?<query>` to the
   same-origin URL `/proxy/<host>/<path>?<query>` instead
   (`lib/app/web_proxy.dart`).
3. Hosts the optional notes sync (`/api/sync/...`, see
   [SYNC-PLAN.md](SYNC-PLAN.md)).

The relay stores nothing. Each browser keeps its own logins (localStorage),
and the Worker never keeps anything beyond the requests it forwards. What the
sync stores is described in [PRIVACY.md](PRIVACY.md).

Deployment, local development, rollback and database operations are in
[worker/README.md](../worker/README.md).

## Which version

- **Production** (beta and stable releases): `https://better-betteruntis.eu` (also reachable at `https://better-betteruntis.brandart1.workers.dev`).
- **Alpha preview**: only while the repository variable `ALPHA_SYNC` is `on`
  (since 0.5.0-beta it is off), alpha releases are uploaded under the preview
  alias `alpha`, `https://alpha-better-betteruntis.brandart1.workers.dev`. It
  shares the sync database with production.

## Building it yourself

```sh
flutter pub get
flutter build web --release --no-web-resources-cdn
cp -R build/web/. worker/public/   # keeps worker/public/_headers
cd worker && npm ci && npx wrangler dev
```

`--no-web-resources-cdn` matters: it makes CanvasKit/skwasm load from the
same origin instead of Google's CDN.

## Relay contract

```
<METHOD> /proxy/<host>/<path>?<query>   ->   <METHOD> https://<host>/<path>?<query>
```

- `<host>` is matched case-insensitively and must be a plain DNS name
  (`[a-z0-9.-]`, valid labels, no port, no userinfo, no percent-encoding, no
  IP literals) on the allowlist (`ALLOWED_HOSTS` in `worker/wrangler.jsonc`,
  default `webuntis.com,*.webuntis.com`). Anything else gets **403**.
- `<path>` and `<query>` are forwarded as sent (percent-encoding is kept).
  Paths with `.`/`..` segments, empty segments (`//`) or encoded backslashes
  get 403. Only HTTPS on port 443 is used.
- Methods: `GET`, `POST`, `HEAD`. Others get **405**.
- Request headers forwarded: `Content-Type`, `Accept`, `Accept-Language`,
  `Authorization` **only if it's `Bearer ...`**, and `X-CSRF-TOKEN`,
  `X-XSRF-TOKEN`, `Tenant-Id`. The browser's cookies, Origin, Referer and
  the rest are dropped. The User-Agent is set to `BetterBetterUntis-Web/1.0`.
- **WebUntis website session** (since 0.5.8+161): reporting an absence and
  its reasons accept only the WebUntis website's session cookie, which a
  browser never shows the app. The app sends that session in
  `X-BBU-Cookie`; the relay sends it upstream as `Cookie`, with `Origin` /
  `Referer` of the school's own site (set by the relay, never taken from the
  browser). At most 4 096 characters, no line breaks (**400**).
- Response: upstream status, body and `Content-Type` only, plus
  `Cache-Control: no-store`. Upstream `Set-Cookie` comes back only as
  `X-BBU-Set-Cookie` (a JSON array of `name=value`, no attributes), never as
  a cookie of this site; the app keeps it in memory for the open tab only.
  `Location` and all other upstream headers are dropped. Redirects are not
  followed.
- Limits: request body 1 MB (**413**), upstream response 32 MB (**502**),
  45 s upstream time (**504**), 300 requests per minute per IP (**429**).
- Nothing is logged: no bodies, queries, auth headers or hosts.

## Response headers

All responses get `Cross-Origin-Opener-Policy: same-origin`,
`Cross-Origin-Embedder-Policy: credentialless`, `X-Content-Type-Options:
nosniff` and `Referrer-Policy: no-referrer` (`worker/public/_headers` for
the app's files, the Worker for `/proxy` and `/api`).

Caching: `index.html` and all `.js/.mjs/.wasm/.json` files are sent with
`Cache-Control: no-cache` (Flutter doesn't hash those filenames, so browsers
revalidate them). Fonts, images and other assets are cached for a day.

## Security notes

- Logins (WebUntis passwords and tokens) are stored **in each user's
  browser**, never on the server. They pass through the relay in request
  bodies and `Authorization: Bearer` headers, so the relay has to be trusted;
  its code is in `worker/src/proxy.ts`.
- Logins in localStorage are as safe as that browser profile (browsers have
  no keychain). Use the phone apps on shared computers.

## Self-hosting (removed in 0.5.0)

Up to 0.4.x the web version came with a small Dart server (`server/`,
Docker image, `…-web-linux-x64.tar.gz` release asset) for self-hosting. It
was removed in 0.5.0 in favour of the hosted version. To get it, check out a
0.4.x tag, e.g. `git checkout v0.4.8-alpha.7`, and follow `docs/WEB.md`
there, or download the web tarball from a 0.4.x release.
