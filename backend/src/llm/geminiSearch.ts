import type { GoogleGenAI } from "@google/genai";

export interface WebSearchResult {
  text: string;
  sources: string[];
}

/**
 * One-shot Gemini call with Google Search grounding.
 * Used by the search_web agent tool.
 */
export async function runGeminiWebSearch(
  client: GoogleGenAI,
  model: string,
  query: string,
  signal: AbortSignal,
): Promise<WebSearchResult> {
  const prompt = [
    "You are a research assistant. Search the web and return a helpful summary.",
    "Include review themes, ratings, pros/cons, and notable details when relevant.",
    "Be factual. If results are mixed, say so. Keep the answer under 400 words.",
    "",
    `Research query: ${query}`,
  ].join("\n");

  const response = await client.models.generateContent({
    model,
    contents: prompt,
    config: {
      maxOutputTokens: 1024,
      abortSignal: signal,
      tools: [{ googleSearch: {} }],
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
      text: "No web results found for that query.",
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
