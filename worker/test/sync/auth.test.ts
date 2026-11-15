import { SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { hashSessionToken, SESSION_TTL_MS } from "../../src/sync/auth";
import { type UpstreamCall, call, fakeUntis, freshIp, freshUser, get, HOST, identityId, login, note, ORIGIN, put, req } from "./helpers";

function sessionReq(body: unknown, headers: Record<string, string> = {}): Request {
  return req("POST", "/api/sync/session", { body, headers: { "cf-connecting-ip": freshIp(), ...headers } });
}

async function errorOf(res: Response): Promise<string> {
  return ((await res.json()) as { error: string }).error;
}

describe("POST /api/sync/session", () => {
  it("success: token, cookie, stored hash only, identity, e2e flag", async () => {
    const user = freshUser();
    const t0 = Date.UTC(2026, 10, 15, 12);
    const res = await call(sessionReq({ host: "Nessa.WebUntis.com", school: "Demo-School", untisToken: `tok.${user}.demo-school` }), {
      now: () => t0,
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    const body = (await res.json()) as { token: string; expiresAt: string; identity: unknown; e2e: boolean };
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.expiresAt).toBe(new Date(t0 + SESSION_TTL_MS).toISOString());
    expect(body.identity).toEqual({ host: HOST, school: "demo-school", userId: user });
    expect(body.e2e).toBe(false);
    const cookie = res.headers.get("set-cookie")!;
    expect(cookie).toBe(`bbu_sync=${body.token}; Path=/api/sync; HttpOnly; Secure; SameSite=Strict; Max-Age=7776000`);

    // Only the SHA-256 of the token is stored, nowhere the token itself.
    const id = await identityId(user);
    const rows = await env.DB.prepare("SELECT * FROM sessions WHERE identity_id = ?").bind(id).all();
    expect(rows.results).toHaveLength(1);
    const row = rows.results[0] as Record<string, unknown>;
    expect(row["token_hash"]).toBe(await hashSessionToken(body.token));
    expect(row["token_hash"]).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(row)).not.toContain(body.token);
    expect(row["expires_at"]).toBe(t0 + SESSION_TTL_MS);
  });

  it("tokens differ between logins, same identity", async () => {
    const user = freshUser();
    const a = await login(user);
    const b = await login(user);
    expect(a.token).not.toBe(b.token);
    expect(a.body.identity).toEqual(b.body.identity);
    const n = await env.DB.prepare("SELECT count(*) AS c FROM identities WHERE user_id = ?").bind(user).first<{ c: number }>();
    expect(n!.c).toBe(1);
  });

  it("host not allowed -> 403, WebUntis never asked", async () => {
    const calls: UpstreamCall[] = [];
    const res = await call(sessionReq({ host: "evil.example.com", school: "x", untisToken: "tok.1.x" }), { fetch: fakeUntis(calls) });
    expect(res.status).toBe(403);
    expect(await errorOf(res)).toBe("host_not_allowed");
    expect(calls).toHaveLength(0);
  });

  it("WebUntis 401 -> 401 invalid_token; school mismatch -> 401", async () => {
    let res = await call(sessionReq({ host: HOST, school: "x", untisToken: "tok.reject.x" }));
    expect([res.status, await errorOf(res)]).toEqual([401, "invalid_token"]);
    res = await call(sessionReq({ host: HOST, school: "other", untisToken: "tok.1.demo-school" }));
    expect([res.status, await errorOf(res)]).toEqual([401, "school_mismatch"]);
  });

  it("odd JSON from WebUntis -> 502", async () => {
    const res = await call(sessionReq({ host: HOST, school: "x", untisToken: "tok.1.x" }), {
      fetch: async () => Response.json({ hello: 1 }),
    });
    expect([res.status, await errorOf(res)]).toEqual([502, "unexpected_response"]);
  });

  it("bad bodies -> 400 / 415 / 413", async () => {
    for (const body of ["[]", "nope", "{}", JSON.stringify({ host: HOST, school: " ", untisToken: "t" }), JSON.stringify({ host: 1, school: "s", untisToken: "t" })]) {
      const res = await call(sessionReq(body));
      expect(res.status, body).toBe(400);
      expect(await errorOf(res)).toBe("bad_request");
    }
    const form = new Request(`${ORIGIN}/api/sync/session`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", "cf-connecting-ip": freshIp() },
      body: "host=x",
    });
    expect((await call(form)).status).toBe(415);
    const big = await call(sessionReq({ host: HOST, school: "s", untisToken: "x".repeat(20000) }));
    expect(big.status).toBe(413);
  });

  it("cross-site Origin -> 403; own origin is fine", async () => {
    const user = freshUser();
    const body = { host: HOST, school: "s", untisToken: `tok.${user}.s` };
    const evil = await call(sessionReq(body, { origin: "https://evil.example" }));
    expect([evil.status, await errorOf(evil)]).toEqual([403, "csrf_rejected"]);
    const own = await call(sessionReq(body, { origin: ORIGIN }));
    expect(own.status).toBe(200);
  });

  it("browser login (Origin present): token only in the HttpOnly cookie, not in the body", async () => {
    const user = freshUser();
    const body = { host: HOST, school: "s", untisToken: `tok.${user}.s` };
    const web = await call(sessionReq(body, { origin: ORIGIN }));
    expect(web.status).toBe(200);
    const json = (await web.json()) as Record<string, unknown>;
    expect(json).not.toHaveProperty("token");
    expect(json["identity"]).toEqual({ host: HOST, school: "s", userId: user });
    const cookie = web.headers.get("set-cookie")!;
    const token = /^bbu_sync=([^;]+);/.exec(cookie)![1]!;
    expect((await call(req("GET", "/api/sync/notes", { headers: { cookie: `bbu_sync=${token}` } }))).status).toBe(200);
    // Native (no Origin): token in the body.
    const app = (await (await call(sessionReq(body))).json()) as Record<string, unknown>;
    expect(app["token"]).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("rate limit per client IP -> 429 with retry-after", async () => {
    const ip = freshIp();
    const statuses: number[] = [];
    let last: Response | undefined;
    for (let i = 0; i < 12; i++) {
      last = await call(req("POST", "/api/sync/session", { body: { host: "evil.com", school: "s", untisToken: "t" }, headers: { "cf-connecting-ip": ip } }));
      statuses.push(last.status);
    }
    expect(statuses.slice(0, 10).every((s) => s === 403)).toBe(true);
    expect(statuses[11]).toBe(429);
    expect(last!.headers.get("retry-after")).toBe("60");
    expect(await errorOf(last!)).toBe("rate_limited");
    // Another IP is unaffected.
    const other = await call(sessionReq({ host: "evil.com", school: "s", untisToken: "t" }));
    expect(other.status).toBe(403);
  });

  it("purges expired sessions and keeps at most 30 per identity", async () => {
    const user = freshUser();
    await login(user);
    const id = await identityId(user);
    await env.DB.prepare("INSERT INTO sessions VALUES ('expired-x-" + user + "', ?, 0, 1)").bind(id).run();
    await login(freshUser());
    const gone = await env.DB.prepare("SELECT count(*) AS c FROM sessions WHERE expires_at <= 1").first<{ c: number }>();
    expect(gone!.c).toBe(0);
    for (let i = 0; i < 32; i++) await login(user);
    const n = await env.DB.prepare("SELECT count(*) AS c FROM sessions WHERE identity_id = ?").bind(id).first<{ c: number }>();
    expect(n!.c).toBe(30);
  });
});

describe("session check", () => {
  it("bearer token and cookie both work", async () => {
    const s = await login(freshUser());
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(200);
    const viaCookie = await call(req("GET", "/api/sync/notes", { headers: { cookie: `other=1; bbu_sync=${s.token}` } }));
    expect(viaCookie.status).toBe(200);
  });

  it("basic auth header is ignored in favour of the cookie", async () => {
    const s = await login(freshUser());
    const res = await call(req("GET", "/api/sync/notes", { headers: { authorization: "Basic dTpw", cookie: `bbu_sync=${s.token}` } }));
    expect(res.status).toBe(200);
  });

  it("no / unknown / malformed token -> 401 unauthorized", async () => {
    for (const headers of [
      {} as Record<string, string>,
      { authorization: "Bearer " + "A".repeat(43) },
      { authorization: "Bearer short" },
      { authorization: "Bearer a b" },
      { cookie: "bbu_sync=" },
      { cookie: "bbu_sync=' OR 1=1 --" },
    ]) {
      const res = await call(req("GET", "/api/sync/notes", { headers }));
      expect(res.status, JSON.stringify(headers)).toBe(401);
      expect(await errorOf(res)).toBe("unauthorized");
    }
  });

  it("expired session -> 401 (by DB time and by clock)", async () => {
    const s = await login(freshUser());
    const ok = await call(req("GET", "/api/sync/notes", { token: s.token }), { now: () => Date.now() + SESSION_TTL_MS - 60_000 });
    expect(ok.status).toBe(200);
    const late = await call(req("GET", "/api/sync/notes", { token: s.token }), { now: () => Date.now() + SESSION_TTL_MS + 1000 });
    expect(late.status).toBe(401);
    await env.DB.prepare("UPDATE sessions SET expires_at = ? WHERE token_hash = ?").bind(Date.now() - 1, await hashSessionToken(s.token)).run();
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(401);
  });

  it("RL_SYNC is per identity: more sessions don't buy more requests", async () => {
    const s = await login(freshUser());
    const s2 = await login(s.body.identity.userId);
    let status = 0;
    for (let i = 0; i < 125 && status !== 429; i++) {
      status = (await call(req("GET", "/api/sync/notes?since=999999", { token: s.token }))).status;
    }
    expect(status).toBe(429);
    // Another session of the same identity is limited too; other users aren't.
    expect((await call(req("GET", "/api/sync/notes", { token: s2.token }))).status).toBe(429);
    const other = await login(freshUser());
    expect((await call(req("GET", "/api/sync/notes", { token: other.token }))).status).toBe(200);
  });

  it("RL_WRITE: 20 writes per minute per identity, reads still pass", async () => {
    const s = await login(freshUser());
    const s2 = await login(s.body.identity.userId);
    const statuses: number[] = [];
    for (let i = 0; i < 21; i++) statuses.push((await put(i % 2 ? s.token : s2.token, [note(`k${i}`, i + 1)])).status);
    expect(statuses.slice(0, 20).every((x) => x === 200)).toBe(true);
    expect(statuses[20]).toBe(429);
    expect((await call(req("PUT", "/api/sync/e2e", { token: s.token, body: {} }))).status).toBe(429);
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(200);
  });

  it("RL_AUTH per client IP before the session lookup (random tokens, IPv6 /64)", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 301; i++) {
      const token = (crypto.randomUUID().replace(/-/g, "") + "x".repeat(20)).slice(0, 43);
      // Different addresses of one /64 count together.
      const ip = `2001:db8:77:1:${i.toString(16)}::1`;
      const res = await call(req("GET", "/api/sync/notes", { token, headers: { "cf-connecting-ip": ip } }));
      statuses.push(res.status);
    }
    expect(statuses.slice(0, 300).every((x) => x === 401)).toBe(true);
    expect(statuses[300]).toBe(429);
    const other = await call(req("GET", "/api/sync/notes", { token: "y".repeat(43), headers: { "cf-connecting-ip": "2001:db8:78::1" } }));
    expect(other.status).toBe(401);
  });

  it("more than one bbu_sync cookie -> 401 (cookie tossing)", async () => {
    const s = await login(freshUser());
    const other = await login(freshUser());
    for (const cookie of [`bbu_sync=${s.token}; bbu_sync=${other.token}`, `bbu_sync=${s.token}; x=1; bbu_sync=${s.token}`]) {
      const res = await call(req("GET", "/api/sync/notes", { headers: { cookie } }));
      expect([res.status, await errorOf(res)]).toEqual([401, "unauthorized"]);
      // Also with a bearer token.
      expect((await call(req("GET", "/api/sync/notes", { token: s.token, headers: { cookie } }))).status).toBe(401);
    }
    const logout = await call(req("DELETE", "/api/sync/session", { headers: { cookie: `bbu_sync=${s.token}; bbu_sync=${other.token}`, "x-bbu-sync": "1" } }));
    expect(logout.status).toBe(401);
    expect(logout.headers.get("set-cookie")).toContain("Max-Age=0");
    // Nothing was logged out.
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(200);
    expect((await call(req("GET", "/api/sync/notes", { token: other.token }))).status).toBe(200);
  });
});

describe("CSRF", () => {
  it("cookie + PUT without same-origin signal -> 403", async () => {
    const s = await login(freshUser());
    for (const headers of [{} as Record<string, string>, { origin: "https://evil.example" }, { origin: "null" }, { "x-bbu-sync": "0" }]) {
      const res = await call(
        req("PUT", "/api/sync/notes", { body: { notes: [] }, headers: { cookie: `bbu_sync=${s.token}`, ...headers } }),
      );
      expect(res.status, JSON.stringify(headers)).toBe(403);
      expect(await errorOf(res)).toBe("csrf_rejected");
    }
    for (const [method, path] of [["DELETE", "/api/sync/account"], ["PUT", "/api/sync/e2e"], ["DELETE", "/api/sync/session"]] as const) {
      const res = await call(req(method, path, { headers: { cookie: `bbu_sync=${s.token}` } }));
      expect(res.status, path).toBe(403);
    }
    // Nothing was deleted.
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(200);
  });

  it("cookie + X-BBU-Sync: 1, own Origin or PUBLIC_ORIGIN passes", async () => {
    const s = await login(freshUser());
    const cookie = `bbu_sync=${s.token}`;
    const put1 = async (headers: Record<string, string>, e = env) =>
      (await call(req("PUT", "/api/sync/notes", { body: { notes: [] }, headers: { cookie, ...headers } }), {}, e)).status;
    expect(await put1({ "x-bbu-sync": "1" })).toBe(200);
    expect(await put1({ origin: ORIGIN })).toBe(200);
    expect(await put1({ origin: "https://bbu.example.org" })).toBe(403);
    expect(await put1({ origin: "https://bbu.example.org" }, { ...env, PUBLIC_ORIGIN: "https://bbu.example.org/" })).toBe(200);
  });

  it("cookie + GET needs no signal; bearer never does", async () => {
    const s = await login(freshUser());
    expect((await call(req("GET", "/api/sync/notes", { headers: { cookie: `bbu_sync=${s.token}`, origin: "https://evil.example" } }))).status).toBe(200);
    expect((await put(s.token, [note("k", 1)])).status).toBe(200);
  });
});

describe("DELETE /api/sync/session", () => {
  it("bearer logout deletes the session and clears the cookie", async () => {
    const s = await login(freshUser());
    const res = await call(req("DELETE", "/api/sync/session", { token: s.token }));
    expect(res.status).toBe(204);
    expect(res.headers.get("set-cookie")).toContain("Max-Age=0");
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(401);
    const n = await env.DB.prepare("SELECT count(*) AS c FROM sessions WHERE token_hash = ?").bind(await hashSessionToken(s.token)).first<{ c: number }>();
    expect(n!.c).toBe(0);
  });

  it("cookie logout needs the CSRF signal", async () => {
    const s = await login(freshUser());
    const res = await call(req("DELETE", "/api/sync/session", { headers: { cookie: `bbu_sync=${s.token}`, "x-bbu-sync": "1" } }));
    expect(res.status).toBe(204);
    expect((await call(req("GET", "/api/sync/notes", { token: s.token }))).status).toBe(401);
  });

  it("without a session: still 204; other sessions stay", async () => {
    const s = await login(freshUser());
    expect((await call(req("DELETE", "/api/sync/session"))).status).toBe(204);
    expect((await call(req("DELETE", "/api/sync/session", { token: "x".repeat(43) }))).status).toBe(204);
    expect((await get(s.token)).notes).toEqual([]);
  });
});

describe("through the Worker entry (SELF.fetch)", () => {
  afterEach(() => vi.restoreAllMocks());

  it("login, put, get with the global fetch mocked", async () => {
    const realFetch = globalThis.fetch;
    const upstream = fakeUntis();
    vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
      const url = String(input instanceof Request ? input.url : input);
      if (url.startsWith(`https://${HOST}/`)) return upstream(input, init);
      return realFetch(input, init);
    });
    const user = freshUser();
    const res = await SELF.fetch(`${ORIGIN}/api/sync/session`, {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": freshIp() },
      body: JSON.stringify({ host: HOST, school: "demo-school", untisToken: `tok.${user}.demo-school` }),
    });
    expect(res.status).toBe(200);
    const { token } = (await res.json()) as { token: string };
    const putRes = await SELF.fetch(`${ORIGIN}/api/sync/notes`, {
      method: "PUT",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ notes: [note("k1", 5, "hello")] }),
    });
    expect(putRes.status).toBe(200);
    expect(putRes.headers.get("x-content-type-options")).toBe("nosniff");
    const page = await SELF.fetch(`${ORIGIN}/api/sync/notes?since=0`, { headers: { authorization: `Bearer ${token}` } });
    expect(((await page.json()) as { notes: unknown[] }).notes).toHaveLength(1);
  });

  it("routing: unknown path -> 404 json, wrong method -> 405 with allow", async () => {
    const nf = await SELF.fetch(`${ORIGIN}/api/sync/nope`);
    expect(nf.status).toBe(404);
    expect(nf.headers.get("content-type")).toContain("application/json");
    expect(nf.headers.get("cache-control")).toBe("no-store");
    expect(await errorOf(nf)).toBe("not_found");
    expect((await SELF.fetch(`${ORIGIN}/api/sync`)).status).toBe(404);
    const na = await SELF.fetch(`${ORIGIN}/api/sync/notes`, { method: "POST" });
    expect(na.status).toBe(405);
    expect(na.headers.get("allow")).toBe("GET, PUT");
    expect(await errorOf(na)).toBe("method_not_allowed");
    expect((await SELF.fetch(`${ORIGIN}/api/sync/session`, { method: "GET" })).headers.get("allow")).toBe("POST, DELETE");
  });
});
