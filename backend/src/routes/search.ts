import { Hono } from "hono";

import { getConfig } from "../config.js";
import { GeminiProvider } from "../llm/gemini.js";
import { runGeminiWebSearch } from "../llm/geminiSearch.js";
import { getProvider } from "../llm/registry.js";
import { WebSearchRequestSchema } from "../types.js";

export const searchRoutes = new Hono();

searchRoutes.post("/search", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = WebSearchRequestSchema.safeParse(body);
  if (!parsed.success) {
    return c.json(
      { error: "invalid_request", issues: parsed.error.issues },
      400,
    );
  }

  const provider = getProvider();
  if (!(provider instanceof GeminiProvider)) {
    return c.json(
      {
        error: "unsupported",
        message: "Web search requires the Gemini provider.",
      },
      400,
    );
  }

  const config = getConfig();
  const controller = new AbortController();
  c.req.raw.signal.addEventListener("abort", () => controller.abort(), {
    once: true,
  });

  try {
    const result = await runGeminiWebSearch(
      provider.genai,
      config.GEMINI_MODEL,
      parsed.data.query,
      controller.signal,
    );
    return c.json(result);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Web search failed.";
    return c.json({ error: "search_failed", message }, 502);
  }
});
