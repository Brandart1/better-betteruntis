/** Bindings and variables of the Worker (see wrangler.jsonc). */
export interface Env {
  /** Static assets: the Flutter web build. */
  ASSETS: Fetcher;
  /** Sync database. */
  DB: D1Database;
  /** Comma-separated WebUntis hosts the relay and the sync login may contact. */
  ALLOWED_HOSTS: string;
  /** Rate limit: sync session creation (per client IP). */
  RL_SESSION: RateLimit;
  /** Rate limit: WebUntis relay (per client IP). */
  RL_PROXY: RateLimit;
  /** Rate limit: other sync calls (per session). */
  RL_SYNC: RateLimit;
  /** Public origin, e.g. https://bbu.example.org (CSRF origin check); may be empty. */
  PUBLIC_ORIGIN: string;
}
