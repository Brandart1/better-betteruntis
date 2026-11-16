/** Bindings and variables of the Worker (see wrangler.jsonc). */
export interface Env {
  /** Static assets: the Flutter web build. */
  ASSETS: Fetcher;
  /** Sync database (missing in web-only deployments, see index.ts). */
  DB: D1Database;
  /** Comma-separated WebUntis hosts the relay and the sync login may contact. */
  ALLOWED_HOSTS: string;
  /** Rate limit: sync session creation (per client IP). */
  RL_SESSION: RateLimit;
  /** Rate limit: WebUntis relay (per client IP). */
  RL_PROXY: RateLimit;
  /** Rate limit: every authenticated sync call (per identity). */
  RL_SYNC: RateLimit;
  /** Rate limit: sync writes, PUT notes and PUT/PATCH/DELETE e2e (per identity). */
  RL_WRITE: RateLimit;
  /** Rate limit: failed session lookups (per client IP); over it the IP is blocked before D1 is asked. */
  RL_AUTH: RateLimit;
  /** Public origin, e.g. https://bbu.example.org (CSRF origin check); may be empty. */
  PUBLIC_ORIGIN: string;
}
