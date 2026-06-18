import { Hono } from "hono";

import { GeminiProvider } from "../llm/gemini.js";
import { getProvider } from "../llm/registry.js";
import { redactAskRequest } from "../safety/redaction.js";
import { AgentContinueRequestSchema, AskRequestSchema } from "../types.js";
import { streamSse } from "./sse.js";

export const agentRoutes = new Hono();

agentRoutes.post("/ask", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = AskRequestSchema.safeParse(body);
  if (!parsed.success) {
    return c.json(
      { error: "invalid_request", issues: parsed.error.issues },
      400,
    );
  }

  const safe = redactAskRequest(parsed.data);
  // eslint-disable-next-line no-console
  console.log(
    `ask: prompt_len=${safe.prompt.length} chip=${safe.chip_intent ?? "none"} has_image=${Boolean(safe.image_b64)}`,
  );
  const controller = new AbortController();
  // Forward client disconnects.
  c.req.raw.signal.addEventListener("abort", () => controller.abort(), {
    once: true,
  });

  const events = getProvider().ask(safe, controller.signal);
  return streamSse(c, events, controller);
});

agentRoutes.post("/continue", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = AgentContinueRequestSchema.safeParse(body);
  if (!parsed.success) {
    return c.json(
      { error: "invalid_request", issues: parsed.error.issues },
      400,
    );
  }

  const provider = getProvider();
  if (!(provider instanceof GeminiProvider)) {
    return c.json(
      { error: "unsupported", message: "Agent continue requires Gemini provider." },
      400,
    );
  }

  const controller = new AbortController();
  c.req.raw.signal.addEventListener("abort", () => controller.abort(), {
    once: true,
  });

  const events = provider.continueAgent(parsed.data, controller.signal);
  return streamSse(c, events, controller);
});
