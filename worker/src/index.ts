/**
 * BetterBetterUntis Worker entry point. Static assets (the web app) are
 * served by Cloudflare directly; the Worker only runs for /proxy/* (WebUntis
 * relay) and /api/* (optional notes sync). See ../docs/SYNC-PLAN.md.
 */
import type { Env } from "./env";
import { withSecurityHeaders } from "./http";
import { handleProxy } from "./proxy";
import { purgeExpiredSessions, purgeTombstones, TOMBSTONE_MAX_AGE_MS } from "./sync/db";
import { handleSync } from "./sync/router";

async function route(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (path === "/healthz") {
    return new Response("ok", {
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  if (path === "/proxy" || path.startsWith("/proxy/")) {
    return handleProxy(request, env, ctx);
  }
  if (path === "/api/sync" || path.startsWith("/api/sync/")) {
    return handleSync(request, env, ctx);
  }
  // Asset responses get their headers from public/_headers.
  return env.ASSETS.fetch(request);
}

/** The daily cron's work (exported for tests). */
export async function dailyCleanup(db: D1Database, now: number): Promise<void> {
  for (let i = 0; i < 20; i++) {
    if ((await purgeExpiredSessions(db, now)) < 1000) break;
  }
  for (let i = 0; i < 20; i++) {
    if ((await purgeTombstones(db, now - TOMBSTONE_MAX_AGE_MS)) < 1000) break;
  }
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const res = await route(request, env, ctx);
    // Worker-generated responses (/proxy, /api, /healthz) need the same
    // security headers as the assets; setting them again on assets is harmless.
    return withSecurityHeaders(res);
  },

  /**
   * Daily cron (wrangler.jsonc triggers): removes expired sync sessions and
   * tombstones not written for 400 days (bounded: at most 20 000 each).
   */
  async scheduled(controller, env, _ctx): Promise<void> {
    await dailyCleanup(env.DB, controller.scheduledTime || Date.now());
  },
} satisfies ExportedHandler<Env>;
