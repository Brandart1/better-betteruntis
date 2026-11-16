import { describe, expect, it } from "vitest";
import { HostAllowlist } from "../../src/allowlist";
import { HttpError } from "../../src/sync/http";
import {
  APP_DATA_PATH,
  decodeJwtPayload,
  isAnonymousAppData,
  parseAppDataIdentity,
  verifyUntisIdentity,
  type FetchFn,
} from "../../src/sync/identity";

/** Anonymised, trimmed `app/data` answer (shape as observed from WebUntis). */
function appData(o: { userId?: unknown; tenantName?: unknown; tenantId?: unknown } = {}) {
  return {
    currentSchoolYear: { id: 1, name: "2026/2027" },
    tenant: {
      displayName: "Demo School",
      id: "tenantId" in o ? o.tenantId : "1234500",
      wuHostName: null,
      name: "tenantName" in o ? o.tenantName : "demo-school",
    },
    user: {
      id: "userId" in o ? o.userId : 4711,
      name: "student1",
      person: { displayName: "Student One", id: 99 },
      roles: ["STUDENT"],
    },
    holidays: [],
  };
}

function b64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function jwt(payload: unknown): string {
  return `${b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${b64url(JSON.stringify(payload))}.c2ln`;
}

const allowlist = HostAllowlist.parse("webuntis.com,*.webuntis.com");
const now = Date.UTC(2026, 10, 15, 12);
const nowSecs = Math.floor(now / 1000);

interface Sent {
  url: string;
  init: RequestInit | undefined;
}

function upstream(reply: () => Response | Promise<Response>): { fetch: FetchFn; sent: Sent[] } {
  const sent: Sent[] = [];
  return {
    sent,
    fetch: async (input, init) => {
      sent.push({ url: String(input), init });
      return reply();
    },
  };
}

const ok = (body: unknown = appData()) => Response.json(body);

async function fails(p: Promise<unknown>): Promise<HttpError> {
  try {
    await p;
  } catch (e) {
    if (e instanceof HttpError) return e;
    throw e;
  }
  throw new Error("expected HttpError");
}

describe("parseAppDataIdentity", () => {
  it("reads user.id, tenant.name and tenant.id", () => {
    expect(parseAppDataIdentity(appData())).toEqual({ userId: "4711", tenantName: "demo-school", tenantId: "1234500" });
  });

  it("accepts string ids, tolerates missing tenant.id", () => {
    const id = parseAppDataIdentity(appData({ userId: "u-1", tenantId: null }))!;
    expect(id.userId).toBe("u-1");
    expect(id.tenantId).toBeNull();
  });

  it("null on odd shapes", () => {
    const tenant = appData().tenant;
    for (const j of [
      null,
      [],
      "x",
      { user: {}, tenant: {} },
      appData({ userId: null }),
      appData({ userId: -1 }),
      appData({ userId: 1.5 }),
      appData({ userId: "" }),
      appData({ userId: "a|b" }),
      appData({ userId: "a b" }),
      appData({ userId: { id: 1 } }),
      appData({ tenantName: null }),
      appData({ tenantName: "  " }),
      appData({ tenantName: 7 }),
      { user: "x", tenant },
    ]) {
      expect(parseAppDataIdentity(j), JSON.stringify(j)).toBeNull();
    }
  });
});

describe("decodeJwtPayload", () => {
  it("decodes a payload, null for non-JWTs", () => {
    expect(decodeJwtPayload(jwt({ tenant_id: 5 }))!["tenant_id"]).toBe(5);
    expect(decodeJwtPayload("abc")).toBeNull();
    expect(decodeJwtPayload("a.%%%.c")).toBeNull();
    expect(decodeJwtPayload(`a.${b64url("[1]")}.c`)).toBeNull();
    expect(decodeJwtPayload(`a.${b64url("not json")}.c`)).toBeNull();
  });
});

describe("verifyUntisIdentity", () => {
  const base = { school: "Demo-School", allowlist, now };

  it("success: request shape and identity", async () => {
    const u = upstream(() => ok());
    const token = jwt({ tenant_id: "1234500", exp: nowSecs + 600 });
    const id = await verifyUntisIdentity({ ...base, host: "Demo.WebUntis.com", untisToken: token, fetch: u.fetch });
    expect(id).toEqual({ host: "demo.webuntis.com", school: "demo-school", userId: "4711" });
    expect(u.sent).toHaveLength(1);
    expect(u.sent[0]!.url).toBe(`https://demo.webuntis.com${APP_DATA_PATH}`);
    const h = new Headers(u.sent[0]!.init?.headers);
    expect(h.get("authorization")).toBe(`Bearer ${token}`);
    expect(h.get("accept")).toBe("application/json");
    expect(h.get("user-agent")).toContain("BetterBetterUntis");
    expect(u.sent[0]!.init?.redirect).toBe("manual");
    expect(u.sent[0]!.init?.method).toBe("GET");
  });

  it("school stored as WebUntis spells it, lower case", async () => {
    const u = upstream(() => ok(appData({ tenantName: "  Demo-SCHOOL " })));
    const id = await verifyUntisIdentity({ ...base, school: "demo-school", host: "x.webuntis.com", untisToken: "t", fetch: u.fetch });
    expect(id.school).toBe("demo-school");
  });

  it("host not allowlisted -> 403, no upstream call", async () => {
    for (const host of ["evil.com", "webuntis.com.evil.com", "evilwebuntis.com", "1.2.3.4", "x.webuntis.com:8443", "", "a..webuntis.com"]) {
      const u = upstream(() => ok());
      const e = await fails(verifyUntisIdentity({ ...base, host, untisToken: "t", fetch: u.fetch }));
      expect(e.status, host).toBe(403);
      expect(e.code).toBe("host_not_allowed");
      expect(u.sent).toHaveLength(0);
    }
  });

  it("WebUntis 401/403 -> 401 invalid_token", async () => {
    for (const status of [401, 403]) {
      const u = upstream(() => new Response("no", { status }));
      const e = await fails(verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: "t", fetch: u.fetch }));
      expect([e.status, e.code]).toEqual([401, "invalid_token"]);
    }
  });

  it("malformed or expired token -> 401 without upstream call", async () => {
    for (const token of ["has space", "a\nb", "x".repeat(8193), jwt({ exp: nowSecs - 3600 })]) {
      const u = upstream(() => ok());
      const e = await fails(verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: token, fetch: u.fetch }));
      expect([e.status, e.code]).toEqual([401, "invalid_token"]);
      expect(u.sent).toHaveLength(0);
    }
  });

  it("odd answers -> 502 unexpected_response", async () => {
    const replies: (() => Response)[] = [
      () => new Response("x", { status: 500 }),
      () => new Response(null, { status: 302, headers: { location: "https://evil.com/" } }),
      () => new Response("not json"),
      () => Response.json({ user: {} }),
      () => new Response(new Uint8Array([0xff, 0xfe])),
      () => new Response("x".repeat(4 * 1024 * 1024 + 1)),
    ];
    for (const reply of replies) {
      const u = upstream(reply);
      const e = await fails(verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: "t", fetch: u.fetch }));
      expect([e.status, e.code]).toEqual([502, "unexpected_response"]);
    }
  });

  it("anonymous (public timetable) access -> 403 anonymous_not_allowed", async () => {
    for (const name of ["#anonymous#", " #ANONYMOUS# "]) {
      const body = appData();
      body.user.name = name;
      const u = upstream(() => ok(body));
      const e = await fails(verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: "t", fetch: u.fetch }));
      expect([e.status, e.code]).toEqual([403, "anonymous_not_allowed"]);
    }
    expect(isAnonymousAppData(appData())).toBe(false);
    expect(isAnonymousAppData({ user: { name: 5 } })).toBe(false);
    expect(isAnonymousAppData(null)).toBe(false);
  });

  it("school mismatch -> 401", async () => {
    const u = upstream(() => ok());
    const e = await fails(verifyUntisIdentity({ ...base, school: "other-school", host: "x.webuntis.com", untisToken: "t", fetch: u.fetch }));
    expect([e.status, e.code]).toEqual([401, "school_mismatch"]);
  });

  it("JWT tenant_id contradicting app/data -> 401", async () => {
    const u = upstream(() => ok());
    const e = await fails(
      verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: jwt({ tenant_id: 999 }), fetch: u.fetch }),
    );
    expect(e.code).toBe("school_mismatch");
    // A matching numeric tenant_id is fine.
    const ok2 = await verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: jwt({ tenant_id: 1234500 }), fetch: u.fetch });
    expect(ok2.userId).toBe("4711");
  });

  it("unreachable -> 502 upstream_unreachable", async () => {
    const fetchFn: FetchFn = async () => {
      throw new TypeError("network");
    };
    const e = await fails(verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: "t", fetch: fetchFn }));
    expect([e.status, e.code]).toEqual([502, "upstream_unreachable"]);
  });

  it("passes an abort signal (timeout)", async () => {
    const u = upstream(() => ok());
    await verifyUntisIdentity({ ...base, host: "x.webuntis.com", untisToken: "t", fetch: u.fetch });
    expect(u.sent[0]!.init?.signal).toBeInstanceOf(AbortSignal);
  });
});
