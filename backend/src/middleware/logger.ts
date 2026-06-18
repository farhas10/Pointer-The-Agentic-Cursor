import type { MiddlewareHandler } from "hono";

/**
 * Single-line request log: method, path, status, ms.
 *
 * Intentionally does not log request bodies — request content is
 * considered sensitive (see threat model).
 */
export const loggerMiddleware: MiddlewareHandler = async (c, next) => {
  const start = performance.now();
  await next();
  const ms = (performance.now() - start).toFixed(1);
  const status = c.res.status;
  // eslint-disable-next-line no-console
  console.log(`${c.req.method} ${c.req.path} ${status} ${ms}ms`);
};
