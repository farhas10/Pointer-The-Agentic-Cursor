import { Hono } from "hono";

import { getProvider } from "../llm/registry.js";
import { DrawerQueryRequestSchema } from "../types.js";
import { streamSse } from "./sse.js";

export const drawerRoutes = new Hono();

drawerRoutes.post("/query", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = DrawerQueryRequestSchema.safeParse(body);
  if (!parsed.success) {
    return c.json(
      { error: "invalid_request", issues: parsed.error.issues },
      400,
    );
  }

  const controller = new AbortController();
  c.req.raw.signal.addEventListener("abort", () => controller.abort(), {
    once: true,
  });

  const events = getProvider().queryDrawer(parsed.data, controller.signal);
  return streamSse(c, events, controller);
});
