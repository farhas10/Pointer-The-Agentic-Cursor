import { randomUUID } from "node:crypto";

import type { Content, GoogleGenAI } from "@google/genai";
import { modelPartsFromResponse } from "./geminiParts.js";

import type { DrawerQueryRequest, SseEvent } from "../types.js";
import { buildDrawerContents } from "./gemini.js";
import { runGeminiWebSearch } from "./geminiSearch.js";
import { DRAWER_SYSTEM_PROMPT } from "./prompts.js";
import { phase4FunctionDeclarations } from "./tools.js";

const MAX_DRAWER_TURNS = 3;

const searchWebDeclaration =
  phase4FunctionDeclarations().find((d) => d.name === "search_web") ??
  phase4FunctionDeclarations()[0]!;

/**
 * Drawer query with server-side web search fallback.
 * Turn 1: answer from items or call search_web.
 * Turn 2+: synthesize condensed answer from search results.
 */
export async function* runGeminiDrawerQuery(
  client: GoogleGenAI,
  model: string,
  req: DrawerQueryRequest,
  signal: AbortSignal,
): AsyncIterable<SseEvent> {
  const contents: Content[] = buildDrawerContents(req);
  let inputTokens = 0;
  let outputTokens = 0;

  for (let turn = 0; turn < MAX_DRAWER_TURNS; turn += 1) {
    if (signal.aborted) return;

    const response = await client.models.generateContent({
      model,
      contents,
      config: {
        systemInstruction: DRAWER_SYSTEM_PROMPT,
        maxOutputTokens: 2048,
        abortSignal: signal,
        tools: [{ functionDeclarations: [searchWebDeclaration] }],
      },
    });

    const usage = response.usageMetadata;
    if (usage) {
      if (usage.promptTokenCount != null) inputTokens = usage.promptTokenCount;
      if (usage.candidatesTokenCount != null) {
        outputTokens = usage.candidatesTokenCount;
      }
    }

    const calls = response.functionCalls ?? [];
    if (calls.length === 0) {
      const text = response.text?.trim();
      if (text) {
        yield { event: "token", data: { text } };
      }
      yield {
        event: "done",
        data: {
          finish_reason: "stop",
          usage: { input_tokens: inputTokens, output_tokens: outputTokens },
        },
      };
      return;
    }

    contents.push({
      role: "model",
      parts: modelPartsFromResponse(response),
    });

    for (const call of calls) {
      const name = call.name ?? "unknown";
      const id = call.id ?? randomUUID();

      if (name !== "search_web") {
        contents.push({
          role: "user",
          parts: [
            {
              functionResponse: {
                name,
                id,
                response: { error: "Only search_web is available in drawer mode." },
              },
            },
          ],
        });
        continue;
      }

      const query =
        typeof call.args?.query === "string" && call.args.query.trim()
          ? call.args.query.trim()
          : req.prompt;

      yield {
        event: "tool_call",
        data: {
          id,
          name: "search_web",
          input: { query },
          session_id: req.drawer_id,
          tier: "safe",
        },
      };

      const search = await runGeminiWebSearch(client, model, query, signal);
      contents.push({
        role: "user",
        parts: [
          {
            functionResponse: {
              name: "search_web",
              id,
              response: { result: search.text },
            },
          },
        ],
      });
    }
  }

  yield {
    event: "error",
    data: { message: "Drawer search took too many steps. Try a shorter question." },
  };
}
