import type { GoogleGenAI } from "@google/genai";

export interface TranscribeResult {
  text: string;
}

/**
 * Transcribe short voice clips via Gemini multimodal audio input.
 * Keeps Speech.framework off the Mac client (avoids on-device crashes).
 */
export async function runGeminiTranscribe(
  client: GoogleGenAI,
  model: string,
  audioB64: string,
  mimeType: string,
  signal: AbortSignal,
): Promise<TranscribeResult> {
  const response = await client.models.generateContent({
    model,
    contents: [
      {
        role: "user",
        parts: [
          {
            inlineData: {
              mimeType,
              data: audioB64,
            },
          },
          {
            text:
              "Transcribe the attached audio verbatim. " +
              "Output only the spoken words with normal punctuation. " +
              "No commentary or labels.",
          },
        ],
      },
    ],
    config: {
      maxOutputTokens: 512,
      abortSignal: signal,
    },
  });

  const text = response.text?.trim() ?? "";
  if (!text) {
    return { text: "" };
  }
  return { text };
}
