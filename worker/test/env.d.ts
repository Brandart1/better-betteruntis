// Types of `env` in tests (cloudflare:workers / cloudflare:test).
declare namespace Cloudflare {
  interface Env {
    ASSETS: Fetcher;
    DB: D1Database;
    ALLOWED_HOSTS: string;
    PUBLIC_ORIGIN: string;
    RL_SESSION: RateLimit;
    RL_PROXY: RateLimit;
    RL_SYNC: RateLimit;
    RL_WRITE: RateLimit;
    RL_AUTH: RateLimit;
    TEST_MIGRATIONS: import("@cloudflare/vitest-plugin").D1Migration[];
  }
}
