import { randomUUID } from "node:crypto";

import {
  createFunctionResponsePartFromBase64,
  Environment,
  type Content,
  type GenerateContentResponse,
  type GoogleGenAI,
  type Part,
} from "@google/genai";

import { resolveAgentMode, type AgentMode, isQaFastChip } from "../agent/agentMode.js";
import {
  appendUserTurn,
  createSession,
  deleteSession,
  getSession,
  getSessionByPanelId,
  type AgentSession,
} from "../agent/sessionStore.js";
import type { Config } from "../config.js";
import { validateToolCall } from "../safety/validator.js";
import type { AgentContinueRequest, AskRequest, SseEvent } from "../types.js";
import {
  functionCallsFromParts,
  modelPartsFromAggregated,
  visibleTextFromParts,
  visibleTextFromResponse,
} from "./geminiParts.js";
import {
  ASK_SYSTEM_PROMPT,
  AUTOMATION_SYSTEM_PROMPT,
  QA_TEXT_FALLBACK_PROMPT,
  chipIntentPrefix,
} from "./prompts.js";
import { phase4FunctionDeclarations } from "./tools.js";

const MAX_AGENT_TURNS = 8;

const AUTOMATION_CUSTOM_TOOLS = new Set([
  "search_web",
  "search_places",
  "open_url",
  "launch_app",
  "focus_app",
  "media_control",
  "run_shortcut",
  "copy_to_clipboard",
]);

const COMPUTER_USE_EXCLUDED = [
  "open_web_browser",
  "navigate",
  "search",
  "go_forward",
  "go_back",
];

export async function* runGeminiAgentAsk(
  client: GoogleGenAI,
  config: Config,
  req: AskRequest,
  signal: AbortSignal,
): AsyncIterable<SseEvent> {
  const mode = resolveAgentMode(req);
  if (mode === "automation" && !req.image_b64) {
    yield {
      event: "error",
      data: {
        message:
          "Screen capture is required for this action. Grant Screen Recording permission and try again.",
      },
    };
    return;
  }
  const turn = buildAskContents(req, mode);

  if (req.panel_session_id) {
    const existing = getSessionByPanelId(req.panel_session_id);
    if (existing) {
      existing.mode = mode;
      existing.chipIntent = req.chip_intent ?? existing.chipIntent;
      existing.screenWidth = req.screen_width;
      existing.screenHeight = req.screen_height;
      appendUserTurn(existing, structuredClone(turn));
      yield* runAgentTurn(client, config, existing, signal, {
        retainOnStop: true,
      });
      return;
    }
  }

  const session = createSession(
    structuredClone(turn),
    req.app_context?.bundle_id,
    req.panel_session_id,
    mode,
    req.screen_width,
    req.screen_height,
    req.chip_intent,
  );
  yield* runAgentTurn(client, config, session, signal, {
    retainOnStop: Boolean(req.panel_session_id),
  });
}

export async function* runGeminiAgentContinue(
  client: GoogleGenAI,
  config: Config,
  req: AgentContinueRequest,
  signal: AbortSignal,
): AsyncIterable<SseEvent> {
  const session = getSession(req.session_id);
  if (!session) {
    yield {
      event: "error",
      data: { message: "Agent session expired. Ask again to start over." },
    };
    return;
  }

  for (const result of req.tool_results) {
    session.contents.push(buildFunctionResponseContent(result));
  }

  yield* runAgentTurn(client, config, session, signal);
}

async function* runAgentTurn(
  client: GoogleGenAI,
  config: Config,
  session: AgentSession,
  signal: AbortSignal,
  opts: { retainOnStop?: boolean } = {},
): AsyncIterable<SseEvent> {
  let turns = 0;
  let retriedEmpty = false;
  const model = modelForMode(session.mode, config);
  const systemInstruction = systemPromptForMode(session.mode);
  const maxOutputTokens = session.mode === "automation" ? 2048 : 1024;
  const tools = toolsForSession(session);

  while (turns < MAX_AGENT_TURNS) {
    if (signal.aborted) return;
    turns += 1;

    const stream = await client.models.generateContentStream({
      model,
      contents: session.contents,
      config: {
        systemInstruction,
        maxOutputTokens,
        abortSignal: signal,
        ...(tools ? { tools } : {}),
      },
    });

    let response: GenerateContentResponse | undefined;
    let streamedText = "";
    // Function calls / thought-signatures can arrive in any chunk (often not
    // the last one), so accumulate every chunk's parts instead of trusting the
    // final chunk alone.
    const aggregatedParts: Part[] = [];
    for await (const chunk of stream) {
      if (signal.aborted) return;
      response = chunk;
      const chunkParts = chunk.candidates?.[0]?.content?.parts;
      if (chunkParts?.length) aggregatedParts.push(...chunkParts);
      // Each chunk's visible text is a delta, not cumulative — emit it directly.
      const delta = visibleTextFromResponse(chunk);
      if (delta) {
        streamedText += delta;
        yield { event: "token", data: { text: delta } };
      }
    }

    if (!response) {
      yield {
        event: "error",
        data: { message: "Empty response from Gemini." },
      };
      return;
    }

    const usage = response.usageMetadata;
    const usagePayload = usage
      ? {
          input_tokens: usage.promptTokenCount ?? 0,
          output_tokens: usage.candidatesTokenCount ?? 0,
        }
      : undefined;

    const calls = functionCallsFromParts(aggregatedParts);
    if (calls.length > 0) {
      session.contents.push({
        role: "model",
        parts: modelPartsFromAggregated(aggregatedParts, calls),
      });

      session.pendingToolIds = [];
      for (const call of calls) {
        const name = call.name ?? "unknown";
        const id = call.id ?? randomUUID();
        const validation = validateToolCall(name, call.args, {
          foregroundBundleId: session.foregroundBundleId,
        });
        if (!validation.ok) {
          session.contents.push({
            role: "user",
            parts: [
              {
                functionResponse: {
                  name,
                  id,
                  response: { error: validation.reason ?? "blocked" },
                },
              },
            ],
          });
          continue;
        }

        session.pendingToolIds.push(id);
        yield {
          event: "tool_call",
          data: {
            id,
            name,
            input: call.args ?? {},
            session_id: session.id,
            tier: validation.tier,
          },
        };
      }

      if (session.pendingToolIds.length > 0) {
        yield {
          event: "done",
          data: {
            finish_reason: "tool_use",
            usage: usagePayload,
            session_id: session.id,
            agent_mode: session.mode,
          },
        };
        return;
      }
      continue;
    }

    if (streamedText.length === 0) {
      const finalText = visibleTextFromParts(aggregatedParts);
      if (finalText.trim()) {
        yield { event: "token", data: { text: finalText } };
        streamedText = finalText;
      }
    }
    if (streamedText.length === 0) {
      if (!retriedEmpty && session.mode === "qa") {
        retriedEmpty = true;
        session.contents.push({
          role: "user",
          parts: [
            {
              text: "Your last response was empty. Reply in plain text or call the appropriate tool now.",
            },
          ],
        });
        continue;
      }

      if (isQaFastChip(session.chipIntent)) {
        const fallbackText = await oneShotTextFallback(
          client,
          config,
          session,
          signal,
        );
        if (fallbackText) {
          yield { event: "token", data: { text: fallbackText } };
          if (opts.retainOnStop) {
            session.contents.push({
              role: "model",
              parts: [{ text: fallbackText }],
            });
          } else {
            deleteSession(session.id);
          }
          yield {
            event: "done",
            data: {
              finish_reason: "stop",
              session_id: opts.retainOnStop ? session.id : undefined,
              agent_mode: session.mode,
            },
          };
          return;
        }
      }

      yield {
        event: "error",
        data: {
          message: emptyResponseMessage(session),
        },
      };
      return;
    }

    if (opts.retainOnStop) {
      // Persist the assistant turn so companion follow-ups send a valid
      // user → model → user history (otherwise Gemini sees back-to-back
      // user turns and rejects the request).
      session.contents.push({
        role: "model",
        parts: [{ text: streamedText }],
      });
    } else {
      deleteSession(session.id);
    }
    yield {
      event: "done",
      data: {
        finish_reason: "stop",
        usage: usagePayload,
        session_id: opts.retainOnStop ? session.id : undefined,
        agent_mode: session.mode,
      },
    };
    return;
  }

  if (!opts.retainOnStop) {
    deleteSession(session.id);
  }
  yield {
    event: "error",
    data: { message: "Agent exceeded maximum tool turns." },
  };
}

function systemPromptForMode(mode: AgentMode): string {
  return mode === "automation" ? AUTOMATION_SYSTEM_PROMPT : ASK_SYSTEM_PROMPT;
}

function modelForMode(mode: AgentMode, config: Config): string {
  return mode === "automation"
    ? config.GEMINI_AUTOMATION_MODEL
    : config.GEMINI_MODEL;
}

function toolsForSession(session: AgentSession) {
  if (session.mode === "automation") {
    return [
      {
        computerUse: {
          environment: Environment.ENVIRONMENT_DESKTOP,
          excludedPredefinedFunctions: COMPUTER_USE_EXCLUDED,
        },
      },
      {
        functionDeclarations: phase4FunctionDeclarations().filter(
          (tool) => tool.name && AUTOMATION_CUSTOM_TOOLS.has(tool.name),
        ),
      },
    ];
  }
  if (session.chipIntent && isQaFastChip(session.chipIntent)) {
    return undefined;
  }
  return [{ functionDeclarations: phase4FunctionDeclarations() }];
}

function buildFunctionResponseContent(
  result: AgentContinueRequest["tool_results"][number],
): Content {
  const responsePayload: Record<string, unknown> =
    result.result && typeof result.result === "object"
      ? { ...(result.result as Record<string, unknown>) }
      : { result: result.result };

  if (result.url) {
    responsePayload.url = result.url;
  }

  const parts: Part[] = [
    {
      functionResponse: {
        name: result.name,
        id: result.id,
        response: responsePayload,
        parts: result.screenshot_b64
          ? [
              createFunctionResponsePartFromBase64(
                result.screenshot_b64,
                result.screenshot_mime ?? "image/jpeg",
              ),
            ]
          : undefined,
      },
    },
  ];

  return { role: "user", parts };
}

function buildAskContents(req: AskRequest, mode: AgentMode): Content[] {
  const parts: Part[] = [];

  if (req.image_b64 && req.image_mime) {
    parts.push({
      inlineData: { mimeType: req.image_mime, data: req.image_b64 },
    });
  }

  const contextLines: string[] = [];
  if (mode === "automation" && req.screen_width && req.screen_height) {
    contextLines.push(
      `Screen: ${req.screen_width}x${req.screen_height} pixels (Computer Use grid 0–999 maps to this).`,
    );
  }
  if (req.app_context) {
    const { app_name, bundle_id, window_title, url } = req.app_context;
    if (app_name || bundle_id) contextLines.push(`App: ${app_name ?? bundle_id}`);
    if (window_title) contextLines.push(`Window: ${window_title}`);
    if (url) contextLines.push(`URL: ${url}`);
  }
  if (req.ax_snapshot) {
    const { role, subrole, title, value, selected_text, redacted } =
      req.ax_snapshot;
    const prefix = mode === "automation" ? "Element hint" : "Element";
    if (role) {
      contextLines.push(
        `${prefix}${mode === "automation" ? " — role" : " role"}: ${role}${subrole ? `/${subrole}` : ""}`,
      );
    }
    if (title) {
      contextLines.push(
        `${prefix}${mode === "automation" ? " — title" : " title"}: ${title}`,
      );
    }
    if (selected_text) contextLines.push(`Selected text: ${selected_text}`);
    else if (value && !redacted) {
      contextLines.push(
        `${prefix}${mode === "automation" ? " — value" : " value"}: ${value}`,
      );
    }
    if (redacted) contextLines.push(`(secure content was redacted)`);
  }
  if (req.ambient_summary) {
    contextLines.push(`Recent activity: ${req.ambient_summary}`);
  }
  if (req.location) {
    const { latitude, longitude, city, source } = req.location;
    if (latitude != null && longitude != null) {
      contextLines.push(
        `Location (${source}): ${latitude}, ${longitude}`,
      );
    } else if (city) {
      contextLines.push(`Location (${source}): ${city}`);
    }
  }
  if (req.adapter_hint) {
    contextLines.push(req.adapter_hint);
  }
  if (req.entity_context?.length) {
    const entityLines = req.entity_context.map(
      (e) =>
        `#${e.index} ${e.name}${e.subtitle ? ` — ${e.subtitle}` : ""}${e.url ? ` (${e.url})` : ""}`,
    );
    contextLines.push(
      `Panel entities (resolve "this/that/#N" to these):\n${entityLines.join("\n")}`,
    );
  }

  const promptText = [
    contextLines.length ? `Context:\n${contextLines.join("\n")}` : null,
    chipIntentPrefix(req),
    mode === "automation" ? automationDirective() : null,
    mode === "qa" ? actionDirective(req.prompt) : null,
    researchDirective(req.prompt),
    entityDirective(req),
    chainDirective(req.prompt),
    `User: ${req.prompt}`,
  ]
    .filter(Boolean)
    .join("\n\n");

  parts.push({ text: promptText });
  return [{ role: "user", parts }];
}

function automationDirective(): string {
  return (
    "INSTRUCTION: Use Computer Use UI actions (click_at, type_text_at, scroll_at) " +
    "based on the screenshot. Take one step at a time; a fresh screenshot follows each UI action."
  );
}

function actionDirective(prompt: string): string | null {
  if (
    /^\s*(open|launch|start|run|go to|switch to|focus|show|click|type|paste|list|navigate to)\b/i.test(
      prompt,
    )
  ) {
    return (
      "INSTRUCTION: This is an action command. Call the right tool now " +
      "(launch_app for open/launch, open_path for files/folders). " +
      "Do not ask for permission in your reply."
    );
  }
  if (
    /\b(skip|next song|pause|play|bold|italic|save|click|press|toggle|add slide|export)\b/i.test(
      prompt,
    )
  ) {
    return (
      "INSTRUCTION: Desktop action. Prefer ax_press / ax_set_value / invoke_menu / key_chord. " +
      "Execute tools immediately; do not only give instructions."
    );
  }
  return null;
}

function researchDirective(prompt: string): string | null {
  if (
    /\b(nearby|near me|around here|close to me|in this area|restaurants?|places? to eat|coworking)\b/i.test(
      prompt,
    )
  ) {
    return (
      "INSTRUCTION: Proximity query. Use search_places when location is in context; " +
      "otherwise ask ONE clarifying question (cuisine/area) then search_places or search_web. " +
      "Return a ranked list in the panel."
    );
  }
  if (
    /\b(reviews?|tell me more|more info|more about|what do people|is this good|worth it|compare|research|look up|find out|dive deeper|general sentiment)\b/i.test(
      prompt,
    )
  ) {
    return (
      "INSTRUCTION: The user wants information BEYOND what's on screen. " +
      "Extract the subject from context and call search_web with a specific query."
    );
  }
  return null;
}

function entityDirective(req: AskRequest): string | null {
  if (!req.entity_context?.length) return null;
  if (
    !/\b(that|this|#\d|first|second|third|fourth|fifth|last)\b/i.test(
      req.prompt,
    )
  ) {
    return null;
  }
  return (
    "INSTRUCTION: The user refers to a prior result (this/that/#N). " +
    "Use the matching Panel entity name and url in tool calls. " +
    "Do not ask which one they mean."
  );
}

function chainDirective(prompt: string): string | null {
  if (
    !/\b(then|into|and paste|paste into|chain|after that|summarize.+paste|copy.+mail|mail it)\b/i.test(
      prompt,
    )
  ) {
    return null;
  }
  return (
    "INSTRUCTION: Cross-app chain requested. Complete every step in order: " +
    "work in the source app, copy the result, focus the destination app, paste or act. " +
    "Do not stop after step one."
  );
}

function emptyResponseMessage(session: AgentSession): string {
  if (session.mode === "automation") {
    return (
      "Computer Use returned no output. Check Screen Recording permission and try again."
    );
  }
  if (isQaFastChip(session.chipIntent)) {
    return "Gemini didn't return an answer. Try again.";
  }
  return (
    "No answer from Gemini. For UI actions, Option+right-click the target and use Click it for me."
  );
}

async function oneShotTextFallback(
  client: GoogleGenAI,
  config: Config,
  session: AgentSession,
  signal: AbortSignal,
): Promise<string | null> {
  const lastUser = [...session.contents]
    .reverse()
    .find((content) => content.role === "user");
  if (!lastUser) return null;

  try {
    const response = await client.models.generateContent({
      model: config.GEMINI_MODEL,
      contents: [lastUser],
      config: {
        systemInstruction: QA_TEXT_FALLBACK_PROMPT,
        maxOutputTokens: 1024,
        abortSignal: signal,
      },
    });
    const text = visibleTextFromResponse(response).trim();
    return text || null;
  } catch {
    return null;
  }
}
