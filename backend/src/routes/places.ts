import { Hono } from "hono";

import { getConfig } from "../config.js";
import { GeminiProvider } from "../llm/gemini.js";
import { runGeminiPlacesSearch } from "../llm/geminiPlaces.js";
import { getProvider } from "../llm/registry.js";
import { PlacesSearchRequestSchema } from "../types.js";

export const placesRoutes = new Hono();

placesRoutes.post("/places", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = PlacesSearchRequestSchema.safeParse(body);
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
        message: "Places search requires the Gemini provider.",
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
    const result = await runGeminiPlacesSearch(
      provider.genai,
      config.GEMINI_MODEL,
      parsed.data,
      controller.signal,
    );
    return c.json(result);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Places search failed.";
    return c.json({ error: "places_failed", message }, 502);
  }
});
