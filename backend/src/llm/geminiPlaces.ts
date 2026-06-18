import type { GoogleGenAI } from "@google/genai";

import type { PlacesSearchRequest } from "../types.js";

export interface PlacesSearchResult {
  text: string;
  sources: string[];
}

/**
 * Gemini call with Google Maps grounding for proximity queries.
 */
export async function runGeminiPlacesSearch(
  client: GoogleGenAI,
  model: string,
  req: PlacesSearchRequest,
  signal: AbortSignal,
): Promise<PlacesSearchResult> {
  const locationLine =
    req.latitude != null && req.longitude != null
      ? `User location: ${req.latitude}, ${req.longitude}`
      : req.city
        ? `User area: ${req.city}`
        : "User location: unknown — ask one clarifying question if needed.";

  const prompt = [
    "You are a local places assistant. Use Google Maps to find real places.",
    "Return a ranked list (5–8 items) with name, one-line why, and rating if available.",
    "Be factual. Keep under 400 words.",
    "",
    locationLine,
    `Query: ${req.query}`,
  ].join("\n");

  const response = await client.models.generateContent({
    model,
    contents: prompt,
    config: {
      maxOutputTokens: 1024,
      abortSignal: signal,
      tools: [{ googleMaps: {} }],
    },
  });

  const text = response.text?.trim() ?? "";
  const metadata = response.candidates?.[0]?.groundingMetadata;
  const sources =
    metadata?.groundingChunks
      ?.map((chunk) => chunk.web?.uri ?? chunk.web?.title)
      .filter((s): s is string => Boolean(s)) ?? [];

  const uniqueSources = [...new Set(sources)].slice(0, 8);

  if (!text) {
    return {
      text: "No places found for that query.",
      sources: uniqueSources,
    };
  }

  const sourceBlock =
    uniqueSources.length > 0
      ? `\n\nSources:\n${uniqueSources.map((s) => `- ${s}`).join("\n")}`
      : "";

  return {
    text: text + sourceBlock,
    sources: uniqueSources,
  };
}
