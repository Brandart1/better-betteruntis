# Self-hosted web version

The web build of BetterBetterUntis is served by a small Dart server
(`server/`, package `bbu_server`). It does three things:

1. Serves the Flutter web build (with SPA fallback, so URLs like
   `/timetable` work on reload).
2. Proxies WebUntis requests. Browsers can't call WebUntis directly (CORS), so
   the web app sends every request for `https://<host>/<path>?<query>` to the
   same-origin URL `/proxy/<host>/<path>?<query>` instead.
3. Answers `/healthz` with `200 ok` for monitoring.

The server stores nothing. Each browser keeps its own logins, and the
server never sees or keeps anything beyond the requests it forwards.

## Running with Docker Compose

```sh
docker compose up -d --build
```

This builds the web app (Flutter 3.47.9), compiles the server and starts it on
port 8080. The example `docker-compose.yml` only binds to `127.0.0.1:8080`
because it expects a reverse proxy on the same host (see below). Edit
`environment:` in the file to configure it.

The image is built `FROM scratch` (no shell). Its built-in health check runs
`/app/bbu_server --healthcheck`. The server runs as UID/GID 65532 and works
with `read_only: true`.

Plain Docker:

```sh
docker build -t better-betteruntis-web .
docker run -d -p 127.0.0.1:8080:8080 -e BBU_BASIC_AUTH='me:long-random-pw' better-betteruntis-web
```

## Running without Docker

```sh
# 1. Build the web app (from the repository root)
flutter pub get
flutter build web --release --no-web-resources-cdn

# 2. Build and run the server
cd server
dart pub get
dart compile exe bin/server.dart -o bbu_server
BBU_WEB_ROOT=../build/web ./bbu_server
```

For development, `dart run bin/server.dart` works too.
`--no-web-resources-cdn` matters: it makes CanvasKit/skwasm load from the
server itself instead of Google's CDN, so everything is same-origin.

## Configuration

| Variable            | Default                       | Meaning |
|---------------------|-------------------------------|---------|
| `PORT`              | `8080`                        | Listen port (binds `0.0.0.0`). |
| `BBU_WEB_ROOT`      | `web` (relative to the CWD); `/app/web` in the image | Directory containing the Flutter `build/web` output. |
| `BBU_ALLOWED_HOSTS` | `webuntis.com,*.webuntis.com` | Comma-separated upstream allowlist. Exact hosts or `*.suffix` wildcards; `*.x.com` matches subdomains only, not `x.com` itself. Add your school's host if it isn't under webuntis.com. |
| `BBU_BASIC_AUTH`    | unset (off)                   | `user:password` turns on HTTP basic auth for everything except `/healthz`. |
| `BBU_COEP`          | `credentialless`              | Value of `Cross-Origin-Embedder-Policy`. Set it to an empty string to leave the header out, or `require-corp` for strict isolation (this breaks the QR scanner, which loads its decoder from a CDN). |

If a value is invalid, the server refuses to start and says why.

## Proxy contract

```
<METHOD> /proxy/<host>/<path>?<query>   ->   <METHOD> https://<host>/<path>?<query>
```

- `<host>` is matched case-insensitively and must be a plain DNS name
  (`[a-z0-9.-]`, valid labels, no port, no userinfo, no percent-encoding, no
  IP literals) that is on `BBU_ALLOWED_HOSTS`. Anything else gets **403**.
- `<path>` and `<query>` are forwarded byte for byte (percent-encoding is
  kept). Paths with `.`/`..` segments, empty segments (`//`) or encoded
  backslashes get 403. The upstream URL is built from its parts, so the path
  can't change the scheme, host or port. Only HTTPS on port 443 is used.
- Methods: `GET`, `POST`, `HEAD`. Others get **405**.
- Request headers forwarded: `Content-Type`, `Accept`, `Accept-Language`, and
  `Authorization` **only if it's `Bearer ...`**. Basic credentials, cookies,
  Origin, Referer and the rest are dropped. The User-Agent is set to
  `BetterBetterUntis-Web/1.0`.
- Response: upstream status, body and `Content-Type` only, plus
  `Cache-Control: no-store`. `Set-Cookie`, `Location` and all other upstream
  headers are dropped. Redirects are not followed.
- Limits: request body 1 MB (**413**), upstream response 32 MB (**502**),
  45 s total upstream time (**504**). If the upstream connection, DNS lookup
  or TLS handshake fails, the response is **502**.
- Logs show method, host, path (without the query), status and duration.
  Request bodies, queries and auth headers are never logged.

## Response headers

All responses get `Cross-Origin-Opener-Policy: same-origin`,
`Cross-Origin-Embedder-Policy: credentialless` (configurable, see above),
`X-Content-Type-Options: nosniff` and `Referrer-Policy: no-referrer`.

Caching: `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`,
`version.json`, `manifest.json` and all `.js/.mjs/.wasm/.json` files are sent
with `Cache-Control: no-cache` and an ETag. Flutter doesn't hash those
filenames, so browsers revalidate them and get a cheap 304 when nothing changed.
Fonts, images and other assets are cached for a day.

## Security

- **Serve it over HTTPS.** Your WebUntis password and app secret cross the
  network on every request, and browsers only allow camera access (QR login)
  on HTTPS origins or `localhost`. Logins are kept in the browser's
  localStorage (browsers have no keychain), so they are as safe as that
  browser profile. Put a reverse proxy in front of it and let that handle
  TLS. With Caddy:

  ```
  untis.example.lan {
      reverse_proxy 127.0.0.1:8080
  }
  ```

  Traefik or nginx work the same way: plain HTTP to port 8080, with TLS
  handled by the proxy.
- **Don't expose it to the internet without protection.** Use a VPN
  (WireGuard, Tailscale, ...) or set `BBU_BASIC_AUTH`. The allowlist stops the
  proxy from reaching arbitrary hosts, but an unprotected server still lets
  anyone use your server to reach WebUntis.
- Logins (WebUntis passwords and tokens) are stored **in each user's
  browser**, never on the server. They pass through the proxy in request
  bodies and `Authorization: Bearer` headers, so trust whoever runs the server
  and the reverse proxy in front of it.
- With basic auth on, a successful login also sets an `HttpOnly`,
  `SameSite=Strict` cookie (`bbu_auth`, valid for 30 days). This is needed
  because the app's REST calls send their own `Authorization: Bearer` header,
  and then the browser no longer adds the cached basic credentials. The cookie
  is an HMAC of the configured credentials, so changing the password logs
  everyone out. It gets the `Secure` flag when the request arrives over HTTPS
  or with `X-Forwarded-Proto: https`. The cookie and basic credentials are
  never forwarded to WebUntis.
