import { Hono } from "hono";

import { getConfig } from "../config.js";
import { GeminiProvider } from "../llm/gemini.js";
import { runGeminiTranscribe } from "../llm/geminiTranscribe.js";
import { getProvider } from "../llm/registry.js";
import { TranscribeRequestSchema } from "../types.js";

export const transcribeRoutes = new Hono();

transcribeRoutes.post("/transcribe", async (c) => {
  const body = await c.req.json().catch(() => null);
  const parsed = TranscribeRequestSchema.safeParse(body);
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
        message: "Transcription requires the Gemini provider.",
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
    const result = await runGeminiTranscribe(
      provider.genai,
      config.GEMINI_MODEL,
      parsed.data.audio_b64,
      parsed.data.audio_mime,
      controller.signal,
    );
    return c.json(result);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Transcription failed.";
    return c.json({ error: "transcribe_failed", message }, 502);
  }
});
