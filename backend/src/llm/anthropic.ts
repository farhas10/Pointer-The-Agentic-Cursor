import Anthropic from "@anthropic-ai/sdk";

import type { Config } from "../config.js";
import type { AskRequest, DrawerQueryRequest, SseEvent } from "../types.js";
import {
  ASK_SYSTEM_PROMPT,
  DRAWER_SYSTEM_PROMPT,
  chipIntentPrefix,
  chipIntentPrefixForDrawer,
} from "./prompts.js";
import type { LLMProvider } from "./provider.js";

type ContentBlockParam =
  | Anthropic.Messages.TextBlockParam
  | Anthropic.Messages.ImageBlockParam
  | Anthropic.Messages.ToolUseBlockParam
  | Anthropic.Messages.ToolResultBlockParam;

/**
 * Anthropic provider. Wraps the official SDK and emits SseEvents.
 *
 * Phase 1 supports text + a single image. Phase 4 will add tool use
 * here (the SDK already supports it; we just don't surface tool_use
 * events to the client until the action executor is in place).
 */
export class AnthropicProvider implements LLMProvider {
  readonly name = "anthropic";
  private readonly client: Anthropic;
  private readonly model: string;

  constructor(config: Config) {
    if (!config.ANTHROPIC_API_KEY) {
      throw new Error(
        "AnthropicProvider requires ANTHROPIC_API_KEY to be set.",
      );
    }
    this.client = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
    this.model = config.ANTHROPIC_MODEL;
  }

  async *ask(
    req: AskRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    const userContent = buildAskUserContent(req);
    const stream = await this.client.messages.stream(
      {
        model: this.model,
        max_tokens: 1024,
        system: ASK_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userContent }],
      },
      { signal },
    );

    yield* relayAnthropicStream(stream);
  }

  async *queryDrawer(
    req: DrawerQueryRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    const userContent = buildDrawerUserContent(req);
    const stream = await this.client.messages.stream(
      {
        model: this.model,
        max_tokens: 2048,
        system: DRAWER_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userContent }],
      },
      { signal },
    );

    yield* relayAnthropicStream(stream);
  }
}

/* -------------------------------------------------------------------- */
/*  Content assembly                                                     */
/* -------------------------------------------------------------------- */

function buildAskUserContent(req: AskRequest): ContentBlockParam[] {
  const blocks: ContentBlockParam[] = [];

  if (req.image_b64 && req.image_mime) {
    blocks.push({
      type: "image",
      source: {
        type: "base64",
        media_type: req.image_mime,
        data: req.image_b64,
      },
    });
  }

  const contextLines: string[] = [];
  if (req.app_context) {
    const { app_name, bundle_id, window_title, url } = req.app_context;
    if (app_name || bundle_id) {
      contextLines.push(`App: ${app_name ?? bundle_id}`);
    }
    if (window_title) contextLines.push(`Window: ${window_title}`);
    if (url) contextLines.push(`URL: ${url}`);
  }
  if (req.ax_snapshot) {
    const { role, subrole, title, value, selected_text, redacted } =
      req.ax_snapshot;
    if (role) contextLines.push(`Element role: ${role}${subrole ? `/${subrole}` : ""}`);
    if (title) contextLines.push(`Element title: ${title}`);
    if (selected_text) contextLines.push(`Selected text: ${selected_text}`);
    else if (value && !redacted) contextLines.push(`Element value: ${value}`);
    if (redacted) contextLines.push(`(secure content was redacted)`);
  }
  if (req.ambient_summary) {
    contextLines.push(`Recent activity: ${req.ambient_summary}`);
  }

  const prefix = chipIntentPrefix(req);
  const promptText = [
    contextLines.length ? `Context:\n${contextLines.join("\n")}` : null,
    prefix,
    `User: ${req.prompt}`,
  ]
    .filter(Boolean)
    .join("\n\n");

  blocks.push({ type: "text", text: promptText });
  return blocks;
}

function buildDrawerUserContent(req: DrawerQueryRequest): ContentBlockParam[] {
  const blocks: ContentBlockParam[] = [];

  for (const item of req.items) {
    if (item.kind === "image") {
      blocks.push({
        type: "image",
        source: {
          type: "base64",
          media_type: item.image_mime,
          data: item.image_b64,
        },
      });
      const ocr = item.ocr_text ? `\nOCR: ${item.ocr_text}` : "";
      blocks.push({
        type: "text",
        text: `Item [${item.item_id}] (image${item.label ? `, "${item.label}"` : ""})${ocr}`,
      });
    } else if (item.kind === "text") {
      const chunks = item.chunks
        .map((c) => `[chunk ${c.chunk_id}]\n${c.text}`)
        .join("\n\n");
      blocks.push({
        type: "text",
        text: `Item [${item.item_id}] (text${item.label ? `, "${item.label}"` : ""}):\n${chunks}`,
      });
    } else {
      const chunks = (item.extracted_text_chunks ?? [])
        .map((c) => `[chunk ${c.chunk_id}]\n${c.text}`)
        .join("\n\n");
      blocks.push({
        type: "text",
        text: `Item [${item.item_id}] (URL ${item.url}${item.label ? `, "${item.label}"` : ""})${chunks ? `:\n${chunks}` : ""}`,
      });
    }
  }

  const prefix = chipIntentPrefixForDrawer(req);
  blocks.push({
    type: "text",
    text: [prefix, `User: ${req.prompt}`].filter(Boolean).join("\n\n"),
  });

  return blocks;
}

/* -------------------------------------------------------------------- */
/*  Stream relay                                                         */
/* -------------------------------------------------------------------- */

type AnthropicStream = ReturnType<Anthropic["messages"]["stream"]>;

async function* relayAnthropicStream(
  stream: AnthropicStream,
): AsyncIterable<SseEvent> {
  let inputTokens = 0;
  let outputTokens = 0;
  let finishReason: "stop" | "tool_use" | "length" | "content_filter" = "stop";

  for await (const ev of stream) {
    if (ev.type === "content_block_delta" && ev.delta.type === "text_delta") {
      yield { event: "token", data: { text: ev.delta.text } };
    } else if (ev.type === "message_delta") {
      if (ev.usage?.output_tokens != null) {
        outputTokens = ev.usage.output_tokens;
      }
      if (ev.delta.stop_reason) {
        finishReason = mapStopReason(ev.delta.stop_reason);
      }
    } else if (ev.type === "message_start") {
      if (ev.message.usage?.input_tokens != null) {
        inputTokens = ev.message.usage.input_tokens;
      }
    }
  }

  yield {
    event: "done",
    data: {
      finish_reason: finishReason,
      usage: { input_tokens: inputTokens, output_tokens: outputTokens },
    },
  };
}

function mapStopReason(
  reason: string,
): "stop" | "tool_use" | "length" | "content_filter" {
  switch (reason) {
    case "end_turn":
    case "stop_sequence":
      return "stop";
    case "tool_use":
      return "tool_use";
    case "max_tokens":
      return "length";
    default:
      return "stop";
  }
}
