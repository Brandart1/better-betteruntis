/**
 * BetterBetterUntis Worker entry point. Static assets (the web app) are
 * served by Cloudflare directly; the Worker only runs for /proxy/* (WebUntis
 * relay) and /api/* (optional notes sync). See ../docs/SYNC-PLAN.md.
 */
import type { Env } from "./env";
import { withSecurityHeaders } from "./http";
import { handleProxy } from "./proxy";
import {
  INACTIVE_IDENTITY_MS,
  purgeExpiredSessions,
  purgeInactiveIdentities,
  purgeTombstones,
  TOMBSTONE_MAX_AGE_MS,
} from "./sync/db";
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
    // Deployments without a database (wrangler.teacher-alpha.jsonc: web
    // hosting + relay only) have no sync.
    if (!(env as { DB?: unknown }).DB) {
      return new Response(JSON.stringify({ error: "sync_disabled" }), {
        status: 404,
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    }
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
  // Privacy notice: sync accounts without a login for 12 months are deleted.
  for (let i = 0; i < 10; i++) {
    if ((await purgeInactiveIdentities(db, now - INACTIVE_IDENTITY_MS)) < 500) break;
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
   * Daily cron (wrangler.jsonc triggers): removes expired sync sessions,
   * tombstones not written for 400 days (bounded: at most 20 000 each) and
   * sync accounts without a login for 12 months (at most 5 000).
   */
  async scheduled(controller, env, _ctx): Promise<void> {
    if (!(env as { DB?: unknown }).DB) return;
    await dailyCleanup(env.DB, controller.scheduledTime || Date.now());
  },
} satisfies ExportedHandler<Env>;
