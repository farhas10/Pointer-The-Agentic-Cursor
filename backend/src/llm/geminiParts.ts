import type {
  FunctionCall,
  GenerateContentResponse,
  Part,
} from "@google/genai";

/** User-visible text from response parts (skips thought / functionCall). */
export function visibleTextFromParts(parts: Part[] | undefined): string {
  if (!parts?.length) return "";
  return parts
    .filter((part) => part.text != null && part.thought !== true)
    .map((part) => part.text!)
    .join("");
}

/**
 * Function calls extracted from accumulated stream parts.
 *
 * Streaming splits a turn across chunks: a function call frequently lands in an
 * early chunk while the final chunk only carries usage metadata. Reading
 * `response.functionCalls` off the last chunk therefore misses real tool calls,
 * so we collect them from the parts we aggregated across every chunk.
 */
export function functionCallsFromParts(parts: Part[]): FunctionCall[] {
  return parts
    .filter((part): part is Part & { functionCall: FunctionCall } =>
      Boolean(part.functionCall),
    )
    .map((part) => part.functionCall);
}

/**
 * Model parts to persist for a tool-loop turn, preserving `thoughtSignature`
 * on functionCall parts (Gemini 3 rejects tool resume without it). Falls back
 * to reconstructing from bare function calls when no raw parts were captured.
 */
export function modelPartsFromAggregated(
  parts: Part[],
  fallbackCalls: FunctionCall[],
): Part[] {
  if (parts.some((part) => part.functionCall)) {
    return structuredClone(parts);
  }
  return fallbackCalls.map((call) => ({
    functionCall: { name: call.name, id: call.id, args: call.args },
  }));
}

export function visibleTextFromResponse(
  response: GenerateContentResponse,
): string {
  return visibleTextFromParts(response.candidates?.[0]?.content?.parts);
}

/**
 * Gemini 3 requires `thoughtSignature` on functionCall parts when resuming
 * a tool loop. Reconstructing parts from `response.functionCalls` drops it.
 */
export function modelPartsFromResponse(
  response: GenerateContentResponse,
): Part[] {
  const parts = response.candidates?.[0]?.content?.parts;
  if (parts?.some((part) => part.functionCall)) {
    return structuredClone(parts);
  }

  return (response.functionCalls ?? []).map((call) => ({
    functionCall: {
      name: call.name,
      id: call.id,
      args: call.args,
    },
  }));
}
