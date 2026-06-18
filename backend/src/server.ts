import { Hono } from "hono";

import { authMiddleware } from "./middleware/auth.js";
import { loggerMiddleware } from "./middleware/logger.js";
import { rateLimitMiddleware } from "./middleware/rateLimit.js";
import { agentRoutes } from "./routes/agent.js";
import { searchRoutes } from "./routes/search.js";
import { placesRoutes } from "./routes/places.js";
import { transcribeRoutes } from "./routes/transcribe.js";
import { drawerRoutes } from "./routes/drawer.js";
import { healthRoutes } from "./routes/health.js";

/**
 * Composes routes + middleware into a Hono app. Exported so tests can
 * spin one up without binding a port.
 */
export function createApp(): Hono {
  const app = new Hono();

  app.use("*", loggerMiddleware);

  app.route("/", healthRoutes);

  // Authenticated + rate-limited API surface.
  const v1 = new Hono();
  v1.use("*", authMiddleware);
  v1.use("*", rateLimitMiddleware);
  v1.route("/agent", agentRoutes);
  v1.route("/agent", searchRoutes);
  v1.route("/agent", placesRoutes);
  v1.route("/agent", transcribeRoutes);
  v1.route("/drawer", drawerRoutes);
  app.route("/v1", v1);

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((err, c) => {
    // eslint-disable-next-line no-console
    console.error("unhandled", err);
    return c.json({ error: "internal_error" }, 500);
  });

  return app;
}
