import { GoogleGenAI } from "@google/genai";
import type { Content, Part } from "@google/genai";

import type { Config } from "../config.js";
import type { AskRequest, DrawerQueryRequest, SseEvent } from "../types.js";
import { chipIntentPrefixForDrawer } from "./prompts.js";
import type { LLMProvider } from "./provider.js";
import { runGeminiAgentAsk, runGeminiAgentContinue } from "./geminiAgent.js";
import { runGeminiDrawerQuery } from "./geminiDrawer.js";

/**
 * Google Gemini provider. Uses a multi-turn agent loop with function
 * calling (Phase 3 tools) for `/v1/agent/ask` and `/continue`.
 */
export class GeminiProvider implements LLMProvider {
  readonly name = "gemini";
  readonly genai: GoogleGenAI;
  private readonly config: Config;

  constructor(config: Config) {
    if (!config.GEMINI_API_KEY) {
      throw new Error("GeminiProvider requires GEMINI_API_KEY to be set.");
    }
    this.genai = new GoogleGenAI({ apiKey: config.GEMINI_API_KEY });
    this.config = config;
  }

  async *ask(req: AskRequest, signal: AbortSignal): AsyncIterable<SseEvent> {
    yield* runGeminiAgentAsk(this.genai, this.config, req, signal);
  }

  async *continueAgent(
    req: import("../types.js").AgentContinueRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    yield* runGeminiAgentContinue(this.genai, this.config, req, signal);
  }

  async *queryDrawer(
    req: DrawerQueryRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    yield* runGeminiDrawerQuery(
      this.genai,
      this.config.GEMINI_MODEL,
      req,
      signal,
    );
  }
}

/* -------------------------------------------------------------------- */
/*  Content assembly                                                     */
/* -------------------------------------------------------------------- */

export function buildDrawerContents(req: DrawerQueryRequest): Content[] {
  const parts: Part[] = [];

  for (const item of req.items) {
    if (item.kind === "image") {
      parts.push({
        inlineData: { mimeType: item.image_mime, data: item.image_b64 },
      });
      const ocr = item.ocr_text ? `\nOCR: ${item.ocr_text}` : "";
      parts.push({
        text: `Item [${item.item_id}] (image${item.label ? `, "${item.label}"` : ""})${ocr}`,
      });
    } else if (item.kind === "text") {
      const chunks = item.chunks
        .map((c) => `[chunk ${c.chunk_id}]\n${c.text}`)
        .join("\n\n");
      parts.push({
        text: `Item [${item.item_id}] (text${item.label ? `, "${item.label}"` : ""}):\n${chunks}`,
      });
    } else {
      const chunks = (item.extracted_text_chunks ?? [])
        .map((c) => `[chunk ${c.chunk_id}]\n${c.text}`)
        .join("\n\n");
      parts.push({
        text: `Item [${item.item_id}] (URL ${item.url}${item.label ? `, "${item.label}"` : ""})${chunks ? `:\n${chunks}` : ""}`,
      });
    }
  }

  parts.push({
    text: [chipIntentPrefixForDrawer(req), `User: ${req.prompt}`]
      .filter(Boolean)
      .join("\n\n"),
  });

  return [{ role: "user", parts }];
}

/* -------------------------------------------------------------------- */
/*  Stream relay                                                         */
/* -------------------------------------------------------------------- */

type GeminiStream = Awaited<
  ReturnType<GoogleGenAI["models"]["generateContentStream"]>
>;

async function* relayGeminiStream(
  stream: GeminiStream,
  signal: AbortSignal,
): AsyncIterable<SseEvent> {
  let inputTokens = 0;
  let outputTokens = 0;
  let finishReason: "stop" | "tool_use" | "length" | "content_filter" = "stop";

  for await (const chunk of stream) {
    if (signal.aborted) return;

    const text = chunk.text;
    if (text) {
      yield { event: "token", data: { text } };
    }

    const usage = chunk.usageMetadata;
    if (usage) {
      if (usage.promptTokenCount != null) inputTokens = usage.promptTokenCount;
      if (usage.candidatesTokenCount != null) {
        outputTokens = usage.candidatesTokenCount;
      }
    }

    const reason = chunk.candidates?.[0]?.finishReason;
    if (reason) finishReason = mapFinishReason(String(reason));
  }

  yield {
    event: "done",
    data: {
      finish_reason: finishReason,
      usage: { input_tokens: inputTokens, output_tokens: outputTokens },
    },
  };
}

function mapFinishReason(
  reason: string,
): "stop" | "tool_use" | "length" | "content_filter" {
  switch (reason) {
    case "STOP":
      return "stop";
    case "MAX_TOKENS":
      return "length";
    case "SAFETY":
    case "RECITATION":
    case "BLOCKLIST":
    case "PROHIBITED_CONTENT":
    case "SPII":
      return "content_filter";
    default:
      return "stop";
  }
}
