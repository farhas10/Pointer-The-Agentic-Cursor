import type { MiddlewareHandler } from "hono";

import { getConfig } from "../config.js";

/**
 * Phase 1 auth — pass-through unless `DEV_SHARED_SECRET` is set, in which
 * case we require a matching `Authorization: Bearer <secret>` header.
 *
 * Phase 5 swaps this for proper Sign-in-with-Apple JWT verification.
 */
export const authMiddleware: MiddlewareHandler = async (c, next) => {
  const config = getConfig();
  const required = config.DEV_SHARED_SECRET;
  if (!required) {
    await next();
    return;
  }

  const header = c.req.header("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/.exec(header);
  if (!match || match[1] !== required) {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
};
