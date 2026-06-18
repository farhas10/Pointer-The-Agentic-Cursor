import type { MiddlewareHandler } from "hono";

import { getConfig } from "../config.js";

/**
 * Tiny in-memory token-bucket per remote IP. Adequate for development
 * and single-process deployments. Production deploys swap this for a
 * Redis-backed limiter; the interface is the same.
 */

interface Bucket {
  tokens: number;
  lastRefill: number;
}

const buckets = new Map<string, Bucket>();

export const rateLimitMiddleware: MiddlewareHandler = async (c, next) => {
  const config = getConfig();
  const ip = remoteIp(c);
  const now = Date.now();
  const bucket = buckets.get(ip) ?? {
    tokens: config.RATE_LIMIT_MAX,
    lastRefill: now,
  };

  // Refill linearly over the window.
  const elapsed = now - bucket.lastRefill;
  const refill = (elapsed / config.RATE_LIMIT_WINDOW_MS) * config.RATE_LIMIT_MAX;
  bucket.tokens = Math.min(config.RATE_LIMIT_MAX, bucket.tokens + refill);
  bucket.lastRefill = now;

  if (bucket.tokens < 1) {
    buckets.set(ip, bucket);
    return c.json({ error: "rate_limited" }, 429);
  }
  bucket.tokens -= 1;
  buckets.set(ip, bucket);
  await next();
};

function remoteIp(c: import("hono").Context): string {
  const fwd = c.req.header("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  // Hono Node adapter exposes the raw socket via env when run under
  // `@hono/node-server`; in unit tests (`app.request`) env is empty, so
  // fall through to a stable bucket key.
  const env = c.env as
    | { incoming?: { socket?: { remoteAddress?: string } } }
    | undefined;
  return env?.incoming?.socket?.remoteAddress ?? "unknown";
}

/** Test-only. */
export function resetRateLimitForTests(): void {
  buckets.clear();
}
