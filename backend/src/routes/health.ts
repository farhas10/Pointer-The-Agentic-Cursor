import { Hono } from "hono";

import { getProvider } from "../llm/registry.js";

export const healthRoutes = new Hono();

healthRoutes.get("/healthz", (c) =>
  c.json({ ok: true, provider: getProvider().name }),
);
