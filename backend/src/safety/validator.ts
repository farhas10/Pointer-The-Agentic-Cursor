import { z } from "zod";

/**
 * Tool-call safety validator. Every tool call the LLM emits flows
 * through `validateToolCall` before being relayed to the client.
 */

export type ToolCallTier = "safe" | "automation" | "destructive";

export interface ToolCallValidation {
  ok: boolean;
  tier: ToolCallTier;
  reason?: string;
}

export interface ToolCallContext {
  foregroundBundleId?: string;
}

const ToolNameSchema = z.enum([
  "copy_to_clipboard",
  "search_web",
  "search_places",
  "open_url",
  "paste_text",
  "replace_selection",
  "click_at",
  "type_text",
  "key_chord",
  "launch_app",
  "focus_app",
  "open_path",
  "list_directory",
  "run_applescript",
  "read_ax_tree",
  "find_ax_element",
  "ax_press",
  "ax_set_value",
  "ax_focus",
  "invoke_menu",
  "media_control",
  "run_shortcut",
]);

const COMPUTER_USE_TOOLS = new Set([
  "click_at",
  "type_text_at",
  "scroll_at",
  "wait_5_seconds",
  "key_combination",
  "hover_at",
  "drag_and_drop",
  "scroll_document",
  "go_forward",
  "go_back",
  "open_web_browser",
  "navigate",
  "search",
]);

const TIER: Record<z.infer<typeof ToolNameSchema>, ToolCallTier> = {
  copy_to_clipboard: "safe",
  search_web: "safe",
  search_places: "safe",
  open_url: "safe",
  paste_text: "automation",
  replace_selection: "automation",
  click_at: "automation",
  type_text: "automation",
  key_chord: "automation",
  launch_app: "safe",
  focus_app: "automation",
  open_path: "automation",
  list_directory: "safe",
  run_applescript: "destructive",
  read_ax_tree: "safe",
  find_ax_element: "safe",
  ax_press: "automation",
  ax_set_value: "automation",
  ax_focus: "automation",
  invoke_menu: "automation",
  media_control: "safe",
  run_shortcut: "automation",
};

const COMPUTER_USE_TIER: Record<string, ToolCallTier> = {
  click_at: "automation",
  type_text_at: "automation",
  scroll_at: "automation",
  wait_5_seconds: "safe",
  key_combination: "automation",
  hover_at: "automation",
  drag_and_drop: "destructive",
  scroll_document: "automation",
  go_forward: "automation",
  go_back: "automation",
  open_web_browser: "automation",
  navigate: "automation",
  search: "automation",
};

const PASSWORD_LIKE = /password|passwd|secret|api[_-]?key|token/i;
const PAYMENT_LIKE = /stripe|card.?number|cvv|cvc|checkout/i;
const SENSITIVE_PATH =
  /(^|\/)\.(ssh|gnupg|aws|kube)(\/|$)|keychain|\.env$/i;

export function validateToolCall(
  name: string,
  input: unknown,
  context?: ToolCallContext,
): ToolCallValidation {
  if (COMPUTER_USE_TOOLS.has(name)) {
    return validateComputerUseTool(name, input);
  }

  const parsed = ToolNameSchema.safeParse(name);
  if (!parsed.success) {
    return { ok: false, tier: "destructive", reason: `unknown tool ${name}` };
  }
  let tier = TIER[parsed.data];
  const record =
    input && typeof input === "object"
      ? (input as Record<string, unknown>)
      : {};

  if (parsed.data === "type_text" || parsed.data === "paste_text") {
    const text = typeof record.text === "string" ? record.text : "";
    if (PASSWORD_LIKE.test(text)) {
      return {
        ok: false,
        tier,
        reason: "refusing to type password-like content",
      };
    }
  }

  if (parsed.data === "run_applescript") {
    const script = typeof record.script === "string" ? record.script : "";
    if (PASSWORD_LIKE.test(script) || /do shell script/i.test(script)) {
      return {
        ok: false,
        tier,
        reason: "AppleScript blocked by safety policy",
      };
    }
  }

  if (parsed.data === "open_url") {
    const url = typeof record.url === "string" ? record.url : "";
    if (/javascript:/i.test(url) || /file:/i.test(url)) {
      return { ok: false, tier, reason: "blocked URL scheme" };
    }
  }

  if (parsed.data === "click_at") {
    const label =
      typeof record.label === "string" ? record.label.toLowerCase() : "";
    if (PAYMENT_LIKE.test(label)) {
      return { ok: false, tier, reason: "blocked click on payment surface" };
    }
  }

  if (parsed.data === "open_path" || parsed.data === "list_directory") {
    const path = typeof record.path === "string" ? record.path : "";
    if (SENSITIVE_PATH.test(path)) {
      return { ok: false, tier, reason: "blocked sensitive path" };
    }
  }

  if (parsed.data === "launch_app" || parsed.data === "focus_app") {
    const bundleId =
      typeof record.bundle_id === "string" ? record.bundle_id : "";
    const foreground = context?.foregroundBundleId;
    if (
      parsed.data === "focus_app" &&
      foreground &&
      bundleId &&
      bundleId !== foreground
    ) {
      tier = "destructive";
    }
  }

  if (parsed.data === "launch_app") {
    const bundleId =
      typeof record.bundle_id === "string" ? record.bundle_id : "";
    const foreground = context?.foregroundBundleId;
    if (foreground && bundleId && bundleId !== foreground) {
      tier = "automation";
    }
  }

  return { ok: true, tier };
}

function validateComputerUseTool(
  name: string,
  input: unknown,
): ToolCallValidation {
  const tier = COMPUTER_USE_TIER[name] ?? "automation";
  const record =
    input && typeof input === "object"
      ? (input as Record<string, unknown>)
      : {};

  if (name === "type_text_at") {
    const text = typeof record.text === "string" ? record.text : "";
    if (PASSWORD_LIKE.test(text)) {
      return {
        ok: false,
        tier,
        reason: "refusing to type password-like content",
      };
    }
  }

  if (name === "click_at" || name === "type_text_at" || name === "scroll_at") {
    for (const key of ["x", "y"] as const) {
      const value = record[key];
      if (typeof value !== "number" || value < 0 || value > 999) {
        return { ok: false, tier, reason: `invalid ${key} coordinate` };
      }
    }
  }

  return { ok: true, tier };
}
