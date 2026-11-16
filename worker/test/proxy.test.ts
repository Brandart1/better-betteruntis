import { createExecutionContext, SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../src/env";
import { handleProxy, type ProxyOptions, UPSTREAM_USER_AGENT } from "../src/proxy";

const DEFAULT_UPSTREAM_HEADERS = {
  "content-type": "application/json;charset=UTF-8",
  "set-cookie": "JSESSIONID=abc; Path=/",
  "x-powered-by": "untis",
  "access-control-allow-origin": "*",
  location: "https://evil.com/",
};

/** Records upstream requests (with their bodies) and replies with a canned response. */
class Recorder {
  requests: { request: Request; body: Uint8Array }[] = [];
  constructor(
    private status = 200,
    private body: string | null = '{"ok":true}',
    private headers: Record<string, string> = DEFAULT_UPSTREAM_HEADERS,
  ) {}

  fetch = async (request: Request): Promise<Response> => {
    this.requests.push({ request, body: new Uint8Array(await request.arrayBuffer()) });
    return new Response(this.body, { status: this.status, headers: this.headers });
  };

  get single(): Request {
    expect(this.requests).toHaveLength(1);
    return this.requests[0]!.request;
  }
}

function testEnv(overrides: Partial<Env> = {}): Env {
  const allowAll: RateLimit = { limit: async () => ({ success: true }) };
  return { ...(env as unknown as Env), RL_PROXY: allowAll, ...overrides };
}

function req(method: string, pathAndQuery: string, init: RequestInit = {}): Request {
  return new Request(`https://bbu.test${pathAndQuery}`, { method, ...init });
}

function call(request: Request, options: ProxyOptions, e: Env = testEnv()): Promise<Response> {
  return handleProxy(request, e, createExecutionContext(), options);
}

describe("proxy target", () => {
  let rec: Recorder;
  beforeEach(() => {
    rec = new Recorder();
  });

  for (const path of [
    "/proxy/evil.com/WebUntis/jsonrpc.do",
    "/proxy/webuntis.com.evil.com/x",
    "/proxy/user@x.webuntis.com/x",
    "/proxy/user%40x.webuntis.com/x",
    "/proxy/x.webuntis.com:444/x",
    "/proxy/x.webuntis.com%3A444/x",
    "/proxy/evil.com%2Fx.webuntis.com/x",
    "/proxy/evil.com%2F@x.webuntis.com/x",
    "/proxy/x.webuntis.com%2F..%2F..%2Fevil.com/x",
    "/proxy/evil.com%23.webuntis.com/x",
    "/proxy/evil.com%5c.webuntis.com/x",
    "/proxy/evil.com\\.webuntis.com/x",
    "/proxy/127.0.0.1/x",
    "/proxy/[::1]/x",
    "/proxy/localhost/x",
    "/proxy/sch%C3%BCle.webuntis.com/x",
    "/proxy/",
    "/proxy",
    "/proxy//x.webuntis.com/x",
    "/proxy/x.webuntis.com//evil.com/x",
    "/proxy/x.webuntis.com/%2e%2e/evil.com/x",
    "/proxy/x.webuntis.com/a%5c..%5cb",
    "/proxy/x.webuntis.com/a%00b",
    "/proxy/x.webuntis.com/../evil.com/y", // resolved to /proxy/evil.com/y by URL parsing
  ]) {
    it(`rejects ${path}`, async () => {
      const res = await call(req("GET", path), { fetch: rec.fetch });
      expect(res.status, path).toBe(403);
      expect(await res.text()).toBe("Forbidden upstream host");
      expect(res.headers.get("cache-control")).toBe("no-store");
      expect(rec.requests).toHaveLength(0);
    });
  }

  it("uppercase host is normalised", async () => {
    const res = await call(req("GET", "/proxy/MESE.WebUntis.com/WebUntis/"), { fetch: rec.fetch });
    expect(res.status).toBe(200);
    expect(new URL(rec.single.url).host).toBe("mese.webuntis.com");
  });

  it("accepts punycode hosts", async () => {
    await call(req("GET", "/proxy/xn--schle-kva.webuntis.com/x"), { fetch: rec.fetch });
    expect(rec.single.url).toBe("https://xn--schle-kva.webuntis.com/x");
  });

  it("builds the https URL and preserves the query verbatim", async () => {
    const query = "?m=getUserData2017&school=Gym%20Musterstadt&v=i2.2&a=%2F%3D";
    const res = await call(
      req("POST", `/proxy/mese.webuntis.com/WebUntis/jsonrpc_intern.do${query}`, {
        headers: { "content-type": "application/json" },
        body: '{"id":"1","method":"getUserData2017"}',
      }),
      { fetch: rec.fetch },
    );
    expect(res.status).toBe(200);
    const u = new URL(rec.single.url);
    expect(rec.single.url).toBe(`https://mese.webuntis.com/WebUntis/jsonrpc_intern.do${query}`);
    expect(u.protocol).toBe("https:");
    expect(u.port).toBe("");
    expect(u.username + u.password).toBe("");
  });

  it("encoded slashes in the path stay inside the path", async () => {
    await call(req("GET", "/proxy/x.webuntis.com/a%2F%2Fevil.com/b"), { fetch: rec.fetch });
    const u = new URL(rec.single.url);
    expect(u.host).toBe("x.webuntis.com");
    expect(u.pathname).toBe("/a%2F%2Fevil.com/b");
  });

  it("bare host forwards to /", async () => {
    await call(req("GET", "/proxy/schoolsearch.webuntis.com"), { fetch: rec.fetch });
    expect(rec.single.url).toBe("https://schoolsearch.webuntis.com/");
  });

  it("trailing slash is kept", async () => {
    await call(req("GET", "/proxy/x.webuntis.com/WebUntis/"), { fetch: rec.fetch });
    expect(rec.single.url).toBe("https://x.webuntis.com/WebUntis/");
  });

  it("custom allowlist from the environment", async () => {
    const e = testEnv({ ALLOWED_HOSTS: "untis.example.org" });
    expect((await call(req("GET", "/proxy/untis.example.org/x"), { fetch: rec.fetch }, e)).status).toBe(200);
    expect((await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: rec.fetch }, e)).status).toBe(403);
  });

  it("invalid allowlist -> 500 without contacting upstream", async () => {
    const e = testEnv({ ALLOWED_HOSTS: "*" });
    expect((await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: rec.fetch }, e)).status).toBe(500);
    expect(rec.requests).toHaveLength(0);
  });
});

describe("proxy forwarding", () => {
  let rec: Recorder;
  beforeEach(() => {
    rec = new Recorder();
  });

  it("forwards only allowed request headers and a neutral UA", async () => {
    await call(
      req("GET", "/proxy/x.webuntis.com/WebUntis/api/rest/view/v1/app/data", {
        headers: {
          authorization: "Bearer tok123",
          accept: "application/json",
          "accept-language": "de",
          "content-type": "application/json",
          // The sync cookie (Path=/) reaches /proxy too; it must never go upstream.
          cookie: "__Host-bbu_sync=secret; bbu_sync=old",
          origin: "https://bbu.test",
          referer: "https://bbu.test/timetable",
          "user-agent": "Mozilla/5.0",
          "x-forwarded-for": "10.0.0.1",
          "cf-connecting-ip": "10.0.0.2",
          "cf-ray": "abc",
          "accept-encoding": "br",
          "x-bbu-sync": "1",
        },
      }),
      { fetch: rec.fetch },
    );
    const sent = rec.single.headers;
    expect(new Set([...sent.keys()])).toEqual(
      new Set(["authorization", "accept", "accept-language", "content-type", "user-agent"]),
    );
    expect(sent.get("authorization")).toBe("Bearer tok123");
    expect(sent.get("user-agent")).toBe(UPSTREAM_USER_AGENT);
    expect(sent.has("cookie")).toBe(false);
    expect([...sent.values()].join("\n")).not.toContain("secret");
  });

  it("basic-auth credentials are never forwarded upstream", async () => {
    await call(
      req("POST", "/proxy/x.webuntis.com/WebUntis/jsonrpc_intern.do", {
        headers: { authorization: "Basic dXNlcjpwYXNz" },
        body: "{}",
      }),
      { fetch: rec.fetch },
    );
    expect(rec.single.headers.has("authorization")).toBe(false);
  });

  it("forwards the body byte-for-byte", async () => {
    const body = new TextEncoder().encode('{"params":[{"auth":{"user":"ä"}}]}');
    await call(
      req("POST", "/proxy/x.webuntis.com/WebUntis/jsonrpc_intern.do", {
        headers: { "content-type": "application/json" },
        body,
      }),
      { fetch: rec.fetch },
    );
    expect(rec.single.method).toBe("POST");
    expect(rec.requests[0]!.body).toEqual(body);
    expect(rec.single.headers.get("content-type")).toBe("application/json");
  });

  it("returns only status, body and content-type", async () => {
    const r = new Recorder(418, "teapot");
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: r.fetch });
    expect(res.status).toBe(418);
    expect(await res.text()).toBe("teapot");
    expect(new Set([...res.headers.keys()])).toEqual(
      new Set(["content-type", "cache-control", "content-security-policy", "content-disposition"]),
    );
    expect(res.headers.get("content-type")).toBe("application/json;charset=UTF-8");
    expect(res.headers.get("cache-control")).toBe("no-store");
  });

  it("binary image answers (pupil photos) pass through byte-for-byte with the bearer token", async () => {
    // JPEG header plus every byte value, so nothing is re-encoded as text.
    const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...Array.from({ length: 256 }, (_, i) => i)]);
    let seen: Request | undefined;
    const res = await call(
      req("GET", "/proxy/x.webuntis.com/WebUntis/api/portrait/students/501", {
        headers: { accept: "image/*", authorization: "Bearer jwt" },
      }),
      {
        fetch: async (r) => {
          seen = r;
          return new Response(bytes, { status: 200, headers: { "content-type": "image/jpeg" } });
        },
      },
    );
    expect(seen?.url).toBe("https://x.webuntis.com/WebUntis/api/portrait/students/501");
    expect(seen?.headers.get("accept")).toBe("image/*");
    expect(seen?.headers.get("authorization")).toBe("Bearer jwt");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(bytes);
  });

  it("redirects are not followed and their location is dropped", async () => {
    const r = new Recorder(302, null);
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: r.fetch });
    expect(r.single.redirect).toBe("manual");
    expect(res.status).toBe(302);
    expect(res.headers.has("location")).toBe(false);
    expect(res.headers.has("set-cookie")).toBe(false);
  });

  it("204 and 304 pass through without a body", async () => {
    for (const status of [204, 304]) {
      const r = new Recorder(status, null);
      const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: r.fetch });
      expect(res.status).toBe(status);
      expect(await res.text()).toBe("");
    }
  });

  it("HEAD is forwarded without body", async () => {
    const res = await call(req("HEAD", "/proxy/x.webuntis.com/x"), { fetch: rec.fetch });
    expect(res.status).toBe(200);
    expect(rec.single.method).toBe("HEAD");
    expect(await res.text()).toBe("");
  });

  for (const m of ["PUT", "DELETE", "PATCH", "OPTIONS"]) {
    it(`rejects method ${m}`, async () => {
      const res = await call(req(m, "/proxy/x.webuntis.com/x"), { fetch: rec.fetch });
      expect(res.status).toBe(405);
      expect(res.headers.get("allow")).toBe("GET, POST, HEAD");
      expect(rec.requests).toHaveLength(0);
    });
  }

  it("request body over the limit -> 413", async () => {
    const big = new Uint8Array(1024 * 1024 + 1).fill(0x61);
    const res = await call(req("POST", "/proxy/x.webuntis.com/x", { body: big }), { fetch: rec.fetch });
    expect(res.status).toBe(413);
    expect(rec.requests).toHaveLength(0);
  });

  it("streamed body over the limit without content-length -> 413", async () => {
    let i = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(c) {
        if (i++ < 17) c.enqueue(new Uint8Array(64 * 1024).fill(0x61));
        else c.close();
      },
    });
    const request = req("POST", "/proxy/x.webuntis.com/x", { body: stream });
    expect(request.headers.has("content-length")).toBe(false);
    const res = await call(request, { fetch: rec.fetch });
    expect(res.status).toBe(413);
    expect(rec.requests).toHaveLength(0);
  });

  it("declared content-length over the limit -> 413 without reading", async () => {
    const res = await call(
      req("POST", "/proxy/x.webuntis.com/x", { body: "{}", headers: { "content-length": "99999999" } }),
      { fetch: rec.fetch, maxRequestBodyBytes: 1000 },
    );
    expect(res.status).toBe(413);
  });
});

describe("upstream failures", () => {
  it("timeout -> 504", async () => {
    const never = (): Promise<Response> => new Promise(() => {});
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: never, timeoutMs: 50 });
    expect(res.status).toBe(504);
  });

  it("aborts the upstream request on timeout", async () => {
    let signal: AbortSignal | undefined;
    const never = (r: Request): Promise<Response> => {
      signal = r.signal;
      return new Promise(() => {});
    };
    await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: never, timeoutMs: 20 });
    expect(signal?.aborted).toBe(true);
  });

  it("slow response body also counts towards the timeout", async () => {
    const slow = async (): Promise<Response> =>
      new Response(
        new ReadableStream<Uint8Array>({
          start(c) {
            c.enqueue(new Uint8Array([1])); // never closed
          },
        }),
      );
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: slow, timeoutMs: 50 });
    expect(res.status).toBe(504);
  });

  it("network error -> 502", async () => {
    const failing = async (): Promise<Response> => {
      throw new TypeError("Network connection lost.");
    };
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: failing });
    expect(res.status).toBe(502);
    expect(await res.text()).toBe("Upstream connection failed");
  });

  it("oversized upstream response -> 502", async () => {
    const big = async (): Promise<Response> => new Response("x".repeat(2000));
    const res = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: big, maxResponseBodyBytes: 1000 });
    expect(res.status).toBe(502);
    expect(await res.text()).toBe("Upstream response too large");
  });
});

describe("fetch metadata and sandboxing", () => {
  const CSP = "sandbox; default-src 'none'; frame-ancestors 'none'";

  for (const headers of [
    { "sec-fetch-dest": "document" },
    { "sec-fetch-dest": "iframe" },
    { "sec-fetch-dest": "object" },
    { "sec-fetch-dest": "embed" },
    { "sec-fetch-dest": "script" },
    { "sec-fetch-dest": "" },
    { "sec-fetch-site": "cross-site" },
    { "sec-fetch-dest": "empty", "sec-fetch-site": "cross-site" },
  ] as Record<string, string>[]) {
    it(`rejects ${JSON.stringify(headers)} with 403, upstream never called`, async () => {
      const rec = new Recorder();
      const res = await call(req("GET", "/proxy/x.webuntis.com/x", { headers }), { fetch: rec.fetch });
      expect(res.status).toBe(403);
      expect(res.headers.get("content-security-policy")).toBe(CSP);
      expect(rec.requests).toHaveLength(0);
    });
  }

  for (const headers of [
    {},
    { "sec-fetch-dest": "empty", "sec-fetch-site": "same-origin" },
    { "sec-fetch-dest": "EMPTY" },
    { "sec-fetch-site": "same-site" },
    { "sec-fetch-site": "none" },
  ] as Record<string, string>[]) {
    it(`allows ${JSON.stringify(headers)}`, async () => {
      const rec = new Recorder();
      const res = await call(req("GET", "/proxy/x.webuntis.com/x", { headers }), { fetch: rec.fetch });
      expect(res.status).toBe(200);
      expect(rec.requests).toHaveLength(1);
    });
  }

  it("every relay response is sandboxed and an attachment (success and errors)", async () => {
    const ok = await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: new Recorder(200, "<html><script>x</script>", { "content-type": "text/html" }).fetch });
    const bad = await call(req("GET", "/proxy/evil.com/x"), { fetch: new Recorder().fetch });
    for (const res of [ok, bad]) {
      expect(res.headers.get("content-security-policy")).toBe(CSP);
      expect(res.headers.get("content-disposition")).toBe("attachment");
    }
  });

  it("the Worker wrapper keeps the relay's CSP", async () => {
    const res = await SELF.fetch("https://bbu.test/proxy/evil.com/x");
    expect(res.headers.get("content-security-policy")).toBe(CSP);
    expect(res.headers.get("x-frame-options")).toBe("DENY");
  });

  it("navigations through the Worker are refused", async () => {
    const res = await SELF.fetch("https://bbu.test/proxy/x.webuntis.com/x", { headers: { "sec-fetch-dest": "document" } });
    expect(res.status).toBe(403);
  });
});

describe("rate limit", () => {
  it("429 with retry-after when the limiter says no, keyed by client IP", async () => {
    const keys: string[] = [];
    const deny: RateLimit = {
      limit: async ({ key }) => {
        keys.push(key);
        return { success: false };
      },
    };
    const rec = new Recorder();
    const res = await call(
      req("GET", "/proxy/x.webuntis.com/x", { headers: { "cf-connecting-ip": "203.0.113.7" } }),
      { fetch: rec.fetch },
      testEnv({ RL_PROXY: deny }),
    );
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("60");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.json()).toEqual({ error: "rate_limited" });
    expect(keys).toEqual(["203.0.113.7"]);
    expect(rec.requests).toHaveLength(0);
  });

  it("IPv6 clients are keyed by their /64", async () => {
    const keys: string[] = [];
    const spy: RateLimit = {
      limit: async ({ key }) => {
        keys.push(key);
        return { success: true };
      },
    };
    await call(
      req("GET", "/proxy/x.webuntis.com/x", { headers: { "cf-connecting-ip": "2001:db8:1:2:aaaa::7" } }),
      { fetch: new Recorder().fetch },
      testEnv({ RL_PROXY: spy }),
    );
    expect(keys).toEqual(["2001:db8:1:2::/64"]);
  });

  it("falls back to 'unknown' without CF-Connecting-IP", async () => {
    const keys: string[] = [];
    const spy: RateLimit = {
      limit: async ({ key }) => {
        keys.push(key);
        return { success: true };
      },
    };
    await call(req("GET", "/proxy/x.webuntis.com/x"), { fetch: new Recorder().fetch }, testEnv({ RL_PROXY: spy }));
    expect(keys).toEqual(["unknown"]);
  });
});

describe("through the Worker", () => {
  const security = {
    "cross-origin-opener-policy": "same-origin",
    "cross-origin-embedder-policy": "credentialless",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "strict-transport-security": "max-age=31536000",
  };

  function expectSecurityHeaders(res: Response): void {
    for (const [k, v] of Object.entries(security)) expect(res.headers.get(k), k).toBe(v);
  }

  it("routes /proxy to the relay (rejected host, no network)", async () => {
    const res = await SELF.fetch("https://bbu.test/proxy/evil.com/x");
    expect(res.status).toBe(403);
    expect(await res.text()).toBe("Forbidden upstream host");
    expectSecurityHeaders(res);
  });

  it("rejects other methods via the Worker", async () => {
    const res = await SELF.fetch("https://bbu.test/proxy/x.webuntis.com/x", { method: "PUT", body: "x" });
    expect(res.status).toBe(405);
    expectSecurityHeaders(res);
  });

  it("/healthz has the security headers", async () => {
    const res = await SELF.fetch("https://bbu.test/healthz");
    expectSecurityHeaders(res);
    expect(res.headers.get("content-security-policy")).toBe("frame-ancestors 'none'");
    expect(res.headers.get("cache-control")).toBe("no-store");
  });

  it("assets get the _headers security headers and revalidate", async () => {
    for (const path of ["/", "/index.html", "/timetable"]) {
      const res = await SELF.fetch(`https://bbu.test${path}`);
      expect(res.status, path).toBe(200);
      expect(await res.text()).toContain("BetterBetterUntis");
      expectSecurityHeaders(res);
      // "/" and "/index.html" from the explicit rule, SPA routes from the default.
      expect(res.headers.get("cache-control"), path).toMatch(/no-cache|max-age=0, must-revalidate/);
    }
  });

  it("public/_headers is applied by the assets binding itself", async () => {
    // env.ASSETS bypasses the Worker's wrapper, so these come from _headers.
    const index = await env.ASSETS.fetch("https://bbu.test/index.html");
    expectSecurityHeaders(index);
    expect(index.headers.get("content-security-policy")).toBe("frame-ancestors 'none'");
    expect(index.headers.get("cache-control")).toBe("no-cache");
    const root = await env.ASSETS.fetch("https://bbu.test/");
    expect(root.headers.get("cache-control")).toBe("no-cache");
    await index.body?.cancel();
    await root.body?.cancel();
  });
});
